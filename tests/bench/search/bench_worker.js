"use strict";

// Runs exactly one measurement (an index-build phase, or one query case) and prints its
// record as a single JSON line to stdout. Spawned per-case by bench_scoring.js under a
// wall-clock timeout, so a pathological input (the sloppy Levendist scorer's partialRatio
// is O(queryLen) windows of O(targetLen^2) Levenshtein calls -- a 10,000-char query turns
// this into 10^9-10^12 ops depending on entry count) gets killed and recorded as
// "timed_out" by the parent instead of hanging or crashing the whole benchmark run.

const fs = require("fs");
const path = require("path");
const { loadFuzzySort, loadLevendist } = require("./load_source.js");

const QS = path.join(__dirname, "..", "..", "..", "dots", ".config", "quickshell", "koompi");
const FuzzySort = loadFuzzySort(path.join(QS, "modules", "common", "functions", "fuzzysort.js"));
const Levendist = loadLevendist(path.join(QS, "modules", "common", "functions", "levendist.js"));

const FIXTURES_DIR = path.join(__dirname, "fixtures");

const WARMUP = 20;
const MEASURED = 200;
const CLIP_THRESHOLD = 0.2; // Cliphist.qml:17 scoreThreshold
const APP_THRESHOLD = 0.2; // AppSearch.qml:14 scoreThreshold
const FILE_THRESHOLD = 0.5; // FileSearch.qml:27 scoreThreshold

// mirrors Cliphist.qml:23-43 fuzzyQuery, both branches, entries/preparedEntries
function cliphistFuzzyQuery(mode, search, entries, preparedEntries) {
    if (search.trim() === "") return entries;
    if (mode === "sloppy") {
        const results = entries
            .slice(0, 100)
            .map(str => ({ entry: str, score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase()) }))
            .filter(item => item.score > CLIP_THRESHOLD)
            .sort((a, b) => b.score - a.score);
        return results.map(item => item.entry);
    }
    return FuzzySort.go(search, preparedEntries, { all: true, key: "name" }).map(r => r.obj.entry);
}

// mirrors Cliphist.qml:19-22 preparedEntries
function cliphistPrepare(entries) {
    return entries.map(a => ({ name: FuzzySort.prepare(`${a.replace(/^\s*\S+\s+/, "")}`), entry: a }));
}

// mirrors AppSearch.qml:61-78 fuzzyQuery, both branches, list/preppedNames -- no empty-search early return
function appSearchFuzzyQuery(mode, search, list, preppedNames) {
    if (mode === "sloppy") {
        const results = list
            .map(obj => ({ entry: obj, score: Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase()) }))
            .filter(item => item.score > APP_THRESHOLD)
            .sort((a, b) => b.score - a.score);
        return results.map(item => item.entry);
    }
    return FuzzySort.go(search, preppedNames, { all: true, key: "name" }).map(r => r.obj.entry);
}

// mirrors AppSearch.qml:51-54 preppedNames
function appSearchPrepare(list) {
    return list.map(a => ({ name: FuzzySort.prepare(`${a.name} `), entry: a }));
}

// mirrors FileSearch.qml:29-38 fuzzyRecents, single branch, threshold+limit:20
function fileSearchFuzzyRecents(search, recents, preparedRecents) {
    if (search.trim() === "") return recents.slice(0, 20);
    return FuzzySort.go(search, preparedRecents, { all: true, key: "name", threshold: FILE_THRESHOLD, limit: 20 }).map(r => r.obj.entry);
}

// mirrors FileSearch.qml:20-23 preparedRecents
function fileSearchPrepare(recents) {
    return recents.map(entry => ({ name: FuzzySort.prepare(entry.name), entry }));
}

const DOMAINS = {
    clipboard: { modes: ["default", "sloppy"], prepare: cliphistPrepare, run: (mode, search, entries, prepared) => cliphistFuzzyQuery(mode, search, entries, prepared) },
    apps: { modes: ["default", "sloppy"], prepare: appSearchPrepare, run: (mode, search, entries, prepared) => appSearchFuzzyQuery(mode, search, entries, prepared) },
    files: { modes: ["default"], prepare: fileSearchPrepare, run: (_mode, search, entries, prepared) => fileSearchFuzzyRecents(search, entries, prepared) },
};

function percentile(sortedMs, p) {
    const idx = Math.min(sortedMs.length - 1, Math.max(0, Math.ceil((p / 100) * sortedMs.length) - 1));
    return sortedMs[idx];
}

function stats(samplesNs) {
    const ms = samplesNs.map(n => Number(n) / 1e6).sort((a, b) => a - b);
    const mean = ms.reduce((a, b) => a + b, 0) / ms.length;
    const variance = ms.reduce((a, b) => a + (b - mean) ** 2, 0) / ms.length;
    return {
        p50Ms: percentile(ms, 50),
        p95Ms: percentile(ms, 95),
        p99Ms: percentile(ms, 99),
        meanMs: mean,
        stddevMs: Math.sqrt(variance),
    };
}

function heapDelta(fn) {
    if (typeof global.gc !== "function") {
        return { heapDeltaBytes: null, heapDeltaAvailable: false, heapDeltaNote: "V8-engine proxy, not a QML-engine number; run with node --expose-gc to populate" };
    }
    global.gc();
    const before = process.memoryUsage().heapUsed;
    fn();
    global.gc();
    const after = process.memoryUsage().heapUsed;
    return { heapDeltaBytes: after - before, heapDeltaAvailable: true, heapDeltaNote: "V8-engine proxy, not a QML-engine number" };
}

function timeBatch(fn) {
    for (let i = 0; i < WARMUP; i++) fn();
    const samples = new Array(MEASURED);
    for (let i = 0; i < MEASURED; i++) {
        const t0 = process.hrtime.bigint();
        fn();
        samples[i] = process.hrtime.bigint() - t0;
    }
    return samples;
}

function main() {
    const [, , kind, domain, mode, size, queryCaseArg] = process.argv;
    const cfg = DOMAINS[domain];
    const fixture = JSON.parse(fs.readFileSync(path.join(FIXTURES_DIR, `${domain}-${size}.json`), "utf8"));
    const entries = fixture.entries;

    if (kind === "index-build") {
        let prepared;
        const buildSamples = timeBatch(() => { prepared = cfg.prepare(entries); });
        const buildHeap = heapDelta(() => cfg.prepare(entries));
        const record = { phase: "index-build", domain, mode, size, entryCount: fixture.entryCount, iterations: MEASURED, ...stats(buildSamples), ...buildHeap };
        process.stdout.write(JSON.stringify(record) + "\n");
        return;
    }

    // kind === "query"
    const q = fixture.queries.find(q => q.case === queryCaseArg);
    let prepared = null;
    if (mode === "default") prepared = cfg.prepare(entries);

    let result;
    const samples = timeBatch(() => { result = cfg.run(mode, q.query, entries, prepared); });
    const heap = heapDelta(() => cfg.run(mode, q.query, entries, prepared));
    const record = { phase: "query", domain, mode, size, queryCase: q.case, entryCount: fixture.entryCount, iterations: MEASURED, resultCount: result.length, ...stats(samples), ...heap };
    process.stdout.write(JSON.stringify(record) + "\n");
}

main();
