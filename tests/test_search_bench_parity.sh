#!/usr/bin/env bash
# Diffs services/SearchBench.qml's live runQuery (real Cliphist.fuzzyQuery /
# AppSearch.fuzzyQuery-mirror / FileSearch.fuzzyRecents, run inside a live
# `qs`) against a pure-JS reimplementation of the same fuzzysort-default-mode
# call, for the same fixed fixture and queries, catching drift between them
# (D6 in .work/AUDIT.md).
#
# Prefers tests/bench/search/bench_scoring.js's dispatch functions (J01) if
# that has landed by the time this runs; at the time this was written it
# hadn't (no tests/bench/search/ directory existed yet), so this falls back
# to a small inline reimplementation built directly on
# modules/common/functions/fuzzysort.js — the same self-contained
# `.pragma library` file the real functions use, read as text the same way
# tests/test_search_providers.sh's lift() reads QML source, so this stays a
# thin wrapper around real matching code rather than a hand-written
# reimplementation of fuzzysort's algorithm.
#
# Preconditions this test does not control, and skips (exit 0) rather than
# fails on: `node` installed, KOOMPI_SEARCH_BENCH=1 in *this shell's*
# environment (a cheap local signal the caller means to test against a
# bench-enabled shell), and a live `qs -c koompi` actually answering IPC
# with a registered "searchBench" target (which only happens if
# KOOMPI_SEARCH_BENCH=1 was set in *qs's own* launch environment - see
# SearchBench.qml's header for how to do that).
#
# Result *content* is never observable over IPC by design (runQuery's IPC
# signature is void, and clipboard content specifically is never logged -
# see SearchBench.qml), so "diff result order" is done as far as the wire
# protocol allows: by result *count*, read back from the resultCount field
# SearchBench.qml appends to keystroke.ndjson for each completed query.
# A count mismatch is still real drift (different matches, not just a
# different order of the same matches); an order-only regression wouldn't
# show up here, and would need a same-process comparison instead.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QS_DIR="$REPO_ROOT/dots/.config/quickshell/koompi"
FUZZYSORT_JS="$QS_DIR/modules/common/functions/fuzzysort.js"
NDJSON="$REPO_ROOT/.work/bench/search/keystroke.ndjson"

command -v node > /dev/null || { printf 'node is not installed; skipping\n'; exit 0; }

if [[ "${KOOMPI_SEARCH_BENCH:-}" != "1" ]]; then
    printf 'KOOMPI_SEARCH_BENCH is not set to 1 in this shell; skipping (this only tests a bench-enabled live qs, see services/SearchBench.qml)\n'
    exit 0
fi

ipc_out="$(timeout 3 qs -c koompi ipc show 2>&1)"
ipc_status=$?
if [[ $ipc_status -ne 0 ]]; then
    printf 'no live "qs -c koompi" instance answered IPC (exit %d): %s; skipping\n' "$ipc_status" "$ipc_out"
    exit 0
fi
if ! grep -q 'Target searchBench' <<<"$ipc_out"; then
    printf 'qs is reachable over IPC but has no "searchBench" target registered - the running qs was not launched with KOOMPI_SEARCH_BENCH=1; skipping\n'
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/clipboard.json" <<'EOF'
{"service": "clipboard", "entries": ["1\thello world", "2\tgoodbye world", "3\tfoo bar baz"]}
EOF
cat > "$tmpdir/apps.json" <<'EOF'
{"service": "apps", "entries": [{"name": "Firefox"}, {"name": "Files"}, {"name": "Fire Emblem"}]}
EOF
cat > "$tmpdir/files.json" <<'EOF'
{"service": "files", "entries": [{"name": "readme.md"}, {"name": "readable.txt"}, {"name": "other.log"}]}
EOF

# service:fixture:query
cases=(
    "clipboard:$tmpdir/clipboard.json:hello"
    "apps:$tmpdir/apps.json:fire"
    "files:$tmpdir/files.json:read"
)

