# J16 report — packaging, CI and test-harness bugs (H3 H4 H5 H6 M4 M5 L21 L22 L23)

Branch `j16-packaging-ci-tests`, one commit per finding, in the order below.
Files touched: `sdata/dist-arch/koompi-shell/PKGBUILD`, `sdata/dist-arch/koompi-hyprland-config/PKGBUILD`,
`sdata/dist-arch/koompi-microtex-git/PKGBUILD`, `sdata/dist-arch/repo/build-repo.sh`,
`.github/workflows/{build-packages,installer,build-iso}.yml`, new `.github/workflows/tests.yml`,
`tests/run.sh`, `tests/test_ai_approval_scope.sh`, five new `tests/test_*.sh`, this report. Nothing else.

Every finding was re-verified in the tree before the fix; all nine are confirmed.
Where a command could reproduce the failure it was run (H5 in an Arch container, L22 against a throwaway HOME, M5 the whole workflow in an Arch container).

Dependencies added (per the rules): `rsync` as `makedepends` of `koompi-shell` and `koompi-hyprland-config` (H3).
It was already in `koompi-shell`'s `depends`; `build-packages.yml`'s `--nodeps` path does not install it, so it is also on that workflow's pacman line (see "Observations").

---

## Lead addendum — koompi-lid missing from koompi-shell (main red) — confirmed

After rebasing onto main `4459fb21` (clean, all nine commits replayed), `tests/test_packaged_tools.sh` failed here too:
```
FAIL: dots/.local/bin/koompi-lid is neither in _tools nor in _tools_excluded in koompi-shell/PKGBUILD
rc=1
```
`dots/.local/bin/koompi-lid` is the J15 lid-switch handler (executable, shipped tool).

**Changed:** `koompi-lid` added to `_tools` (alphabetical, after `koompi-launch-webapp`); `pkgrel` 2 → 3. Commit `fix(koompi-shell): ship koompi-lid`.

**Check:**
```
packaged tools: 27 shipped, 2 excluded, all accounted for
rc=0
ok: package trees carry the dots payload and none of the build artefacts      (H3 test, same PKGBUILD)
rc=0
```

## H3 — packaged trees copy zig caches — confirmed

`koompi-shell` and `koompi-hyprland-config` both `cp -a` the dots tree with no excludes (`PKGBUILD:91,94` and `:30` before).
This worktree is a clean checkout so `.zig-cache` was absent, but `.gitignore:23-24` names it and the test below found a real
`dots/.local/bin/__pycache__/touch-gesturescpython-314.pyc` (left by `test_touch_gestures.sh`) already going into `/etc/skel`.

**Changed:** both `package()` functions rsync with the exclude list `sdata/install/files.sh:277-281` uses
(`.git .gitignore .claude zig-out .zig-cache __pycache__ *.pyc .qmlls.ini`); `rsync` added to `makedepends`.
`pkgrel` not bumped: on a clean tree the payload is byte-identical.

**Check:** `tests/test_pkgbuild_excludes_artefacts.sh` copies the real `dots/`, plants each artefact kind (including a submodule `.git` file), runs both real `package()` functions with `startdir/srcdir/pkgdir` set as makepkg does, and fails if anything leaks or the payload (shell.qml, quicklook, `build.zig` beside the pruned cache, tools, hyprland.lua, the `koompi-wallpaper` symlink) is lost.

Before the fix:
```
FAIL: shell-pkg ships build artefacts:
.../shell-pkg/etc/xdg/quickshell/koompi/scripts/__pycache__
.../shell-pkg/etc/xdg/quickshell/koompi/scripts/global-menu/zig-out
.../shell-pkg/etc/xdg/quickshell/koompi/scripts/global-menu/.zig-cache
.../shell-pkg/etc/xdg/quickshell/koompi/.qmlls.ini
.../shell-pkg/etc/xdg/quickshell/koompi/services/stale.pyc
.../shell-pkg/etc/xdg/quickshell/koompi/modules/common/widgets/shapes/.git
.../shell-pkg/etc/xdg/quickshell/koompi/.claude
FAIL: config-pkg ships build artefacts:
... (same list under etc/skel, plus)
.../config-pkg/etc/skel/.gitignore
.../config-pkg/etc/skel/.local/bin/__pycache__/touch-gesturescpython-314.pyc
.../config-pkg/etc/skel/.local/bin/.zig-cache
rc=1
```
After:
```
ok: package trees carry the dots payload and none of the build artefacts
rc=0
packaged tools: 26 shipped, 2 excluded, all accounted for      (test_packaged_tools.sh still green)
```

