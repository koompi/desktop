"use strict";

// Protocol-level A/B counterpart to bench_scoring.js: spawns the real
// searchd binary, drives it exactly the way SearchDaemon.qml will (NDJSON
// over stdio), and times full round trips (write -> daemon scores -> JSON
// reply parsed) for the same fixtures and query cases bench_scoring.js
// measures in-process. Output is the same NDJSON record shape with
// mode:"daemon", so compare.js diffs the two directly.
//
// clipboard/apps: the fixture's entries are pushed once via "update" (the
// same wholesale-replace SearchDaemon.qml sends on a Cliphist/AppSearch
// change), then every query case is timed as a real search round trip.
//
// files: searchd owns its own index, walked from the real $HOME - it has no
// "load this fixture" affordance (see searchd/PROTOCOL.md's index-ownership
// section), so there is no fixture-for-fixture comparison to make here. What
// this measures instead is real round-trip latency against whatever the
// live index holds, at the same query cases, which is the honest
// like-for-like question for files anyway: FileSearch.qml never ran
// fuzzysort against live filesystem results in the first place (only
// fuzzyRecents, over the XBEL list, does, and that path is untouched by this
// daemon), so the real comparison is against `fd`'s fork+walk cost, not
// against a JS scoring baseline.

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const os = require("os");
const { execFileSync } = require("child_process");

const FIXTURES_DIR = path.join(__dirname, "fixtures");
const OUT_DIR = path.join(__dirname, "..", "..", "..", ".work", "bench", "search");
const SEARCHD = process.env.SEARCHD || path.join(__dirname, "..", "..", "..", "dots", ".config", "quickshell", "koompi", "scripts", "searchd", "zig-out", "bin", "searchd");

const WARMUP = 20;
const MEASURED = 200;
const DAEMON_TIMEOUT_MS = 30000;

function cliphistName(raw) {
    return raw.replace(/^\s*\S+\s+/, "");
}

class Daemon {
    constructor(bin) {
        this.proc = spawn(bin, [], { stdio: ["pipe", "pipe", "inherit"] });
        this.buf = "";
        // The daemon starts emitting the instant it's spawned, synchronously
        // ahead of this constructor's caller ever calling recv() - a queue
        // that only resolves an already-waiting recv() would silently drop
        // whatever arrives first. Every parsed line goes in pending; recv()
        // drains that before it ever waits on new data.
        this.pending = [];
        this.waiters = [];
        this.proc.stdout.on("data", (chunk) => {
            this.buf += chunk.toString("utf8");
            let nl;
            while ((nl = this.buf.indexOf("\n")) >= 0) {
                const line = this.buf.slice(0, nl);
                this.buf = this.buf.slice(nl + 1);
                if (line.trim() === "") continue;
                const msg = JSON.parse(line);
                const w = this.waiters.shift();
                if (w) w(msg);
                else this.pending.push(msg);
            }
        });
    }

    recv() {
        if (this.pending.length > 0) return Promise.resolve(this.pending.shift());
        return new Promise((resolve) => this.waiters.push(resolve));
    }

    send(obj) {
        this.proc.stdin.write(JSON.stringify(obj) + "\n");
    }

    async call(obj) {
        this.send(obj);
        return this.recv();
    }

    async close() {
        this.send({ cmd: "quit", id: -1 });
        await new Promise((resolve) => this.proc.once("exit", resolve));
    }
}

function percentile(sortedMs, p) {
    const idx = Math.min(sortedMs.length - 1, Math.max(0, Math.ceil((p / 100) * sortedMs.length) - 1));
    return sortedMs[idx];
}

function stats(samplesNs) {
    const ms = samplesNs.map((n) => Number(n) / 1e6).sort((a, b) => a - b);
    const mean = ms.reduce((a, b) => a + b, 0) / ms.length;
    const variance = ms.reduce((a, b) => a + (b - mean) ** 2, 0) / ms.length;
    return { p50Ms: percentile(ms, 50), p95Ms: percentile(ms, 95), p99Ms: percentile(ms, 99), meanMs: mean, stddevMs: Math.sqrt(variance) };
}

async function timeRoundTrips(daemon, service, queryCase) {
    const run = async () => {
        const t0 = process.hrtime.bigint();
        const reply = await daemon.call({ cmd: "search", id: 1, service, query: queryCase.query, limit: 30 });
        const t1 = process.hrtime.bigint();
        return { dt: t1 - t0, reply };
    };
    for (let i = 0; i < WARMUP; i++) await run();
    const samples = new Array(MEASURED);
    let lastReply;
    for (let i = 0; i < MEASURED; i++) {
        const { dt, reply } = await run();
        samples[i] = dt;
        lastReply = reply;
    }
    return { samples, lastReply };
}

