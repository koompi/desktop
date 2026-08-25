# J18 — Quickshell services bugs

Findings from `.work/BUG-AUDIT.md` (opencode audit 2026-08-25; the lead verified H1 true and C1 false). Read each finding's full text there before starting.

## Findings you own
- H7 memory daemon gets an empty embedding key (`?.key` on a string)
- M6 timer laps / tray pins never persist (in-place list mutation)
- M7 notification timeout timer on a dismissed popup
- M8 launcher runs prefixed sudo commands without a terminal
- M13 xkb layout+variant concatenated without separator
- M14 wallpaper browser applies invalid directories
- M16 clipboard delete drops rapid second deletions
- L2 Emojis references properties that do not exist
- L3 Privacy binds arrays to bools
- L4 `value == NaN`
- L5 update count overwritten by NaN
- L7 `Mpris.players[0]` vs `.values[0]`
- L11 (services part) `0.02 || 0.2`, `!x ?? true`, missing clamp in Audio.qml / PolkitService.qml
- L12 (services part) EasyEffects optimistic toggle
- L13 LaTeX renderer: exit code ignored, user text spliced into QML source

## Files you own
- under `dots/.config/quickshell/koompi/services/`: `MemoryService.qml`, `TimerService.qml`, `TrayService.qml`, `Notifications.qml`, `LauncherSearch.qml`, `HyprlandXkb.qml`, `Wallpapers.qml`, `Cliphist.qml`, `Emojis.qml`, `Privacy.qml`, `Ai.qml`, `Updates.qml`, `MprisController.qml`, `Audio.qml`, `PolkitService.qml`, `EasyEffects.qml`, `LatexRenderer.qml`
- new tests

## Rules for every finding
1. Re-verify it in the tree before touching anything (read the code, reproduce where a command can). If a row is wrong, say so in the report with the evidence and skip it; do not "fix" a non-bug.
2. Fix the root cause, smallest diff, in the style of the surrounding code. No drive-by refactors.
3. One atomic commit per finding (or per tightly-coupled pair), subject `fix(<area>): <what>`, body: why it was wrong and how it failed.
4. Leave one runnable check per non-trivial fix: a `tests/test_*.sh` in the existing style for scripts/PKGBUILDs/workflows; for QML, `qmllint` clean on the touched file plus the smallest `qs -p` or `bash -c` reproduction you can paste.
5. Report: `.work/<JOB>-report.md` with one section per finding: verdict (confirmed / not a bug), what changed, the check and its pasted output. End with `./tests/run.sh` tail.

## Stop conditions
- Never `pkill`/`killall` by name; kill only pids you started. Never touch `~/.config/koompi/config.json`; test against copies.
- No `sudo`, no package installs; name what you need and stop.
- A fix that needs a file you do not own: stop, report which finding and which file.
