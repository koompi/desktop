"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync, spawnSync } = require("child_process");

const FIXTURES_DIR = path.join(__dirname, "fixtures");
const OUT_DIR = path.join(__dirname, "..", "..", "..", ".work", "bench", "search");
const WORKER = path.join(__dirname, "bench_worker.js");

// Every case (an index-build phase, or one query case) runs in its own child process under
// this wall-clock budget. levendist.js:52-67 partialRatio slides a shortS-length window
// across the whole query and runs O(shortS^2) levenshteinDistance per window; the
// "very-long-10k" fixture query (10,000 chars) against sloppy mode's uncapped/near-uncapped
// entry lists turns this into 10^9-10^12 ops depending on entry count, which no fixed
// iteration count or in-process timer can safely bound. A case that runs past this budget
// is killed and recorded with status:"timed_out" instead of hanging or crashing the whole
// run. fuzzysort's default-mode path rejects a too-long search against a short target
// near-instantly and has never approached this budget on any (domain,mode,size) combo here.
const CASE_TIMEOUT_MS = 15000;

const DOMAIN_MODES = {
    clipboard: ["default", "sloppy"],
    apps: ["default", "sloppy"],
    files: ["default"],
};

const SIZES = ["empty", "small", "current-scale", "stress"];

function runWorker(kind, domain, mode, size, queryCase) {
    const args = queryCase === undefined ? [kind, domain, mode, size] : [kind, domain, mode, size, queryCase];
    const started = process.hrtime.bigint();
    const result = spawnSync(process.execPath, ["--expose-gc", WORKER, ...args], {
        cwd: __dirname,
        timeout: CASE_TIMEOUT_MS,
        killSignal: "SIGKILL",
        encoding: "utf8",
        maxBuffer: 16 * 1024 * 1024,
    });
    const wallMs = Number(process.hrtime.bigint() - started) / 1e6;

    if (result.error && result.error.code === "ETIMEDOUT") {
        return { timedOut: true, wallMs };
    }
    if (result.signal) {
        return { timedOut: true, signal: result.signal, wallMs, stderr: result.stderr };
    }
    if (result.status !== 0) {
        return { errored: true, status: result.status, wallMs, stderr: result.stderr };
    }
    const line = (result.stdout || "").trim().split("\n").filter(Boolean).pop();
    try {
        return { record: JSON.parse(line), wallMs };
    } catch (err) {
        return { errored: true, wallMs, stderr: `unparseable stdout: ${JSON.stringify(result.stdout)}\nstderr: ${result.stderr}` };
    }
}

function timedOutRecord(phase, domain, mode, size, entryCount, extra, outcome) {
    return {
        phase, domain, mode, size, entryCount,
        status: outcome.timedOut ? "timed_out" : "error",
        timeoutMs: outcome.timedOut ? CASE_TIMEOUT_MS : undefined,
        wallMs: outcome.wallMs,
        signal: outcome.signal,
        errorStderr: outcome.stderr ? outcome.stderr.slice(0, 2000) : undefined,
        ...extra,
    };
}

function gitRev() {
    try {
        return execFileSync("git", ["rev-parse", "HEAD"], { cwd: __dirname, encoding: "utf8" }).trim();
    } catch {
        return "unknown";
    }
}

function main() {
    fs.mkdirSync(OUT_DIR, { recursive: true });
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const meta = { gitRev: gitRev(), nodeVersion: process.version, hostname: os.hostname() };
    const runStarted = Date.now();

    const writtenFiles = [];
    let casesOk = 0;
    let casesTimedOut = 0;
    let casesErrored = 0;

    for (const [domain, modes] of Object.entries(DOMAIN_MODES)) {
        for (const mode of modes) {
            for (const size of SIZES) {
                const fixture = JSON.parse(fs.readFileSync(path.join(FIXTURES_DIR, `${domain}-${size}.json`), "utf8"));
                const entryCount = fixture.entryCount;
                const records = [{ type: "meta", ...meta, domain, mode, size, entryCount, timestamp }];

                if (mode === "default") {
                    const outcome = runWorker("index-build", domain, mode, size);
                    if (outcome.record) { records.push(outcome.record); casesOk++; }
                    else {
                        records.push(timedOutRecord("index-build", domain, mode, size, entryCount, {}, outcome));
                        outcome.timedOut ? casesTimedOut++ : casesErrored++;
                    }
                }

                for (const q of fixture.queries) {
                    const outcome = runWorker("query", domain, mode, size, q.case);
                    if (outcome.record) { records.push(outcome.record); casesOk++; }
                    else {
                        records.push(timedOutRecord("query", domain, mode, size, entryCount, { queryCase: q.case }, outcome));
                        outcome.timedOut ? casesTimedOut++ : casesErrored++;
                        if (!outcome.timedOut) console.error(`ERRORED ${domain}/${mode}/${size}/${q.case}: ${outcome.stderr}`);
                        else console.error(`TIMED OUT (${CASE_TIMEOUT_MS}ms budget) ${domain}/${mode}/${size}/${q.case} after ${outcome.wallMs.toFixed(0)}ms wall`);
                    }
                }

                const outFile = path.join(OUT_DIR, `scoring-${domain}-${mode}-${size}-${timestamp}.ndjson`);
                fs.writeFileSync(outFile, records.map(r => JSON.stringify(r)).join("\n") + "\n");
                writtenFiles.push(outFile);
            }
        }
    }

    const wallSec = ((Date.now() - runStarted) / 1000).toFixed(1);
    console.log(`\n${casesOk} cases completed, ${casesTimedOut} timed out, ${casesErrored} errored, over ${wallSec}s wall time`);
    console.log(`gc-exposed (workers run with --expose-gc): true`);
    console.log(`run timestamp: ${timestamp}`);
    console.log(`wrote ${writtenFiles.length} files under ${path.relative(process.cwd(), OUT_DIR)}:`);
    for (const f of writtenFiles) console.log(`  ${path.relative(process.cwd(), f)}`);

    if (casesErrored > 0) process.exit(1);
}

main();