## H4 — build loops skip `ttf-koompi-star/` — confirmed

`build-repo.sh:39` and `build-packages.yml:61` both loop `koompi-*/`; `sdata/dist-arch/ttf-koompi-star/PKGBUILD` exists, is in `ARCH_DEP_PKGBUILDS` (`install-deps.sh:23`) and `koompi-fonts-themes` depends on it.

**Changed:** both loops walk `sdata/dist-arch/*/` and keep the existing `PKGBUILD`-exists guard; the log line and comment say so.

**Check:** `tests/test_repo_build_set.sh` runs `build-repo.sh` with `makepkg`, `gpg` and `repo-add` shadowed (makepkg records `$PWD`), reads the workflow's `for pkgdir in …; do` glob out of the YAML and expands it, and diffs both against `sdata/dist-arch/*/PKGBUILD`.

Before:
```
@@ -27,4 +27,3 @@
 koompi-widgets
-ttf-koompi-star
FAIL: build-repo.sh does not build every sdata/dist-arch/*/PKGBUILD (- missing, + extra)
FAIL: build-packages.yml does not build every sdata/dist-arch/*/PKGBUILD (- missing, + extra)
rc=1
```
After:
```
ok: both repo build loops cover all 30 PKGBUILDs
rc=0
```

## H5 — root-owned PKGDEST in build-packages.yml — confirmed

Step 3 `chown -R builder:builder "$GITHUB_WORKSPACE"`, step 4 `install -dm755 …/repo/packages` as root, then `sudo -u builder makepkg` with `PKGDEST` pointing there.

**Changed:** `install -dm755 -o builder -g builder …` with a comment saying why.

**Check:** the workflow's user-creation and build steps run in a throwaway `archlinux:latest` podman container against a copy of `sdata/` (koompi-apps, a meta with no build step, as the first package), old line then new line:
```
--- OLD: install -dm755 as root
drwxr-xr-x 2 root root 40 Aug 25 05:43 /work/sdata/dist-arch/repo/packages
==> ERROR: You do not have write permission for the directory $PKGDEST (/work/sdata/dist-arch/repo/packages).
    Aborting...
old: rc=11
--- NEW: install -dm755 -o builder -g builder
drwxr-xr-x 2 builder builder 40 Aug 25 05:43 /work/sdata/dist-arch/repo/packages
==> Making package: koompi-apps 1.0-1 (Tue Aug 25 05:43:13 2026)
==> Finished making: koompi-apps 1.0-1 (Tue Aug 25 05:43:14 2026)
new: rc=0
koompi-apps-1.0-1-any.pkg.tar.zst
```
No `tests/test_*.sh` for this one-line ownership flag; the container run above is the check (script at `/tmp/j16-h5.sh` during the session).

## H6 — test prints FAIL but exits 0 — confirmed

`test_ai_approval_scope.sh:62` and `:85-87` were `console.log(covers(...) ? "PASS…" : "FAIL…")`; `fail` never set.

**Changed:** a `keeps(approved, later, why)` helper beside `grants()` that sets `fail = 1` when a rule no longer covers the later command; both assertions go through it.

**Check:** the test itself (bun present here), then a mutant copy with a false positive (`keeps("free -h", "df -h", …)`):
```
PASS  approving free -h covers free -m
…
PASS  approving an exact risky command still covers itself
ok: an approval covers what it names and nothing more
rc=0
--- mutant
FAIL  approving free -h covers free -m
      approving "free -h" no longer covers "df -h"
mutant rc=1
```

## M4 — `tests/run.sh` counts skips as passes and hides output — confirmed

`run.sh:29-31` counted any exit 0 as passed and printed output only on failure; 17 tests `exit 0` after a "skipping"/"skip:" note (`grep -n skip tests/test_*.sh`).

