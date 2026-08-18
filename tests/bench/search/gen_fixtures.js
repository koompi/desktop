"use strict";

const fs = require("fs");
const path = require("path");

const FIXTURES_DIR = path.join(__dirname, "fixtures");

// current-scale: clipboard 750 (`cliphist -max-items` default, this box), apps 163
// (`ls /usr/share/applications/*.desktop | wc -l`, this box), files 289 (`grep -c
// "<bookmark " ~/.local/share/recently-used.xbel`, this box). stress = 10x each.
const SIZES = {
    clipboard: { empty: 0, small: 20, "current-scale": 750, stress: 7500 },
    apps: { empty: 0, small: 20, "current-scale": 163, stress: 1630 },
    files: { empty: 0, small: 20, "current-scale": 289, stress: 2890 },
};

const CLIP_WORDS = [
    "please", "review", "the", "attached", "document", "before", "tomorrow", "meeting",
    "server", "restarted", "successfully", "last", "night", "remember", "update",
    "dependency", "version", "staging", "environment", "customer", "requested", "refund",
    "order", "number", "shipping", "address", "confirmed", "password", "reset", "link",
    "expires", "hours", "dashboard", "metrics", "looking", "stable", "today", "let",
    "know", "if", "questions", "arise", "team", "sync", "postponed", "friday", "draft",
    "proposal", "feedback", "budget", "release", "notes", "ticket", "assigned", "review",
];

const APP_WORDS = [
    "Text", "Code", "Photo", "Video", "Music", "Terminal", "File", "Web", "Mail",
    "Calendar", "Note", "Task", "Paint", "Draw", "Chat", "Voice", "Camera", "Disk",
    "Archive", "System", "Network", "Settings", "Player", "Studio", "Manager", "Viewer",
    "Editor", "Browser", "Reader", "Writer", "Pro", "Lite", "Suite", "Hub",
];

const FILE_STEMS = [
    "report", "invoice", "summary", "draft", "notes", "photo", "screenshot", "backup",
    "archive", "presentation", "budget", "timeline", "proposal", "resume", "contract",
    "itinerary", "checklist", "diagram", "export", "log",
];
const FILE_EXTS = ["pdf", "docx", "xlsx", "png", "jpg", "txt", "md", "csv", "pptx", "zip"];

// Real Khmer script, hand-written for this fixture set (no existing asset to reuse).
const KHMER_WORDS = [
    "ខ្មែរ", "សួស្តី", "អរគុណ", "ទឹក", "ភ្នំពេញ", "បាយ", "ស្រលាញ់", "ជំរាបសួរ",
    "លុយ", "ផ្ទះ", "សៀវភៅ", "កុំព្យូទ័រ", "សាលារៀន", "មិត្តភាព", "ព្រះអាទិត្យ",
    "ព្រះច័ន្ទ", "ភ្លៀង", "ខ្យល់", "ភោជនីយដ្ឋាន", "ឯកសារ",
];
const KHMER_QUERY_WORD = KHMER_WORDS[2]; // "អរគុណ"

const UNICODE_SNIPPETS = [
    "café", "naïve façade", "Zürich", "日本語", "中文文档", "東京タワー", "📎 attachment",
    "🗂️ archive", "✅ done", "🚀 launch",
];
const UNICODE_QUERY_WORD = UNICODE_SNIPPETS[0]; // "café"

function seedFromString(s) {
    let h = 1779033703 ^ s.length;
    for (let i = 0; i < s.length; i++) {
        h = Math.imul(h ^ s.charCodeAt(i), 3432918353);
        h = (h << 13) | (h >>> 19);
    }
    return (h ^ (h >>> 16)) >>> 0;
}

