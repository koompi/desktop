"use strict";

const fs = require("fs");
const path = require("path");

function expandGlob(pattern) {
    if (fs.existsSync(pattern) && !pattern.includes("*")) return [pattern];
    const dir = path.dirname(pattern);
    const base = path.basename(pattern);
    const re = new RegExp("^" + base.split("*").map(s => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$");
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir).filter(f => re.test(f)).map(f => path.join(dir, f)).sort();
}

function readRun(patternOrFile) {
    const files = expandGlob(patternOrFile);
    if (files.length === 0) throw new Error(`no files matched: ${patternOrFile}`);
    const records = new Map();
    for (const file of files) {
        const lines = fs.readFileSync(file, "utf8").split("\n").filter(l => l.trim() !== "");
        for (const line of lines) {
            const rec = JSON.parse(line);
            if (rec.type === "meta") continue;
            const key = rec.phase === "index-build"
                ? `${rec.domain}|${rec.mode}|${rec.size}|index-build`
                : `${rec.domain}|${rec.mode}|${rec.size}|${rec.queryCase}`;
            records.set(key, rec);
        }
    }
    return { files, records };
}

function pctDelta(before, after) {
    if (before === 0) return after === 0 ? 0 : Infinity;
    return ((after - before) / before) * 100;
}

function parseArgs(argv) {
    const positional = [];
    let gate = 25;
    for (const arg of argv) {
        const m = /^--gate=(\d+(\.\d+)?)$/.exec(arg);
        if (m) gate = Number(m[1]);
        else positional.push(arg);
    }
    if (positional.length !== 2) {
        console.error("usage: node compare.js <before-run-glob> <after-run-glob> [--gate=25]");
        process.exit(2);
    }
    return { before: positional[0], after: positional[1], gate };
}

function main() {
    const { before: beforePattern, after: afterPattern, gate } = parseArgs(process.argv.slice(2));
    const before = readRun(beforePattern);
    const after = readRun(afterPattern);

    const beforeKeys = new Set(before.records.keys());
    const afterKeys = new Set(after.records.keys());
    const onlyBefore = [...beforeKeys].filter(k => !afterKeys.has(k));
    const onlyAfter = [...afterKeys].filter(k => !beforeKeys.has(k));

    if (onlyBefore.length > 0 || onlyAfter.length > 0) {
        console.error(`cannot pair up ${onlyBefore.length + onlyAfter.length} record(s):`);
        for (const k of onlyBefore) console.error(`  only in before: ${k}`);
        for (const k of onlyAfter) console.error(`  only in after: ${k}`);
        process.exit(2);
    }

    const rows = [];
    let anyGateFail = false;
    for (const key of [...beforeKeys].sort()) {
        const b = before.records.get(key);
        const a = after.records.get(key);
        const p50 = pctDelta(b.p50Ms, a.p50Ms);
        const p95 = pctDelta(b.p95Ms, a.p95Ms);
        const p99 = pctDelta(b.p99Ms, a.p99Ms);
        const improvement = -p95;
        const gatePass = improvement >= gate;
        if (!gatePass) anyGateFail = true;
        rows.push({ key, b, a, p50, p95, p99, gatePass });
    }

    const header = `${"key".padEnd(48)} ${"p50Δ%".padStart(9)} ${"p95Δ%".padStart(9)} ${"p99Δ%".padStart(9)}  gate(>=${gate}% p95 improvement)`;
    console.log(header);
    console.log("-".repeat(header.length));
    for (const r of rows) {
        const fmt = n => (Number.isFinite(n) ? n.toFixed(1).padStart(8) + "%" : "  n/a  ");
        console.log(`${r.key.padEnd(48)} ${fmt(r.p50)} ${fmt(r.p95)} ${fmt(r.p99)}  ${r.gatePass ? "PASS" : "fail"}`);
    }

    console.log(`\n${rows.length} record(s) compared, ${before.files.length} before file(s), ${after.files.length} after file(s)`);
    console.log(anyGateFail ? `FAIL: not every case meets the >=${gate}% p95-improvement gate` : `PASS: every case meets the >=${gate}% p95-improvement gate`);

    process.exit(anyGateFail ? 1 : 0);
}

main();