**Changed:** exit semantics kept (only non-zero fails the run, as the job asks).
A test whose output has a line containing `skipping` or starting with `skip:` (the two spellings in the suite: `echo "... skipping" >&2` and the `skip()` helpers in `test_globalmenu.sh`, `test_shell_services.sh`, `test_ai_e2e.sh`, `test_ai_threads.sh`) is counted as skipped, its note lines are printed under the test, the summary is `N passed, N skipped, N failed`, and the skipped names are listed like the failed ones.
Header comment documents the protocol.
Not classified as skips, deliberately: `test_brightness/charge_limit/bluetooth.sh` print `ok (no busctl, static checks only)`; they ran their static half and report `ok` themselves.

**Check:** `tests/test_run_sh_counts.sh` drives a copy of `run.sh` over pass/skip/fail stand-ins:
```
ok: run.sh reports passed, skipped and failed separately and exits non-zero only on a failure
rc=0
```
Suite on this machine went from the baseline `57 passed, 0 failed` (which hid two skips) to:
```
==> test_globalmenu.sh
      skip: zig daemon is not built
      skip: rust daemon is not built
  -- test_globalmenu.sh (skipped)
==> test_search_bench_parity.sh
      KOOMPI_SEARCH_BENCH is not set to 1 in this shell; skipping (...)
  -- test_search_bench_parity.sh (skipped)

58 passed, 2 skipped, 0 failed
skipped: test_globalmenu.sh test_search_bench_parity.sh
```

## M5 — nothing in CI runs `tests/run.sh` — confirmed

`grep -rn 'tests/run.sh' .github/workflows` found nothing; `installer.yml` exercises the installer only.

**Changed:** new `.github/workflows/tests.yml` (push, pull_request, dispatch), one job on `archlinux:latest`:

1. `pacman -Syu base-devel git sudo rsync jq nodejs bun python python-evdev python-yaml qt6-declarative dbus pipewire zig rust` — each with its reason on the line.
2. checkout with submodules.
3. `useradd -m tester`, chown the workspace (`./setup` refuses root, `common.sh:154`, and `test_abort_propagation.sh` drives it); `/etc/localtime → Asia/Phnom_Penh` (the image has none; `timezone-coords.sh` reads it); `/run/user/tester` for `systemd-analyze --user verify` (`test_sysdefaults.sh`); `mkdir -p /run/systemd/system`, the whole of what `setups.sh:10 systemd_running` checks, because `setup_portals`/`setup_suspend_hook` return early without it and their tests stub every command they would run and expect the gate open. No systemd runs.
4. `sudo -u tester -H env XDG_RUNTIME_DIR=/run/user/tester ./tests/run.sh | tee log`.
5. Gate: the `skipped:` line from M4's run.sh is checked against a named allow-list with a reason per test; any other skip is `::error` and a red job, so a tool missing from step 1 cannot make the run quietly smaller.

**What cannot run there, and how it skips (honestly, per M4):**
- `test_ai_threads.sh`, `test_services_qml_bugs.sh` — need a running `qs`; quickshell is not in the Arch repos (`koompi-quickshell-git` is a Qt source build the job does not attempt). Their static/qmllint halves run.
- `test_search_bench_parity.sh` — only tests a bench-enabled live `qs`.
- `test_ai_e2e.sh` — needs the LiteRT-LM server and memory daemon on the machine; runs the unit-file consistency checks and skips the rest.
- `test_globalmenu.sh` — the zig/rust daemons are built by `./setup`; the conformance suite needs them. (Skips on this machine too.)
- `test_shell_services.sh` — cargo tree/test (281 passed)/clippy and the audiod zig build all run; the two conformance suites need a system bus with NetworkManager/UPower and a live PipeWire socket.
Nothing else skips; `test_touch_gestures.sh` (python-evdev), the bun/node tests, `test_sysdefaults.sh` (makepkg + systemd-analyze) and `test_pkgbuild_excludes_artefacts.sh` (rsync) all run.

