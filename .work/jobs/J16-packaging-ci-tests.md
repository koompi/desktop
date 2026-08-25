# J16 — packaging, CI and test-harness bugs

Findings from `.work/BUG-AUDIT.md` (opencode audit 2026-08-25; the lead verified H1 true and C1 false). Read each finding's full text there before starting.

## Findings you own
- H3 packaged trees copy zig caches (exclude list; reuse `sdata/install/files.sh:277-281`)
- H4 build loops skip `ttf-koompi-star/`
- H5 root-owned PKGDEST in build-packages.yml
- H6 test prints FAIL but exits 0
- M4 `tests/run.sh` counts skips as passes and hides output (report skips as a third count; keep exit semantics)
- M5 nothing in CI runs `tests/run.sh` (add a workflow on an Arch container; it must actually run and pass, paste the local `act`-less reasoning: which tests need a display and how you skip them honestly)
- L21 microtex soname sed pins
- L22 vacuous `|| true` backup assertion in installer.yml
- L23 same-day ISO rebuild dies on existing tag

## Files you own
- `sdata/dist-arch/koompi-shell/PKGBUILD`, `sdata/dist-arch/koompi-hyprland-config/PKGBUILD`, `sdata/dist-arch/koompi-microtex-git/PKGBUILD`
- `sdata/dist-arch/repo/build-repo.sh`, `.github/workflows/build-packages.yml`, `.github/workflows/installer.yml`, `.github/workflows/build-iso.yml`, new `.github/workflows/tests.yml`
- `tests/run.sh`, `tests/test_ai_approval_scope.sh`, new tests

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
