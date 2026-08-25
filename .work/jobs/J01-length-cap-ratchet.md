# J01 — length cap in conventions + ratchet test

## Files you own
- `docs/conventions.md`
- `tests/test_file_length.sh` (new)
- `tests/file-length-allow.txt` (new)

## Do
1. (D3) Add a "File and function length" section to `docs/conventions.md` after "Files and directories". Caps: QML 400/60, JS and Lua 300/50, bash 400/60, Zig 600/80 (file/function). One paragraph on why (a file is read whole; a function fits a screen), one on the ratchet (allow-listed files may only shrink), and the sources cited in `.work/AUDIT.md`.
2. (D3) Write `tests/test_file_length.sh` in the style of the existing `tests/test_*.sh` (read two of them first). It walks `git ls-files` for `*.qml *.js *.lua *.sh *.zig` plus `setup`, `install.sh`, `dots/.local/bin/*`; skips `installer/zig-pkg/`, `graphify-out/`, `translations/`, `tests/`; counts lines; fails on any file over its cap unless listed in `tests/file-length-allow.txt` with a line count, and fails on any allow-listed file whose current count exceeds the listed count. Function caps are not enforced in this job (no parser); file cap only.
3. (D3) Generate `tests/file-length-allow.txt` from the current tree: one `path<TAB>lines` per file over cap, sorted. It must include every current offender, so the test is green on the day it lands.
4. Run `./tests/run.sh` and paste the tail.

## Acceptance
1. Paste the full contents of `tests/file-length-allow.txt` (expect roughly 55 rows: the 42 files in 400-800, 11 in 800-1500, 2 over 1500, minus non-code kinds).
2. Show the test failing on a synthetic over-cap file: create `/tmp/x.qml` with 401 lines, point the test at it via whatever hook you add for that, paste the failure line, then delete it.
3. Show the test failing when an allow-listed file grows: append one line to an allow-listed file in a scratch copy, paste the failure, revert.
4. `./tests/run.sh` tail showing 57 passed, 0 failed.

## Out of scope
- Shrinking any file. That is J03-J08's work.
- Function-length enforcement.
- Touching `tests/run.sh`; it already discovers new tests.

## Stop conditions
- If `git ls-files` classification leaves an ambiguous kind (a file with no extension that is not in `dots/.local/bin/`), list it and ask rather than guessing a cap.
- No deletions anywhere.
