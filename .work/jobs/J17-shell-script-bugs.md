# J17 — shell script and Lua config bugs

Findings from `.work/BUG-AUDIT.md` (opencode audit 2026-08-25; the lead verified H1 true and C1 false). Read each finding's full text there before starting.

## Findings you own
- M1 switchwall writes literal `"null"` into config.json
- M2 venv path sourced while possibly unset
- M3 wallpaper categorization writes into a directory nothing creates
- H9 failed app recipe still reports "applications installed"
- M20 zig builds use the subshell-abort anti-pattern (`setups.sh:30-34,82`)
- L20 `mktemp -u` race (`setups.sh:367`)
- M22 koompi-displays needs lua/luac, declared nowhere
- L18 predictable /tmp names, no cleanup trap in koompi-stacking
- L19 fixed `.tmp` sibling races concurrent config writers in koompi-wallpaper (use `mktemp` in the same dir + `mv`; validate with `jq -e "type == \"object\""` before the move)
- L24 hyprlock status reads every power supply
- L25 hardcoded touchdevice output eDP-1

## Files you own
- `dots/.config/quickshell/koompi/scripts/colors/switchwall.sh`
- `sdata/install/apps.sh`, `sdata/dist-arch/install-apps.sh`, `sdata/install/setups.sh` (M20, L20 lines only; J14 just added `setup_low_ram_defaults`, leave it)
- `dots/.local/bin/koompi-displays`, `koompi-stacking`, `koompi-wallpaper`
- `dots/.config/hypr/hyprlock/status.sh`, `dots/.config/hypr/hyprland/general.lua`
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
