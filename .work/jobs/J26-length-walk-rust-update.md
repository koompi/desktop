# J26 — extend the file-length walk: Rust and `libexec/update`

From J01 (`.work/J01-report.md`, "Decisions taken"): the ratchet walks `*.qml *.js *.lua *.sh *.zig`, `setup`,
`install.sh` and `dots/.local/bin/*`. Out of the walk but over 400 lines and clearly code:
`dots/.local/share/koompi/libexec/update` (bash, no extension, ~700 lines) and the Rust services
(`shell-services/network/src/service.rs` 1198, `mpris/src/service.rs` 898, `tray/src/watcher.rs` 683, plus
whatever else `git ls-files '*.rs'` finds over cap). Lead's decision: Rust cap 600/80 (same as Zig, same reason:
long declarations per unit of behaviour).

## Files you own
- `tests/test_file_length.sh`
- `tests/file-length-allow.txt` (add rows only; other live jobs remove rows for the files they split — rebase and keep both)
- `docs/conventions.md` (the caps table: one Rust row, one note that `dots/.local/share/koompi/libexec/*` counts as bash)
- `.work/J26-report.md`

## Do
1. `cap_for`: `*.rs` → 600; `dots/.local/share/koompi/libexec/*` → 400 (bash). Keep the skip list; add
   `target/` (cargo output) to it if any `.rs` under a `target/` dir is tracked (check `git ls-files`).
2. Regenerate the allow-list rows for the newly walked kinds with the same counting rule (`awk 'END{print NR}'`),
   `LC_ALL=C` sorted into the existing file. Paste every new row.
3. `docs/conventions.md`: the Rust row in the table and the libexec note, one sentence each.
4. `bash tests/test_file_length.sh` ok; `./tests/run.sh` tail; `shellcheck tests/test_file_length.sh` clean.

## Acceptance
1. The new allow-list rows (expect the three Rust files above at least, plus `libexec/update`).
2. `FILE_LENGTH_ROOT`/`FILE_LENGTH_FILES` demonstration: a 601-line `x.rs` fails, a 600-line one passes; a
   401-line `dots/.local/share/koompi/libexec/y` fails.
3. `./tests/run.sh` tail, unchanged count.

## Out of scope
- Shrinking anything. Function caps.

## Stop conditions
- If a tracked `.rs` file is vendored (a crate copied in), list it and stop rather than allow-listing it silently.
