# J02 report — delete the dead vendored vaxis (AUDIT D1)

Branch `j02-delete-vaxis`, based on main `d552876a`.
Files touched: `installer/zig-pkg/**` (55 files, 776 KB, deleted), `installer/build.zig.zon` (the line-3 comment only), this file.
Nothing under `installer/src/`, `installer/build.zig`, or any other vendored directory was changed.

## Do 1: nothing imports `zig-pkg` or `vaxis`

Before deletion, excluding the directory itself:

```
$ grep -rn 'zig-pkg\|vaxis' installer/ --include='*.zig' --include='*.zon' --include='build.zig' | grep -v '^installer/zig-pkg/'
installer/build.zig:4:// direct ANSI, not libvaxis; see build.zig.zon.
installer/build.zig.zon:3:// No dependencies: vaxis was imported but never actually wired to any rendering
installer/src/main.zig:6://! hard-coded color, glyph, or brand string below `draw()`. No vaxis: rendering is direct

$ grep -rn 'zig-pkg\|vaxis' .github/workflows/
(no output, exit 1)
```

All three hits are `//` comments. No `@import`, no `.dependencies` entry (`build.zig.zon:18` is `.dependencies = .{}`), no path. The stop condition does not fire.

The same grep after deletion, same scope:

```
installer/src/main.zig:6://! hard-coded color, glyph, or brand string below `draw()`. No vaxis: rendering is direct
installer/build.zig:4:// direct ANSI, not libvaxis; see build.zig.zon.
```

For the record, a repo-wide grep also finds prose mentions of "libvaxis" in `installer/README.md` (5 lines), `installer/docs/ui-ux.md` (4 lines) and `sdata/dist-arch/iso/koompi/packages.x86_64:33`. Those describe the TUI's original plan, are not code, and are outside the files this job owns; left as they are.

## Do 2: `git rm -r installer/zig-pkg`

```
$ git rm -r -q installer/zig-pkg && echo "git rm ok"
git rm ok
$ ls installer/zig-pkg
ls: cannot access 'installer/zig-pkg': No such file or directory
```

## Do 3: `build.zig.zon:3`

Line 3 was a five-line history of why vaxis was dropped (pointing at `.work/P3-report.md`). Now one line:

```
-// No dependencies: vaxis was imported but never actually wired to any rendering
-// (confirmed dead import) and its only pinned version needs Zig >=0.16, which
-// breaks archinstall.zig/cidata.zig's pre-Writergate stdlib usage on this
-// toolchain. Rendering is direct ANSI (see main.zig) instead — no fetch, no
-// version coupling. See .work/P3-report.md for the full reasoning.
+// No dependencies: rendering is direct ANSI (see main.zig), so nothing is fetched.
```

## Do 4: `zig build` and `zig build test`

Per the lead's correction (a): this machine has `zig 0.16.0` and `installer/build.zig:14` uses `root_source_file`, which 0.16 removed from `Build.ExecutableOptions`. Both commands already fail on main; fixing `build.zig` is J06. What this job has to show is that the deletion changed nothing there.

Before deletion (main `d552876a` + nothing):

```
$ cd installer && zig build
build.zig:14:10: error: no field named 'root_source_file' in struct 'Build.ExecutableOptions'
        .root_source_file = b.path("src/main.zig"),
         ^~~~~~~~~~~~~~~~
/usr/lib/zig/std/Build.zig:770:31: note: struct declared here
pub const ExecutableOptions = struct {
                              ^~~~~~
referenced by:
    runBuild__anon_34225: /usr/lib/zig/std/Build.zig:2264:33
    main: /usr/lib/zig/compiler/build_runner.zig:463:29
    5 reference(s) hidden; use '-freference-trace=7' to see all references
exit=2

$ cd installer && zig build test
(same error, runBuild__anon_34232)
exit=2
```

After deletion:

```
$ cd installer && zig build
build.zig:14:10: error: no field named 'root_source_file' in struct 'Build.ExecutableOptions'
        .root_source_file = b.path("src/main.zig"),
         ^~~~~~~~~~~~~~~~
/usr/lib/zig/std/Build.zig:770:31: note: struct declared here
pub const ExecutableOptions = struct {
                              ^~~~~~
referenced by:
    runBuild__anon_34223: /usr/lib/zig/std/Build.zig:2264:33
    main: /usr/lib/zig/compiler/build_runner.zig:463:29
    5 reference(s) hidden; use '-freference-trace=7' to see all references
exit=2

$ cd installer && zig build test
(same error, runBuild__anon_34223)
exit=2
```

`diff` of the four captures with the `__anon_NNNNN` suffix stripped (it is a per-invocation counter, not a code identity):

```
build: identical
test: identical
```

So Acceptance 3 as written ("exit 0, 4 tests passing") cannot be met on this toolchain by any change inside this job's owned files; it is replaced, per the lead, by "identical failure before and after". The failure is at `build.zig:14`, before the manifest or any package directory is consulted, so the deletion is not on the path that fails.

## Acceptance 2: `git status --short`

```
$ git -c color.ui=never status --short | awk '{print $1}' | sort | uniq -c
     55 D
      1 M
$ git -c color.ui=never status --short | grep -v 'installer/zig-pkg/'
 M installer/build.zig.zon
```

55 `D` lines, all under `installer/zig-pkg/vaxis-0.6.0-BWNV_HHwCQB451KS7A8SMykALblPmGwHnzSfiJHjN3_9/`, plus the one `.zon` edit. Matches the AUDIT row's "55 files, 776 KB".

## Acceptance 4: `./tests/run.sh`

Baseline per the lead's correction (b): main `d552876a` is 78 passed, 3 skipped, 0 failed (the job file's "56 or 57" predates later jobs landing).

After deletion:

```
$ ./tests/run.sh; echo "exit=$?"
...
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

78 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
exit=0
```

Unchanged from baseline. J01 had not landed on this base, so no 79th test.

## Stop conditions

Step 1 showed no `@import` of vaxis anywhere, only comments. Deletion proceeded.