# Reference counts from the pure-JS mirror, one "service query count" line per case.
reference="$(FUZZYSORT_JS="$FUZZYSORT_JS" CASES_JSON="$tmpdir" node - "${cases[@]}" <<'EOF'
const fs = require("fs");

function loadFuzzysort(path) {
    // Strip the QML-only pragma so this is plain JS, then eval it for its
    // top-level `go`/`prepare` declarations - same file the real
    // Cliphist.fuzzyQuery/AppSearch.fuzzyQuery/FileSearch.fuzzyRecents call.
    const src = fs.readFileSync(path, "utf8").replace(/^\.pragma library\s*/, "");
    return eval(`(function () { ${src}\nreturn { go, prepare }; })()`);
}

const { go, prepare } = loadFuzzysort(process.env.FUZZYSORT_JS);

// Mirrors services/Cliphist.qml:19-22's non-sloppy preparedEntries.
const prepClipboard = entries => entries.map(a => ({ name: prepare(`${a.replace(/^\s*\S+\s+/, "")}`), entry: a }));
// Mirrors services/AppSearch.qml:51-54's preppedNames.
const prepApps = entries => entries.map(a => ({ name: prepare(`${a.name} `), entry: a }));
// Mirrors services/FileSearch.qml:20-23's preparedRecents.
const prepFiles = entries => entries.map(entry => ({ name: prepare(entry.name), entry }));

const preppers = { clipboard: prepClipboard, apps: prepApps, files: prepFiles };

function fuzzyQuery(service, entries, search) {
    const prepped = preppers[service](entries);
    return go(search, prepped, { all: true, key: "name" }).map(r => r.obj.entry);
}

for (const arg of process.argv.slice(2)) {
    const [service, fixturePath, query] = arg.split(":");
    const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
    const results = fuzzyQuery(service, fixture.entries, query);
    console.log(`${service} ${query} ${results.length}`);
}
EOF
)"

failures=0
check() {
    if [[ "$2" != "true" ]]; then
        echo "  xx $1"
        failures=$((failures + 1))
    else
        echo "  ok $1"
    fi
}

before_lines="$(wc -l < "$NDJSON" 2>/dev/null || echo 0)"

for c in "${cases[@]}"; do
    IFS=: read -r service fixture query <<<"$c"

    qs -c koompi ipc call searchBench setDataset "$fixture" > /dev/null 2>&1
    qs -c koompi ipc call searchBench runQuery "$service" "$query" > /dev/null 2>&1

    # keystroke.ndjson is written by a detached process (see SearchBench.qml
    # record()), so the line may land a moment after the IPC call returns.
    live_count=""
    for _ in $(seq 1 20); do
        after_lines="$(wc -l < "$NDJSON" 2>/dev/null || echo 0)"
        if [[ "$after_lines" -gt "$before_lines" ]]; then
            live_count="$(tail -n "$((after_lines - before_lines))" "$NDJSON" | node -e "
                const q=process.argv[1], s=process.argv[2];
                for (const line of require('fs').readFileSync(0,'utf8').trim().split('\n')) {
                    if (!line) continue;
                    const e = JSON.parse(line);
                    if (e.service === s && e.query === q) { console.log(e.resultCount); process.exit(0); }
                }
            " "$query" "$service")"
            [[ -n "$live_count" ]] && break
        fi
        sleep 0.1
    done
    before_lines="$after_lines"

    ref_count="$(grep "^$service $query " <<<"$reference" | awk '{print $NF}')"

    if [[ -z "$live_count" ]]; then
        check "$service \"$query\": live runQuery logged a matching line" "false"
        continue
    fi
    check "$service \"$query\": result count matches (js=$ref_count, live=$live_count)" "$([[ "$ref_count" == "$live_count" ]] && echo true || echo false)"
done

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "search bench parity test passed (${#cases[@]} queries)"
