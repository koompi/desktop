# J25 report — port `installer/src` to zig 0.16's std (std.Io)

Branch `j25-installer-zig-0.16`, based on main `7ffb7128`.
Nine commits, one file each in the contract's order, plus a fix commit on ui.zig and the zon bump (log at the end).
Files touched: `installer/src/{main,term,theme,ui,archinstall,cidata}.zig`, `installer/build.zig.zon` (`minimum_zig_version` only), this file.
`app.zig` and `config.zig` are untouched: nothing they use (`std.posix.tcgetattr/tcsetattr/read`, termios) moved in 0.16.
No stop condition fired: every 0.14 call has a 0.16 equivalent, and the diff is 176 changed lines (< 250).

## Do 1: reproduce

```
$ /usr/bin/zig version; cd installer && zig build
0.16.0
src/main.zig:65:23: error: root source file struct 'heap' has no member named 'GeneralPurposeAllocator'
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
```

## Do 2: the port, file by file

Reference was `/usr/lib/zig/std` (`Io.zig`, `Io/Dir.zig`, `Io/File.zig`, `Io/Writer.zig`, `Io/Threaded.zig`, `process.zig`, `process/Environ.zig`, `testing.zig`, `array_list.zig`, `start.zig`), read before each edit.
Build error after each commit, showing each one moved the compile further:

| commit | file | `zig build` after it |
|---|---|---|
| `40a40f2c` | main.zig | `main.zig:76: expected 1 argument(s), found 2` (loadTheme) |
| `ef41686b` | term.zig | same line 76 (term's change is a call main already made) |
| `4572de9c` | theme.zig | `main.zig:80: no field named 'io' in struct 'ui.Ctx'` |
| `f01f9f47` | ui.zig | `main.zig:86: expected 2 argument(s), found 3` (cidata.detect) |
| `b016c774` | archinstall.zig | same line 86 (archinstall.run is reached later in `step`) |
| `2eb8e9c9` | cidata.zig | builds |
| `04885119` | build.zig.zon | builds |
| `a13e2b86` | ui.zig fix | builds; captures identical (below) |

What each file needed, against J06's inventory:

- **main.zig** — `main(init: std.process.Init.Minimal)`; `std.heap.DebugAllocator(.{}) = .init` replaces `GeneralPurposeAllocator`; one `std.Io.Threaded.init(alloc, .{ .environ = init.environ })` whose `io()` is threaded down: `Ctx.io` for rendering, an explicit `io` argument for `loadTheme`, `cidata.detect`, `archinstall.run`.
  `std.posix.getenv` no longer exists, so the environment comes from `Init.Minimal.environ` and is handed to `detectColorTier`.
  (`main(init: std.process.Init)` would have handed over a ready gpa+io from start.zig in fewer lines; the contract asked for the explicit init, and it keeps the allocator's leak check owned by main as on 0.14.)
- **term.zig** — `detectColorTier(environ: std.process.Environ)`, three `getPosix` lookups. 4 lines.
- **theme.zig** — unmanaged `ArrayList` (`.empty`, `append(alloc, …)`, `toOwnedSlice(alloc)`; `std.array_list.Managed` still exists but is marked deprecated); `loadThemeRaw(io, alloc)` uses `Dir.readFileAlloc` (open+read+close with the same 1 MiB cap) for the same three lookup paths; `std.process.executableDirPathAlloc(io, alloc)` replaces `selfExeDirPathAlloc`.
  Net −7 lines: the three open/defer-close/readToEnd blocks collapse to one call each.
- **ui.zig** — `Ctx` gains `io`; `std.io.fixedBufferStream` → `std.Io.Writer.fixed` + `buffered()` (3 sites; `fixed` and `FixedBufferStream.write` both fill the last partial glyph and then fail, so the 40-byte progress bar is byte-identical); `getStdOut().writer()` → `File.stdout().writerStreaming(ctx.io, &buf)` with one `flush` per frame; 23 `lines.append(alloc, …)`.
  The `fg/bg/resetSGR/writeCell` helpers keep `w: anytype`, so nothing changed there.
- **archinstall.zig** — `Dir.cwd().createDirPath/createFile/deleteFile/writeFile(io, …)`; `.mode = 0o600` → `.permissions = .fromMode(0o600)`; `bufferedWriter(file.writer())` → `file.writer(io, &buf)` + `&fw.interface` + `w.flush()`; `Child.init`+`spawnAndWait` → `std.process.spawn(io, .{ .argv, .stdin/.stdout/.stderr = .inherit })` + `child.wait(io)`; `Term.Exited` → `.exited`.
  The hook drop (`createFile` + `writeAll` + `close` block) is one `Dir.writeFile` call with the same truncate + 0o755 flags.
  `run`, `writeUserConfiguration`, `writeUserCredentials`, `cleanupCredentials`, `runArchinstall`, `runPostInstallHook` gain `io`; the three that no longer need `alloc` drop it (`runArchinstall`, `runPostInstallHook`, `cleanupCredentials` — the last never had it).
- **cidata.zig** — `detect(alloc, io, cfg)`, `detectFromRoot(alloc, io, cfg, dir: std.Io.Dir)`; `dir.readFileAlloc(io, name, alloc, .limited(n))`; `dir.access(io, …)`; `Child.run(.{ .allocator, .argv, .max_output_bytes })` → `std.process.run(alloc, io, .{ .argv, .stdout_limit = .limited(256 * 1024) })` (same cap, same fail-open `catch return null`); `mount`/`umount` on `spawn`+`wait`.
  `unmount` now warns on a spawn failure as well as a wait failure (before, both came out of the one `spawnAndWait`); same message, same swallow.
  The four tests take `std.testing.io` and pass it to `tmpDir`'s `Io.Dir` and `writeFile`.

Behaviour notes, all on error paths the captures do not reach:
`loadThemeRaw` now falls through to the next path on a *read* error too, not only an open error (0.14 propagated a read error from an opened file);
`Dir.readFileAlloc` returns `error.StreamTooLong` where `readToEndAlloc` returned `error.FileTooBig` — both are caught by the same `catch`/`else => return err` arms.

## Do 3

`installer/build.zig.zon`: `.minimum_zig_version = "0.16.0"` (commit `04885119`).
The zon's header comment (`(Zig 0.14.x)`) and build.zig's (`src/ needs 0.14.x std`) are now stale; both are outside this job's files.
For the lead: `sed -i '1s/(Zig 0.14.x)/(Zig 0.16)/' installer/build.zig.zon` and `sed -i '1s/Zig 0.14+ build API; src\/ needs 0.14.x std/Zig 0.16/' installer/build.zig`.

## Acceptance 1: `zig build test --summary all` on 0.16

```
$ zig version
0.16.0
$ zig build test --summary all
Build Summary: 3/3 steps succeeded; 5/5 tests passed
test success
+- run test 5 pass (5 total) 6ms MaxRSS:5M
   +- compile test Debug native success 395ms MaxRSS:148M
$ zig test src/main.zig
1/5 main.test_0...OK
2/5 theme.test.parseHexColor parses valid and rejects invalid...OK
3/5 theme.test.parseTheme loads the shipped koompi.toml...OK
4/5 theme.test.validateTheme fails closed on a missing token...OK
5/5 term.test.ascii fallback table used only when forced...OK
All 5 tests passed.
```

The same five J06 left (four named + main's import block).
cidata's four are still not reached by the root test step: main.zig's `test { _ = @import(...) }` block imports theme/term/app/ui and not cidata, unchanged from main (J06 left it that way; adding `_ = @import("cidata.zig");` there would pull them in).
They compile and pass on 0.16 when run directly:

```
$ zig test src/cidata.zig
1/4 cidata.test.no cidata present -> .none...OK
2/4 cidata.test.user_configuration.json + user_credentials.json -> .configured with parsed fields...OK
3/4 cidata.test.user_configuration.json + defer-provisioning marker -> .deferred...OK
4/4 cidata.test.cidata label present but user_configuration.json missing -> .none (fail open)...OK
All 4 tests passed.
$ zig fmt --check src/; echo fmt_exit=$?
fmt_exit=0
```

## Acceptance 2: the three `cmp` results

Same method as J06: stdin `/dev/null` (RawMode fails open, the driver auto-advances through all seven screens), `env -i` with one of
truecolor `TERM=xterm-256color COLORTERM=truecolor`, ansi16 `TERM=linux`, nocolor `NO_COLOR=1 TERM=xterm-256color COLORTERM=truecolor`;
whole run captured to `.bin`, first frame split at the second `ESC[2J` into `.first` (my split keeps the leading `ESC[2J`, hence first_frame_bytes is J06's +4), stderr to `.err`.
main's binary: `git archive main installer` → `/tmp/j25-main-src`, built with `~/.cache/lead-zig/current/zig` (0.14.1); branch binary: this tree, `/usr/bin/zig` 0.16.0.
Script at `/tmp/j25-capture.sh` (disposable).

```
$ /home/userx/.cache/lead-zig/current/zig version
0.14.1
$ (cd /tmp/j25-main-src/installer && ~/.cache/lead-zig/current/zig build && echo MAIN_BUILD_OK)
MAIN_BUILD_OK
$ zig build && echo BRANCH_BUILD_OK
BRANCH_BUILD_OK
$ /tmp/j25-capture.sh /tmp/j25-main-src/installer main
truecolor: bytes=21292 frames=7 first_frame_bytes=3028 sha256=b4247f6a17872266
ansi16: bytes=15968 frames=7 first_frame_bytes=2269 sha256=9fbca26cefaeb460
nocolor: bytes=12584 frames=7 first_frame_bytes=1781 sha256=803b3b13ae951c7b
$ /tmp/j25-capture.sh $PWD branch
truecolor: bytes=21292 frames=7 first_frame_bytes=3028 sha256=b4247f6a17872266
ansi16: bytes=15968 frames=7 first_frame_bytes=2269 sha256=9fbca26cefaeb460
nocolor: bytes=12584 frames=7 first_frame_bytes=1781 sha256=803b3b13ae951c7b
$ for v in truecolor ansi16 nocolor; do for k in bin first err; do cmp /tmp/j25-cap-main-$v.$k /tmp/j25-cap-branch-$v.$k && echo "cap-main-$v.$k == cap-branch-$v.$k"; done; done
cap-main-truecolor.bin == cap-branch-truecolor.bin
cap-main-truecolor.first == cap-branch-truecolor.first
cap-main-truecolor.err == cap-branch-truecolor.err
cap-main-ansi16.bin == cap-branch-ansi16.bin
cap-main-ansi16.first == cap-branch-ansi16.first
cap-main-ansi16.err == cap-branch-ansi16.err
cap-main-nocolor.bin == cap-branch-nocolor.bin
cap-main-nocolor.first == cap-branch-nocolor.first
cap-main-nocolor.err == cap-branch-nocolor.err
```

The three whole-run sha256 prefixes are the same ones J06 recorded (`b4247f6a…`, `9fbca26c…`, `803b3b13…`), so the 0.16 binary's output also matches J06's 0.14.1 build of main, byte for byte, across all seven screens.

The fix commit `a13e2b86` exists because the first capture from the branch did not match: 1 frame, 3108 bytes, per tier.
`File.writer` is positional by default (pwrite at the writer's own offset, from 0) and `draw` builds a fresh writer per frame, so with stdout redirected to a file each frame overwrote offset 0 and the file held only the last screen.
`writerStreaming` is the right mode for stdout and is what 0.14's plain `write()` did; on a tty both modes behave the same, which is why it only showed up under capture.

## Acceptance 3: diff against main and the line count

```
$ git diff --stat main -- installer
 installer/build.zig.zon       |   2 +-
 installer/src/archinstall.zig | 125 +++++++++++++++++++++---------------------
 installer/src/cidata.zig      |  81 ++++++++++++++-------------
 installer/src/main.zig        |  19 ++++---
 installer/src/term.zig        |   8 +--
 installer/src/theme.zig       |  39 ++++++-------
 installer/src/ui.zig          |  73 ++++++++++++------------
 7 files changed, 176 insertions(+), 171 deletions(-)
$ git diff --numstat main -- installer
1	1	installer/build.zig.zon
62	63	installer/src/archinstall.zig
43	38	installer/src/cidata.zig
12	7	installer/src/main.zig
4	4	installer/src/term.zig
16	23	installer/src/theme.zig
38	35	installer/src/ui.zig
```

176 lines changed (insertions; deletions 171, net +5) against J06's 110–140 estimate: 36 over the top, under the 250 stop line.
Where the estimate stretched: J06 counted 78 call sites + 18 signatures; the extra is (a) 23 `lines.append(alloc, …)` in ui.zig — the managed→unmanaged ArrayList change touches every append, not just the init, and J06's grep counted `init/append/toOwnedSlice` as one site per function; (b) the `spawn(io, .{ .argv = &.{ … } })` struct literals in archinstall.zig, where `zig fmt` puts the six archinstall args on their own lines inside `.argv` (7 lines to say what `Child.init(&.{…}, alloc)` said in 7, but each one moved); (c) the six Threaded/env lines in main.

```
$ wc -l src/*.zig
  167 src/app.zig
  301 src/archinstall.zig
  298 src/cidata.zig
   59 src/config.zig
  117 src/main.zig
  144 src/term.zig
  277 src/theme.zig
  273 src/ui.zig
 1636 total
```

main.zig 117 ≤ 120; largest file 301 < 600.

## Acceptance 4: repo suite and file length

```
$ ./tests/test_file_length.sh; echo exit=$?
ok: 784 files under cap, 33 allow-listed and not grown
exit=0
```

(784/33 vs J06's 783/34: the J26 length-walk commit on main since then; nothing from this branch.)

`./tests/run.sh` on the branch (zig 0.16 on PATH; the suite does not build the installer), full run, tail:

```
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

79 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

Same as the baseline on main (79/3/0). `test_shell_services.sh` passed first time.

## Commits

```
a13e2b86 installer: ui.zig writes stdout in streaming mode
04885119 installer: minimum_zig_version 0.16.0
2eb8e9c9 installer: cidata.zig on Io.Dir and process.run/spawn
b016c774 installer: archinstall.zig on Io.Dir, File.Writer and process.spawn
f01f9f47 installer: ui.zig on Io.Writer
4572de9c installer: theme.zig on Io.Dir and unmanaged ArrayList
ef41686b installer: term.zig reads env through process.Environ
40a40f2c installer: main.zig on zig 0.16 std (DebugAllocator, Io.Threaded, io handle)
```

## Not done, deliberately

- The stale `0.14` header comments in `build.zig` / `build.zig.zon` (outside this job's files; one-liners under Do 3).
- Pulling cidata's tests into the root test step (one import line in main.zig's test block; J06 left it out and the contract asked only which tests are reached).
- The `writeCell` never-truncates rail overflow J06 flagged: identical on main, behaviour change, out of scope.