async function benchClipboardOrApps(daemon, domain, service, gitRev, timestamp) {
    const records = [];
    for (const size of ["empty", "small", "current-scale", "stress"]) {
        const fixture = JSON.parse(fs.readFileSync(path.join(FIXTURES_DIR, `${domain}-${size}.json`), "utf8"));
        const pairs = fixture.entries.map((e) =>
            domain === "clipboard" ? { id: e, name: cliphistName(e) } : { id: e.id, name: e.name }
        );

        const updateStart = process.hrtime.bigint();
        const updateReply = await daemon.call({ cmd: "update", id: 1, service, entries: pairs });
        const updateMs = Number(process.hrtime.bigint() - updateStart) / 1e6;
        if (!updateReply.ok) throw new Error(`update ${domain}/${size} failed: ${JSON.stringify(updateReply)}`);
        records.push({ phase: "index-build", domain, mode: "daemon", size, entryCount: fixture.entryCount, updateMs });

        for (const q of fixture.queries) {
            const { samples, lastReply } = await timeRoundTrips(daemon, service, q);
            records.push({
                phase: "query", domain, mode: "daemon", size, queryCase: q.case,
                entryCount: fixture.entryCount, iterations: MEASURED,
                resultCount: lastReply.ok ? lastReply.results.length : -1,
                ...stats(samples),
            });
        }
    }

    const meta = { gitRev, nodeVersion: process.version, hostname: os.hostname(), domain, mode: "daemon", timestamp };
    const outFile = path.join(OUT_DIR, `daemon-${domain}-${timestamp}.ndjson`);
    fs.writeFileSync(outFile, [JSON.stringify({ type: "meta", ...meta }), ...records.map((r) => JSON.stringify(r))].join("\n") + "\n");
    return outFile;
}

async function benchFiles(daemon, gitRev, timestamp) {
    // No fixture load for files - see the file header. Query cases mirror
    // gen_fixtures.js's buildQueries shape so the record keys line up, but
    // "size" here means nothing beyond "the live index at the time this ran"
    // - labeled "live" rather than one of the fixture sizes so compare.js's
    // pairing (which matches on domain|mode|size|queryCase) does not
    // silently pretend this is comparable to a fixture-size JS run.
    const queries = [
        { case: "no-match", query: "zzznomatch-files-xyz999" },
        { case: "short-common", query: "report" },
        { case: "single-char", query: "a" },
    ];
    const records = [];
    for (const q of queries) {
        const { samples, lastReply } = await timeRoundTrips(daemon, "files", q);
        records.push({
            phase: "query", domain: "files", mode: "daemon", size: "live", queryCase: q.case,
            resultCount: lastReply.ok ? lastReply.results.length : -1,
            totalMatches: lastReply.ok ? lastReply.total : -1,
            ...stats(samples),
        });
    }
    const meta = { gitRev, nodeVersion: process.version, hostname: os.hostname(), domain: "files", mode: "daemon", timestamp };
    const outFile = path.join(OUT_DIR, `daemon-files-live-${timestamp}.ndjson`);
    fs.writeFileSync(outFile, [JSON.stringify({ type: "meta", ...meta }), ...records.map((r) => JSON.stringify(r))].join("\n") + "\n");
    return outFile;
}

function gitRev() {
    try {
        return execFileSync("git", ["rev-parse", "HEAD"], { cwd: __dirname, encoding: "utf8" }).trim();
    } catch {
        return "unknown";
    }
}

async function main() {
    if (!fs.existsSync(SEARCHD)) {
        console.error(`searchd binary not found at ${SEARCHD} - run 'zig build' in scripts/searchd first`);
        process.exit(1);
    }
    fs.mkdirSync(OUT_DIR, { recursive: true });
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const rev = gitRev();

    const daemon = new Daemon(SEARCHD);
    const timeout = setTimeout(() => {
        console.error(`daemon did not respond within ${DAEMON_TIMEOUT_MS}ms`);
        process.exit(1);
    }, DAEMON_TIMEOUT_MS);

    const hello = await daemon.recv();
    console.log("hello:", hello);
    const filesState = await daemon.recv();
    console.log("files state:", filesState);
    await daemon.recv(); // clipboard state
    await daemon.recv(); // apps state

    const written = [];
    written.push(await benchClipboardOrApps(daemon, "clipboard", "clipboard", rev, timestamp));
    written.push(await benchClipboardOrApps(daemon, "apps", "apps", rev, timestamp));
    written.push(await benchFiles(daemon, rev, timestamp));

    clearTimeout(timeout);
    await daemon.close();

    console.log(`wrote ${written.length} files:`);
    for (const f of written) console.log(`  ${path.relative(process.cwd(), f)}`);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
