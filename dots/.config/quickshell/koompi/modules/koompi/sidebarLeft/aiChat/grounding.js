.pragma library

// Grounding is measured, never asserted. Every term below is computed from the
// source list a turn actually carried - how many, how well they matched, how
// fresh they are, and how much of the reply can be traced back to one. A model
// logit never enters it: a 4B local model cannot calibrate itself.

const STOPWORDS = new Set([
    "the", "and", "for", "are", "was", "were", "with", "that", "this", "from",
    "have", "has", "had", "not", "but", "you", "your", "our", "its", "it's",
    "they", "them", "their", "there", "here", "what", "when", "where", "which",
    "who", "whom", "how", "why", "can", "could", "would", "should", "will",
    "shall", "may", "might", "must", "into", "onto", "over", "under", "than",
    "then", "also", "just", "only", "some", "any", "all", "each", "both",
    "about", "after", "before", "because", "been", "being", "does", "did",
    "done", "get", "got", "make", "made", "one", "two", "use", "used", "using",
    "very", "more", "most", "less", "such", "same", "other", "these", "those",
    "his", "her", "she", "him", "out", "off", "per", "via", "yes", "now"
]);

function tokens(value) {
    return String(value ?? "").toLowerCase().match(/[a-z0-9][a-z0-9._\/+-]*/g) ?? [];
}

function contentTokens(value) {
    return tokens(value).filter(t => !STOPWORDS.has(t) && (t.length > 2 || /^[0-9]/.test(t)));
}

// A token that carries a fact rather than a word: a number, a version, a path.
// One of these shared between reply and source is worth a whole phrase.
function isFactToken(t) {
    return (/^[0-9][0-9.,:%-]*$/.test(t) && t.length >= 2) || t.indexOf("/") >= 0 || /[0-9]/.test(t) && t.length >= 4;
}

function sourceIndex(source) {
    const set = new Set();
    for (const t of contentTokens((source?.name ?? "") + " " + (source?.detail ?? "") + " " + (source?.url ?? ""))) {
        set.add(t);
    }
    return set;
}

// Sentences with their offsets in the original line, so the caller can splice
// markup back in without re-joining and losing whitespace.
function splitSentences(line) {
    const out = [];
    let start = 0;
    for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch !== "." && ch !== "!" && ch !== "?" && ch !== "\n") continue;
        let j = i + 1;
        while (j < line.length && (line[j] === " " || line[j] === "\t" || line[j] === "\n" || line[j] === ")" || line[j] === "\"")) j++;
        if (j === i + 1 && j < line.length) continue;
        out.push({ start: start, end: j, text: line.slice(start, j) });
        start = j;
        i = j - 1;
    }
    if (start < line.length) out.push({ start: start, end: line.length, text: line.slice(start) });
    return out;
}

// Which source backs this sentence, or -1 for none. Overlap is literal: shared
// fact tokens, or a run of shared content words. Nothing is inferred about
// meaning, so a sentence the model made up cannot accidentally test positive.
function matchSource(sentence, indices) {
    const st = contentTokens(sentence);
    if (st.length === 0) return -1;
    let best = -1;
    let bestHits = 0;
    for (let i = 0; i < indices.length; i++) {
        const set = indices[i];
        let hits = 0;
        let run = 0;
        let bestRun = 0;
        let factHit = false;
        for (const t of st) {
            if (set.has(t)) {
                hits++;
                run++;
                if (run > bestRun) bestRun = run;
                if (isFactToken(t)) factHit = true;
            } else {
                run = 0;
            }
        }
        const strong = factHit || bestRun >= 3 || (hits >= 2 && hits / st.length >= 0.34);
        if (strong && hits > bestHits) {
            bestHits = hits;
            best = i;
        }
    }
    return best;
}

// [{start, end, text, kind, source}] over one line of reply text.
function typeSpans(text, sources) {
    const list = Array.isArray(sources) ? sources : [];
    if (list.length === 0) return [];
    const indices = list.map(sourceIndex);
    return splitSentences(String(text ?? "")).map(s => {
        const idx = contentTokens(s.text).length === 0 ? -1 : matchSource(s.text, indices);
        return {
            start: s.start,
            end: s.end,
            text: s.text,
            kind: idx >= 0 ? "recorded" : "inferred",
            source: idx
        };
    });
}

function skipLine(line) {
    const t = line.trim();
    if (t.length < 12) return true;
    if (t.startsWith("#") || t.startsWith("|") || t.startsWith(">") || t.startsWith("```")) return true;
    // Nested anchors are invalid rich text, so a line that already links stays as it is.
    return line.indexOf("](") >= 0 || line.indexOf("<a ") >= 0;
}

// Wrap each typed span in markup MarkdownText actually honours. Solid underline
// in the theme accent for a span traced to a source, and it is an anchor so it
// can be clicked back to that source; one step down in emphasis, no underline,
// for a span the model produced unaided.
function annotateLine(line, sources, colRecorded, colInferred) {
    const list = Array.isArray(sources) ? sources : [];
    if (list.length === 0 || skipLine(line)) return line;
    const spans = typeSpans(line, list);
    if (spans.length === 0) return line;
    if (!spans.some(s => s.kind === "recorded")) return line;

    let out = "";
    let cursor = 0;
    for (const span of spans) {
        out += line.slice(cursor, span.start);
        const trailing = span.text.match(/\s*$/)[0];
        const body = span.text.slice(0, span.text.length - trailing.length);
        if (body.length === 0) {
            out += span.text;
        } else if (span.kind === "recorded") {
            out += `<a href="koompi-source:${span.source}"><span style="color:${colRecorded}; text-decoration: underline;">${body}</span></a>${trailing}`;
        } else {
            out += `<span style="color:${colInferred};">${body}</span>${trailing}`;
        }
        cursor = span.end;
    }
    out += line.slice(cursor);
    return out;
}

// Sources found, retrieval match, freshness, and how much of the reply they
// cover. A term with no data is dropped and the rest are renormalised rather
// than filled with a default, so the number never rests on something invented.
function computeGrounding(sources, text) {
    const list = Array.isArray(sources) ? sources : [];
    if (list.length === 0) return null;

    const terms = [];
    terms.push({ name: "sources found", value: 1 - 1 / (1 + list.length), weight: 0.20 });

    const scored = list.map(s => Number(s?.score)).filter(v => isFinite(v) && v >= 0).sort((a, b) => b - a);
    if (scored.length > 0) {
        const top = scored.slice(0, 2);
        const mean = top.reduce((a, b) => a + b, 0) / top.length;
        terms.push({ name: "retrieval match", value: Math.max(0, Math.min(1, mean)), weight: 0.35 });
    }

    const fetched = list.filter(s => s?.type !== "memory").length;
    terms.push({ name: "fetched this turn", value: fetched / list.length, weight: 0.15 });

    const spans = typeSpans(text, list);
    if (spans.length > 0) {
        const recorded = spans.filter(s => s.kind === "recorded").length;
        terms.push({ name: "reply covered", value: recorded / spans.length, weight: 0.30 });
    }

    const weight = terms.reduce((a, t) => a + t.weight, 0);
    const value = terms.reduce((a, t) => a + t.value * t.weight, 0) / weight;
    return {
        value: value,
        band: value < 0.35 ? "guessing" : value < 0.7 ? "partial" : "grounded",
        terms: terms,
        basis: terms.map(t => `${t.name} ${Math.round(t.value * 100)}%`).join(" · ")
    };
}
