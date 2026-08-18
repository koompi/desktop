pragma Singleton

import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

// SearchBench.qml — J02: a live-`qs` keystroke/process bench for the three
// real search functions (Cliphist.fuzzyQuery, AppSearch.fuzzyQuery,
// FileSearch.fuzzyRecents), driven over `qs ipc`. See tests/measure_qs_search.sh
// for the matching PSS/CPU snapshot half of this bench, and
// tests/test_search_bench_parity.sh for the automated check that this stays
// in sync with tests/bench/search/'s pure-JS reimplementations (D6 in
// .work/AUDIT.md).
//
// Off by default: nothing below is reachable (no IpcHandler is registered,
// nothing is logged) unless KOOMPI_SEARCH_BENCH=1 is in the environment `qs`
// itself was launched in. This repo starts the real shell with (see
// sdata/lib/common.sh):
//
//   setsid env QT_QPA_PLATFORM=wayland qs -c koompi >/dev/null 2>&1 &
//
// so a manual debug run looks the same, plus the env var, run from the repo
// root (Quickshell.workingDirectory — wherever `qs` is actually launched
// from — is where keystroke.ndjson below lands, so launch from the repo
// root to get it under .work/):
//
//   cd /path/to/koompi-desktop
//   KOOMPI_SEARCH_BENCH=1 setsid env QT_QPA_PLATFORM=wayland qs -c koompi &
//
// Once running:
//
//   qs ipc call searchBench setDataset tests/bench/search/fixtures/small.json
//   qs ipc call searchBench runQuery clipboard foo
//
// #### Fixture format (setDataset)
// A JSON object `{"service": "clipboard"|"apps"|"files", "entries": [...]}`.
// For "clipboard"/"files", `entries` directly replaces Cliphist.entries /
// FileSearch.recents — both are plain writable properties on those
// singletons already holding live data in exactly this shape, so this is a
// real substitution of the live dataset for the rest of the running shell
// session, not a copy. "apps" is the one exception — see appEntries below.
//
// #### Privacy
// service === "clipboard" is the one search surface with a "never logged"
// bar (matches how Cliphist.qml itself treats clipboard content). runQuery
// never writes clipboard query text or result content anywhere, including
// to keystroke.ndjson: only the query's length and the result count.
Singleton {
    id: root

    readonly property bool enabled: Quickshell.env("KOOMPI_SEARCH_BENCH") === "1"

    // Referenced once from shell.qml purely to force this singleton to
    // instantiate (QML singletons are created lazily, on first access, and
    // nothing else in the shell ever touches SearchBench) — see Do #3 in
    // .work/jobs/J02-live-qs-harness.md. A no-op beyond that.
    function load(): void {}

    // AppSearch.list (services/AppSearch.qml:44) is a readonly property
    // computed from the live Quickshell.DesktopEntries singleton, so unlike
    // Cliphist.entries/FileSearch.recents it can't be substituted from the
    // outside without editing AppSearch.qml, which this job doesn't touch.
    // When set (via setDataset), runQuery mirrors AppSearch.fuzzyQuery's
    // default (non-sloppy) Fuzzy.go path against it instead of calling the
    // real function — the same "short parallel reimplementation, comment-
    // cited to the exact lines it mirrors" approach tests/bench/search/
    // uses for its own pure-JS mirrors (see .work/AUDIT.md, D2). null means
    // "no override": runQuery calls the real AppSearch.fuzzyQuery against
    // whatever is actually installed on this machine.
    property var appEntries: null

    FileView {
        id: datasetFile
        printErrors: true
    }

    function setDataset(fixturePath: string): void {
        if (!root.enabled)
            return;
        datasetFile.path = fixturePath;
        datasetFile.waitForJob(); // blocking on purpose: see FileView docs on waitForJob/blockLoading — this call must
                                   // return only once the fixture is actually in place, or a runQuery IPC call made
                                   // right after from a separate `qs ipc call` process could race the load.
        let fixture;
        try {
            fixture = JSON.parse(datasetFile.text());
        } catch (e) {
            console.error(`[SearchBench] couldn't parse fixture at ${fixturePath}: ${e}`);
            return;
        }
        const entries = fixture.entries ?? [];
        switch (fixture.service) {
        case "clipboard":
            Cliphist.entries = entries;
            break;
        case "files":
            FileSearch.recents = entries;
            break;
        case "apps":
            root.appEntries = entries;
            break;
        default:
            console.error(`[SearchBench] fixture at ${fixturePath} has an unknown "service": ${fixture.service}`);
        }
    }

    // Mirrors AppSearch.qml:61-78's default (non-sloppy) Fuzzy.go path —
    // see appEntries above for why this exists instead of calling the real
    // function.
    function appFuzzyQuery(search, entries) {
        const prepped = entries.map(a => ({
            name: Fuzzy.prepare(`${a.name} `),
            entry: a
        }));
        return Fuzzy.go(search, prepped, {
            all: true,
            key: "name"
        }).map(r => r.obj.entry);
    }

    function runQuery(service: string, text: string): void {
        if (!root.enabled)
            return;
        const t0 = Date.now();
        let results;
        switch (service) {
        case "clipboard":
            results = Cliphist.fuzzyQuery(text);
            break;
        case "apps":
            results = root.appEntries !== null ? root.appFuzzyQuery(text, root.appEntries) : AppSearch.fuzzyQuery(text);
            break;
        case "files":
            results = FileSearch.fuzzyRecents(text);
            break;
        default:
            console.error(`[SearchBench] runQuery: unknown service "${service}"`);
            return;
        }
        const tMs = Date.now() - t0;
        const resultCount = results ? results.length : 0;
        // Never the raw query text for clipboard — its length only.
        const loggedQuery = service === "clipboard" ? text.length : text;
        root.record(service, loggedQuery, resultCount, tMs);
    }

    // Appends one line to keystroke.ndjson. Uses the same
    // StringUtils.shellSingleQuoteEscape + `bash -c` append pattern
    // Cliphist.qml already uses for shell-safe writes of arbitrary text
    // (services/Cliphist.qml:56) rather than inventing a new one; mkdir -p
    // creates .work/bench/search/ on first use.
    function record(service, loggedQuery, resultCount, tMs) {
        const line = JSON.stringify({
            query: loggedQuery,
            service: service,
            resultCount: resultCount,
            tMs: tMs,
            ts: new Date().toISOString()
        });
        const dir = `${Quickshell.workingDirectory}/.work/bench/search`;
        const path = `${dir}/keystroke.ndjson`;
        const escDir = StringUtils.shellSingleQuoteEscape(dir);
        const escPath = StringUtils.shellSingleQuoteEscape(path);
        const escLine = StringUtils.shellSingleQuoteEscape(line);
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${escDir}' && printf '%s\\n' '${escLine}' >> '${escPath}'`]);
    }

    IpcHandler {
        target: "searchBench"
        enabled: root.enabled

        function runQuery(service: string, text: string): void {
            root.runQuery(service, text);
        }

        function setDataset(fixturePath: string): void {
            root.setDataset(fixturePath);
        }
    }
}