**Check — the job's `run:` blocks, read out of the YAML with PyYAML and run in order in a local `archlinux:latest` podman container** (`actions/checkout` replaced by a tar copy of this tree; `RUNNER_TEMP`/`GITHUB_WORKSPACE` set). No `act`. Three iterations, each fixing what the previous one showed:

| run | result | what it showed |
|---|---|---|
| 1 (as root) | `51 passed, 4 skipped, 5 failed` | `test_abort_propagation` (root refused), `test_portal_backends` + `test_suspend_hook` (`systemd_running` false), `test_solar_times` (no `/etc/localtime`), `test_shell_services` (my tmpfs ran out during the rust build — local, not CI) |
| 2 (tester user, zone, systemd dir) | `57 passed, 5 skipped, 3 failed` | `test_iso_release_tag` (no PyYAML in the image → now skips honestly and `python-yaml` is installed), `test_shell_services` (audiod needs `libpipewire-0.3`), `test_sysdefaults` (no `XDG_RUNTIME_DIR`; reproduced locally: fails without, passes with) |
| 3 (final install line, runtime dir) | **`59 passed, 6 skipped, 0 failed`** | gate flagged `test_services_qml_bugs.sh` and `test_shell_services.sh`, both live-desktop skips, now on the allow-list with reasons |

