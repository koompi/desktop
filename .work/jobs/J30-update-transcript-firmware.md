# J30 — `koompi update`: a transcript on disk, a diagnosis, and firmware advice (O28 O31)

`.work/OMARCHY-AUDIT.md` rows O28 and O31. Omarchy at `~/.tmp/omarchy`: `bin/omarchy-update:10-13`,
`bin/omarchy-update-analyze-logs:5-10`, `bin/omarchy-update-firmware:6-13`. Read first:
`dots/.local/share/koompi/libexec/update` (695 lines, at its `tests/file-length-allow.txt` row — it may not grow by one line),
`dots/.local/share/koompi/libexec/update-lib.sh` (110, where new helpers go), `dots/.local/bin/koompi-health`,
`tests/test_update_guards.sh` (J24's shim pattern), and `docs/agents/` for the doc voice.

## Files you own
- `dots/.local/share/koompi/libexec/update` (must stay ≤ 695 lines; move code out, do not add)
- `dots/.local/share/koompi/libexec/update-lib.sh` (bash cap 400)
- `dots/.local/bin/koompi-health`
- new `tests/test_update_transcript.sh`; `.work/J30-report.md`

## Do
1. (O28) Every non-dry-run `koompi update` keeps a transcript: re-exec itself under `script -qefc` into
   `${XDG_STATE_HOME:-$HOME/.local/state}/koompi/logs/update-<YYYYmmdd-HHMMSS>.log` (the directory `koompi-health` already
   logs to), guarded by an env var so the inner run does not recurse; keep the newest 10. `--dry-run` writes none. Print
   the path on the last line, pass or fail.
2. (O28) `koompi doctor --last-update` (in `koompi-health`): prints the newest transcript's path, its exit line, and a
   short diagnosis from a fixed pattern table (pacman conflicts, 404/keyring, "no space", "another koompi update is
   running", git merge conflict) — one line per matched pattern, "no known failure pattern" otherwise. No upload
   (omarchy uploads to a paste service; we do not send logs anywhere — say so in the help text).
3. (O31) After a successful packaged upgrade, when `fwupdmgr` exists: `fwupdmgr get-updates` (read-only; refresh first
   with `--offline`-safe flags you verify in `fwupdmgr --help`), and if it lists any, print an advice line naming
   `koompi update --firmware`. `koompi update --firmware` runs `fwupdmgr update` interactively and nothing else; without
   `fwupdmgr` it says which package provides it (J33 adds the dependency; do not touch PKGBUILDs).
4. `tests/test_update_transcript.sh`: shims `script`, `fwupdmgr`, `pacman` and friends like `test_update_guards.sh`;
   proves the transcript path is created and pruned to 10, dry-run writes none, the diagnosis table matches each pattern
   from a fixture log, `--firmware` calls `fwupdmgr update` and only that, and advice appears only when updates are listed.

## Acceptance
1. Paste the new test's output and the `./tests/run.sh` tail (baseline 81/3/0, +1).
2. Paste `koompi update --dry-run` on this machine (no transcript expected: show the log dir unchanged) and
   `koompi doctor --last-update` against a fixture transcript copied into a throwaway `XDG_STATE_HOME`.
3. `shellcheck -x` on the three scripts: empty. `wc -l`: `update` ≤ 695, others under cap.
4. `koompi update --help` shows `--firmware`; `koompi doctor --help` (or the usage line) shows `--last-update`.

## Out of scope
- `koompi-migrate`, `koompi-snapshot`, `koompi-reload`, `sdata/install/update.sh`, `cli/src/main.zig` (report the usage
  line to update), `sdata/dist-arch/**`.

## Stop conditions
- No real `pacman -Syu`, no `fwupdmgr update`, no reboot on this machine; dry-run and shims only.
- If `script(1)` (util-linux) is not guaranteed on a KOOMPI install, say which package owns it and continue (it is
  util-linux on Arch; verify with `pacman -Qo`).
