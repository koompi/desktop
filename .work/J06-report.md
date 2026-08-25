# J06 report — split installer/src/main.zig (AUDIT D6)

Branch `j06-split-installer-zig`, based on main `422c58e4`.
Two commits, in order: `a2393ce0` build.zig for 0.16's build runner (judgeable alone), `a60f779a` the split.
Files touched: `installer/build.zig`, `installer/src/main.zig`, new `installer/src/{theme,term,app,ui}.zig`, this file.
`installer/build.zig.zon` is unchanged (see Addendum 2 below for why `minimum_zig_version` stays at 0.14.0).
J02 is on the base: `installer/zig-pkg/` does not exist, so that stop condition does not fire.

## Toolchain used for verification

This machine ships zig 0.16.0 (`pacman -Q zig` → `zig 0.16.0-1`, no other zig on disk).
0.16 cannot compile `installer/src/` at all (Addendum 2), on main or on this branch, so every build/test/capture below ran on zig 0.14.1, downloaded to `/tmp/zig014/` for this session only (sha256 verified against ziglang.org's index: `24aeeec8…4716c`).
Nothing was added to the repo for that; `/tmp/zig014` is disposable.

## Addendum 2: build.zig on 0.16, and the size of the src/ port

Commit `a2393ce0` is the whole build.zig side: `root_module = b.createModule(...)` fed to both `addExecutable` and `addTest`.
That form works on 0.14.1 (all results below) and is what 0.16's `ExecutableOptions`/`TestOptions` require.
With it, 0.16 gets past build.zig and stops in src/:

```
$ /usr/bin/zig version; /usr/bin/zig build
0.16.0
   +- compile exe koompi-installer Debug native 1 errors
src/main.zig:65:23: error: root source file struct 'heap' has no member named 'GeneralPurposeAllocator'
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
```

That is the first of many.
The stop condition (port over ~50 lines → report the size, do not do it) fires.
0.16's std is not the 0.15 Writer change alone; `std.fs` is reduced to `std.fs.path` and `std.io` is gone, replaced by `std.Io.Dir`/`std.Io.File`/`std.Io.Writer` where every file, directory, process and stdout call takes an `io: std.Io` handle (`Dir.openFile(dir, io, path, opts)`, `File.writer(file, io, buf)`, `Child.wait(child, io)`, `File.close(file, io)`), obtained from `std.Io.Threaded` in `main` and threaded down.
Inventory of call sites that change (grep for `std.fs.cwd/openFileAbsolute/openDirAbsolute/selfExeDirPathAlloc`, `readToEndAlloc`, `std.io.*`, `.writer()`, `getStdOut`, `std.posix.getenv`, `GeneralPurposeAllocator`, managed `ArrayList` init/append/toOwnedSlice, `Child.init/run/wait`, `fixedBufferStream`, `bufferedWriter`):

```
     19 src/archinstall.zig
      9 src/cidata.zig
      1 src/main.zig
      3 src/term.zig
     13 src/theme.zig
     33 src/ui.zig
     78 total
```

Plus 18 function signatures in archinstall/cidata/theme that gain an `io` parameter, plus the four cidata tests that build a `std.fs.Dir` fixture.
Estimate: 110–140 changed lines across five files, with `archinstall.zig` (the code that runs the wipe) the largest share.
Not done; it is its own job, and it is not a mechanical rename.

Because src/ builds only against the 0.14 std, `minimum_zig_version = "0.14.0"` is still the true statement and was left alone; bumping it to 0.16.0 would reject the only toolchain that builds the source.

## Do 1–3: the split

Clusters moved by line range from the original 931-line file, verbatim except for `pub` and the two `inline for` tables in `parseTheme` that `zig fmt` realigned (the original was not fmt-clean: `zig fmt --check` on main's main.zig exits 1).
Section banners became each file's `//!` header; no other comment was edited.

| file | from main.zig | pub surface |
|---|---|---|
| `theme.zig` | 23–271, tests 895–916, 927–931 | `Theme`, `Rgb`, `Profile`, `Glyphs`, `ThemeError`, `loadTheme`, `loadThemeRaw`, `parseTheme`, `parseHexColor`, `validateTheme` (as mapped) |
| `term.zig` | 278–356, 363–401, test 918–925 | `ColorTier`, `ColorToken`, `IconPurpose`, `detectColorTier`, `fg`, `bg`, `resetSGR`, `icon`, `stepGlyph`, `selectGlyph` (as mapped) |
| `app.zig` | 406–562 | `Step` (+ `pub fn next/prev/title`), `all_steps`, `App` (+ `pub fn goNext/goBack`), `Action`, `RawMode` (+ `pub fn enable/disable`), `nextAction`, `handleDisk/Identity/Edition/Encrypt` |
| `ui.zig` | 569–815 | `Ctx`, `draw` only |
| `main.zig` | 1–11 header, 817–893 (`step`, `main`), + test block | `main` |

Pubs the D6 map did not list, added because a cross-file call needed them (stop condition: add and note; none needed build.zig):
`app.zig`: `all_steps` (ui's rail), `App`, `RawMode` and its `enable`/`disable`, `App.goNext`/`goBack`, `nextAction`, the four `handle*` (main's driver), `Action` (return type of `nextAction`).
`Colors` in theme.zig stays private; other files reach it only through `Theme.colors` field access, which Zig allows.
The `ascii fallback table` test moved to `term.zig` with the functions it tests, not to theme.zig.
The unused `Edition` import in the old main.zig was dropped; nothing referenced it.

Mechanical proof of the verbatim move (`strip` removes the word `pub`):

```
$ diff <(sed -n '278,356p;363,401p;918,925p' main-orig.zig) <(sed -n '17,95p;97,135p;137,144p' term.zig | strip)  → IDENTICAL
$ diff <(sed -n '406,562p' main-orig.zig) <(sed -n '11,167p' app.zig | strip)                                     → IDENTICAL
$ diff <(sed -n '569,815p' main-orig.zig) <(sed -n '24,270p' ui.zig | strip)                                      → IDENTICAL
$ diff <(sed -n '817,893p' main-orig.zig) <(sed -n '29,105p' main.zig)                                             → IDENTICAL
theme.zig vs 23–271 + tests: only the pub lines and the fmt-realigned tables differ (see Do 1 note).
```

## Acceptance 1: line counts

```
$ wc -l src/*.zig
  167 src/app.zig
  302 src/archinstall.zig
  293 src/cidata.zig
   59 src/config.zig
  112 src/main.zig
  144 src/term.zig
  284 src/theme.zig
  270 src/ui.zig
 1631 total
```

main.zig 112 ≤ 120; largest new file 284 < 400 (and < 600, the `tests/test_file_length.sh` cap).
main.zig's allow-list row (`installer/src/main.zig	931`) is now slack: the file is 112 and could regrow to 931 without the ratchet noticing.
`tests/file-length-allow.txt` is outside this job's files; the one-line follow-up for the lead is `sed -i '/^installer\/src\/main.zig\t/d' tests/file-length-allow.txt`.

## Acceptance 2: zig build test

```
$ zig version
0.14.1
$ zig build && echo BUILD_OK
BUILD_OK
$ zig build test --summary all
Build Summary: 3/3 steps succeeded; 5/5 tests passed
test success
+- run test 5 passed 438us MaxRSS:1M
   +- zig test Debug native cached 7ms MaxRSS:39M
```

Baseline on main (same toolchain, `git archive main installer`): `Build Summary: 3/3 steps succeeded; 4/4 tests passed`.
The four named tests are unchanged and all pass; the fifth is the unnamed `test { _ = @import(...) }` block in main.zig that pulls the other files in, which Zig counts as a test.

```
$ grep -n '^test' src/*.zig
src/main.zig:107:test {
src/term.zig:137:test "ascii fallback table used only when forced" {
src/theme.zig:257:test "parseHexColor parses valid and rejects invalid" {
src/theme.zig:266:test "parseTheme loads the shipped koompi.toml" {
src/theme.zig:280:test "validateTheme fails closed on a missing token" {
(cidata.zig's four tests are unchanged and not reached by the root test step, same as on main)
```

## Acceptance 3: zig fmt

```
$ zig fmt --check src/; echo exit=$?
exit=0
```

## Acceptance 4: captures from main and from the branch

stdin is `/dev/null`, so `RawMode.enable` returns null and the driver auto-advances through all seven screens; the whole run was captured, then the first frame split off at the first `ESC[2J`.
Three environments, so all three color tiers of `detectColorTier` are covered:
truecolor `TERM=xterm-256color COLORTERM=truecolor`, ansi16 `TERM=linux`, none `NO_COLOR=1`.
main's binary was built from `git archive main installer` in `/tmp/main-src`, run from its own `installer/` so it reads its own `themes/koompi.toml`.

```
$ /tmp/capture.sh /tmp/main-src/installer main
truecolor: bytes=21292 frames=7 first_frame_bytes=3024 sha256=b4247f6a17872266
ansi16: bytes=15968 frames=7 first_frame_bytes=2265 sha256=9fbca26cefaeb460
nocolor: bytes=12584 frames=7 first_frame_bytes=1777 sha256=803b3b13ae951c7b
$ /tmp/capture.sh $PWD branch
truecolor: bytes=21292 frames=7 first_frame_bytes=3024 sha256=b4247f6a17872266
ansi16: bytes=15968 frames=7 first_frame_bytes=2265 sha256=9fbca26cefaeb460
nocolor: bytes=12584 frames=7 first_frame_bytes=1777 sha256=803b3b13ae951c7b
$ for v in truecolor ansi16 nocolor; do for k in bin first; do cmp /tmp/cap-main-$v.$k /tmp/cap-branch-$v.$k && echo "cap-main-$v.$k == cap-branch-$v.$k"; done; done
cap-main-truecolor.bin == cap-branch-truecolor.bin
cap-main-truecolor.first == cap-branch-truecolor.first
cap-main-ansi16.bin == cap-branch-ansi16.bin
cap-main-ansi16.first == cap-branch-ansi16.first
cap-main-nocolor.bin == cap-branch-nocolor.bin
cap-main-nocolor.first == cap-branch-nocolor.first
```

`cmp` is silent on identical files, so `diff` of each pair is empty; stderr (`warning: SCAFFOLD: would exec archinstall here; skipping in stub`) is identical too.
The first truecolor frame with SGR stripped, for the eye:

```
┌──────────────────────────────────────────────────────────────────────┐
│ ◆ KOOMPI OS · Naga                              Welcome to KOOMPI OS │
├───────────────────┼──────────────────────────────────────────────────┤
│ ▶ Welcome to KOOMPI OS│◆ KOOMPI OS — Naga                                │
│ · Language, timezone & keyboard│                                                  │
│ · Select a disk   │This installer will set up your machine.          │
│ · Your account    │                                                  │
│ · Choose your edition│                                                  │
│ · Disk encryption │                                                  │
│ · Review          │                                                  │
│ · Installing…     │                                                  │
│ · Done            │                                                  │
├───────────────────┼──────────────────────────────────────────────────┤
│⏎ continue   ^C quit                                                  │
└──────────────────────────────────────────────────────────────────────┘
```

Seen while capturing, not fixed (behaviour change, out of scope): `ui.writeCell` pads but never truncates, so rail labels longer than 19 columns ("Welcome to KOOMPI OS", "Language, timezone & keyboard", "Choose your edition") push the divider right on those rows.
Identical on main; worth a BUG-AUDIT row.

## Repo test suite

`./tests/run.sh` on the branch (zig 0.16 on PATH, as on this machine; the suite does not build the installer):

```
79 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

Same as the baseline on main (79/3/0).
`tests/test_file_length.sh` passes: the four new files are under the 600 cap and main.zig shrank.
A first full run had `test_shell_services.sh` fail once (it runs the Rust workspace's cargo test/clippy, nothing under `installer/`); it passed on its own straight after and in the second full run above, so it reads as contention from parallel worktrees, not this branch.

## Not done, deliberately

- The 0.16 std port (sized above).
- The `TODO`/`PLACEHOLDER`/`REVIEW` comments in `app.zig`'s handlers moved as they were; they mark scaffold the audits track and pruning them is not a split.
- `tests/file-length-allow.txt` row for main.zig (one-liner above, lead's file).

## Round 2: allow-list row for main.zig

Lead confirmed the row is this job's to remove.
Commit `d3f3a245` deletes the single row `installer/src/main.zig	931` from `tests/file-length-allow.txt` (35 → 34 rows; nothing else in the file changed, `git diff --stat`: `1 file changed, 1 deletion(-)`).
main.zig is 112 lines, so it now falls under the plain 600-line Zig cap instead of a ratchet row that would have let it regrow to 931 silently.

```
$ ./tests/test_file_length.sh; echo exit=$?
ok: 783 files under cap, 34 allow-listed and not grown
exit=0
```