Run 3 tail:
```
::step:: Install what the tests need
real	5m5.039s
::step:: Run the suite
      skip: no LiteRT-LM on http://127.0.0.1:9379 — backend assertions not run
      skip: quickshell (qs) not installed, static checks only
      skip: zig daemon is not built
      skip: rust daemon is not built
      KOOMPI_SEARCH_BENCH is not set to 1 in this shell; skipping (...)
      skip: no system bus; the shelld conformance suite needs NetworkManager and UPower to answer
      skip: no pipewire socket under XDG_RUNTIME_DIR; the audiod conformance suite needs a live PipeWire

59 passed, 6 skipped, 0 failed
skipped: test_ai_e2e.sh test_ai_threads.sh test_globalmenu.sh test_search_bench_parity.sh test_services_qml_bugs.sh test_shell_services.sh
real	3m39.041s
```
The gate step as committed (with the two names added after run 3's mirror script was generated) against run 3's `skipped:` line:
```
gate against run 3 log: rc=0
```
and against a log with an unexpected skip / no skips: `::error::test_touch_gestures.sh skipped in CI: …` rc=1 / rc=0.

**Not run:** the workflow on GitHub itself (nothing was pushed; that is the lead's call). Differences from the mirror: `actions/checkout` (the same action `build-packages.yml` already uses in this image), and GitHub's `RUNNER_TEMP`. Every `run:` block passed shellcheck as bash.

## L21 — microtex soname sed pins — confirmed

`koompi-microtex-git/PKGBUILD:31-32`. Upstream `NanoMichael/MicroTeX` at `0e3707f` (HEAD today, and the commit `pkgver=r494.0e3707f` names) has `pkg_check_modules(GSVMM REQUIRED IMPORTED_TARGET gtksourceviewmm-3.0)` at line 215 and finds tinyxml2 through `pkg_check_modules(tinyxml2 …)` at line 55; **no line contains `tinyxml2.so.10`**, so that sed was a no-op.
Arch's `gtksourceviewmm 1:3.91.1-2` ships `gtksourceviewmm-4.0.pc` (`Requires: gtkmm-3.0`, same API family MicroTeX builds against).

**Changed:** `prepare()` asks `pkg-config --list-all` for the installed `gtksourceviewmm-*` module and seds that in; fails with a message if none. The tinyxml2 sed is removed. `pkg-config` is in `base-devel`.

**Check:** `tests/test_microtex_prepare.sh` runs the real `prepare()` against a CMakeLists stub (upstream's two lines) with `patch` and `pkg-config` shadowed: 4.0 installed, a later 5.0 installed, nothing installed.
```
ok: microtex prepare() takes the gtksourceviewmm module from pkg-config
rc=0
--- real pkg-config on this machine:
gtksourceviewmm-4.0
```
Not built end-to-end: makepkg on it would install cmake/gtkmm3/etc. (stop condition: no package installs).

## L22 — vacuous `|| true` backup assertion in installer.yml — confirmed

`installer.yml:171` `test -d "$fake/.koompi-dots-backup" || true`. Worse than vacuous: the throwaway HOME starts empty, so `backup_existing` (`files.sh:190-222`) has nothing to copy and no backup dir is ever created in that job; a real assertion there would have failed, which is presumably why it was hedged.

**Changed:** the install step plants `~/.config/hypr/hyprland.lua` containing `-- theirs` before the first `./setup install`, asserts the install backed it up under `.koompi-dots-backup/*/`, and the uninstall step asserts the backup is still there and intact (`uninstall.sh:74` promises exactly that).

**Check:** the same sequence locally against a throwaway HOME:
```
install rc=0
  ok backed up 1 file(s) this run will change, to /home/userx/.tmp/tmp.2GyA35xJmN/.koompi-dots-backup/20260825-124920
hyprland.lua installed
backup holds the user's file
uninstall rc=0
shell tree gone
backup survives uninstall
```

## L23 — same-day ISO rebuild dies on existing tag — confirmed

`build-iso.yml:73` `tag="iso-${iso%.iso}"`, `profiledef.sh:15` `iso_version=… +%Y.%m.%d`, so two dispatches on one day create the same `iso-koompi-2026.08.25-x86_64` and the second `gh release create` fails after the full build.

**Changed:** `tag="iso-${iso%.iso}-${GITHUB_SHA::7}"`; if `gh release view "$tag"` already succeeds (a re-run of the same commit) the assets are uploaded with `--clobber` instead of creating again.

**Check:** `tests/test_iso_release_tag.sh` reads the publish step's script out of the YAML and runs it three times with `gh` shadowed (create of an existing tag fails like the real one): two commits on one day, then a re-run.
```
ok: same-day ISO builds get distinct tags and a re-run replaces its own assets
rc=0
```
The committed-before text against the same test:
```
FAIL: the first tag does not carry the ISO version and the short commit
FAIL: the second build the same day did not get a tag of its own
FAIL: re-running the same commit did not upload over its own release
FAIL: expected exactly two 'release create' calls, got: 3
```

## Observations (not changed; outside the findings or the owned files)

- `build-packages.yml` still cannot build the whole set even with H4/H5 fixed: `makepkg --nodeps` skips `makedepends` and the install line has no `zig` (koompi-shell), `cmake`/Qt (koompi-quickshell-git, koompi-microtex-git), `python`/fontforge (ttf-koompi-star), or `rsync` (H3). Severity: medium; the file calls itself a skeleton and the real fix is the dependency-ordered clean-chroot build its own comments describe. `rsync` alone is now on that install line so H3 does not add a new way for it to fail.
- `koompi-microtex-git` has no `pkgver()` and `source=("git+…")` with no `#commit=`, so `pkgver=r494.0e3707f` is a label, not a pin; today HEAD is `0e3707f` so they agree. Severity: low.
- `build-iso.yml` "Checksum the ISO" has a pre-existing shellcheck SC2035 (`sha256sum *.iso`); harmless with archiso's names.
- `tests/test_brightness.sh`, `test_charge_limit.sh`, `test_bluetooth.sh` print `ok (no busctl…, static checks only)` rather than a skip line, so run.sh counts them as passed on a machine without logind/bluez; they did run their static half. Left as is (not owned).

## Gates

- `shellcheck` clean: `tests/run.sh`, `tests/test_ai_approval_scope.sh`, the five new tests, `sdata/dist-arch/repo/build-repo.sh`; the three PKGBUILDs clean with makepkg's globals excluded (`SC2034 SC2148 SC2154 SC2164`); every `run:` block of the four touched workflows clean as bash (one pre-existing SC2035 info in `build-iso.yml`'s checksum step, not touched).
- `python3 -c 'yaml.safe_load'` parses all four workflows.
- `/tmp/j16-ci-repo` removed (`/tmp` back to 272M used).

## `./tests/run.sh` tail (this tree, after the rebase onto main `4459fb21`)

```
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh

63 passed, 2 skipped, 0 failed
skipped: test_globalmenu.sh test_search_bench_parity.sh
rc=0
```
