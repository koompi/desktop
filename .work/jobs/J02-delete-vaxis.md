# J02 — delete the dead vendored vaxis

## Files you own
- `installer/zig-pkg/**` (delete)
- `installer/build.zig.zon` (comment at line 3 only, if it references the directory)

## Do
1. (D1) Confirm nothing references `zig-pkg` or `vaxis`: `grep -rn 'zig-pkg\|vaxis' installer/ --include='*.zig' --include='*.zon' --include='build.zig'` and `.github/workflows/`. Paste the output.
2. (D1) `git rm -r installer/zig-pkg`.
3. (D1) If `build.zig.zon:3` still explains vaxis history, shorten it to one line saying there are no dependencies.
4. `cd installer && zig build && zig build test`; paste both exits.

## Acceptance
1. Step 1 grep output showing only comments (no imports, no paths).
2. `git status --short` showing only deletions under `installer/zig-pkg/` and the optional `.zon` edit.
3. `zig build` exit 0 and `zig build test` output (expect 4 tests passing).
4. `./tests/run.sh` tail unchanged from baseline (56 or 57 depending on whether J01 has landed on your base).

## Out of scope
- Any change under `installer/src/`. That is J06.
- Any other vendored directory.

## Stop conditions
- If step 1 shows a real `@import` of vaxis anywhere, stop and report; do not delete.