function mulberry32(seed) {
    let a = seed;
    return function () {
        a |= 0;
        a = (a + 0x6d2b79f5) | 0;
        let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function pick(rand, arr) {
    return arr[Math.floor(rand() * arr.length)];
}

function pickN(rand, arr, n) {
    const out = [];
    for (let i = 0; i < n; i++) out.push(pick(rand, arr));
    return out;
}

function capitalize(s) {
    return s.length === 0 ? s : s[0].toUpperCase() + s.slice(1);
}

function transpose(word) {
    if (word.length < 4) return word.split("").reverse().join("");
    const chars = word.split("");
    [chars[2], chars[3]] = [chars[3], chars[2]];
    return chars.join("");
}

function specialSlots(n) {
    if (n === 0) return { find: -1, khmer: -1, unicode: -1 };
    return {
        find: Math.floor(n * 0.2),
        khmer: Math.min(n - 1, Math.floor(n * 0.4) + 1),
        unicode: Math.min(n - 1, Math.floor(n * 0.6) + 2),
    };
}

function buildClipboardEntries(rand, n) {
    const slots = specialSlots(n);
    const entries = [];
    for (let i = 0; i < n; i++) {
        const words = pickN(rand, CLIP_WORDS, 3 + Math.floor(rand() * 6));
        if (i === slots.find) words.splice(Math.floor(words.length / 2), 0, "invoice");
        if (i === slots.khmer) words.push(pick(rand, KHMER_WORDS));
        if (i === slots.unicode) words.push(pick(rand, UNICODE_SNIPPETS));
        if (i % 11 === 0 && i !== slots.khmer) words.push(pick(rand, KHMER_WORDS));
        if (i % 13 === 0 && i !== slots.unicode) words.push(pick(rand, UNICODE_SNIPPETS));
        const text = capitalize(words.join(" ")) + ".";
        entries.push(`${1000 + i}\t${text}`);
    }
    return entries;
}

function buildAppEntries(rand, n) {
    const slots = specialSlots(n);
    const entries = [];
    for (let i = 0; i < n; i++) {
        let name;
        if (i === slots.find) name = "Text Editor";
        else if (i === slots.khmer) name = pick(rand, KHMER_WORDS);
        else if (i === slots.unicode) name = pick(rand, UNICODE_SNIPPETS);
        else if (i % 11 === 0) name = pick(rand, KHMER_WORDS);
        else if (i % 13 === 0) name = pick(rand, UNICODE_SNIPPETS);
        else name = pickN(rand, APP_WORDS, 1 + Math.floor(rand() * 2)).join(" ");
        entries.push({ name, icon: name.toLowerCase().replace(/\s+/g, "-"), id: `app-${i}.desktop` });
    }
    return entries;
}

function buildFileEntries(rand, n) {
    const slots = specialSlots(n);
    const entries = [];
    for (let i = 0; i < n; i++) {
        let name;
        if (i === slots.find) name = `quarterly-report.${pick(rand, FILE_EXTS)}`;
        else if (i === slots.khmer) name = `${pick(rand, KHMER_WORDS)}.${pick(rand, FILE_EXTS)}`;
        else if (i === slots.unicode) name = `${pick(rand, UNICODE_SNIPPETS).replace(/\s+/g, "-")}.${pick(rand, FILE_EXTS)}`;
        else if (i % 11 === 0) name = `${pick(rand, KHMER_WORDS)}.${pick(rand, FILE_EXTS)}`;
        else if (i % 13 === 0) name = `${pick(rand, UNICODE_SNIPPETS).replace(/\s+/g, "-")}.${pick(rand, FILE_EXTS)}`;
        else name = `${pick(rand, FILE_STEMS)}-${Math.floor(rand() * 9999)}.${pick(rand, FILE_EXTS)}`;
        const dir = pick(rand, ["Documents", "Downloads", "Desktop", "Pictures", "Projects"]);
        const path_ = `/home/bench/${dir}/${name}`;
        const day = 1 + Math.floor(rand() * 27);
        const month = 1 + Math.floor(rand() * 12);
        entries.push({
            path: path_,
            name,
            modified: `2026-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}T00:00:00Z`,
        });
    }
    return entries;
}

function longQuery() {
    const filler = "search";
    return filler.repeat(Math.ceil(10000 / filler.length)).slice(0, 10000);
}

function buildQueries(domain, findToken) {
    return [
        { case: "no-match", query: `zzznomatch-${domain}-xyz999` },
        { case: "exact-hit", query: findToken },
        { case: "prefix", query: findToken.slice(0, Math.max(2, Math.floor(findToken.length / 2))) },
        { case: "typo", query: transpose(findToken) },
        { case: "khmer", query: KHMER_QUERY_WORD },
        { case: "unicode-mixed", query: UNICODE_QUERY_WORD },
        { case: "empty", query: "" },
        { case: "whitespace-only", query: "   " },
        { case: "very-long-10k", query: longQuery() },
        { case: "control-chars", query: "before\u0000\u0007\u001bafter" },
        { case: "lone-surrogate", query: "prefix\ud800suffix" },
    ];
}

const DOMAIN_CONFIG = {
    clipboard: { build: buildClipboardEntries, findToken: "invoice" },
    apps: { build: buildAppEntries, findToken: "editor" },
    files: { build: buildFileEntries, findToken: "report" },
};

function main() {
    fs.mkdirSync(FIXTURES_DIR, { recursive: true });
    const written = [];
    for (const [domain, cfg] of Object.entries(DOMAIN_CONFIG)) {
        for (const [size, n] of Object.entries(SIZES[domain])) {
            const seed = seedFromString(`${domain}:${size}:koompi-search-bench`);
            const rand = mulberry32(seed);
            const entries = cfg.build(rand, n);
            const queries = buildQueries(domain, cfg.findToken);
            const fixture = { domain, size, entryCount: n, seed, entries, queries };
            const file = path.join(FIXTURES_DIR, `${domain}-${size}.json`);
            fs.writeFileSync(file, JSON.stringify(fixture, null, 2) + "\n");
            written.push(file);
        }
    }
    for (const file of written) {
        const { size: bytes } = fs.statSync(file);
        console.log(`${path.relative(process.cwd(), file)}\t${bytes} bytes`);
    }
}

main();
