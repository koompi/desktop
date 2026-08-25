# J17 report — shell script and Lua config bugs

Branch `j17-shell-script-bugs`, based on `b49e613d` (merge-base with main).
15 commits: 11 fixes (one per finding), 4 test commits.
Files touched: `dots/.config/quickshell/koompi/scripts/colors/switchwall.sh`, `sdata/install/apps.sh`, `sdata/dist-arch/install-apps.sh`, `sdata/install/setups.sh` (M20/L20 lines only), `dots/.local/bin/koompi-displays`, `dots/.local/bin/koompi-stacking`, `dots/.config/hypr/custom/scripts/koompi-wallpaper.sh` (the target of the `dots/.local/bin/koompi-wallpaper` symlink; see L19), `dots/.config/hypr/hyprlock/status.sh`, `dots/.config/hypr/hyprland/general.lua`, eight new `tests/test_*.sh`.

All eleven rows confirmed.
One (L25) is milder than the audit describes; the row is still a bug and was fixed.
Every new test was run against the pre-fix file as well and fails there (evidence under each finding).

Two things for the lead, neither in my files:

- `setup:225` runs `$DO_APPS && install_apps` and ignores the status. After H9 a failed recipe now prints `xx the arch application recipe failed` and skips the agent installs, but `./setup` still goes on to setups/files and prints the `==> Done` banner. The audit's fix stops at apps.sh; whether a failed app set should abort the install (as deps does via `|| die`) is a `setup` decision. The test asserts only on what apps.sh controls.
- Two gates in `.work/BACKLOG.md` are not green on this machine for reasons outside this branch: `installer` `zig build test` fails at `build.zig:14` (`no field named 'root_source_file'`, system zig 0.16 API change; `git diff b49e613d..HEAD -- installer` is empty), and `shellcheck -x setup install.sh sdata/install/*.sh` reports one info, `setups.sh:168` SC2016, on a line from `160c55a93` (2026-08-01). `cli` `zig build test` exits 0.

---

## M1 — switchwall writes literal `"null"` into config.json

**Verdict: confirmed.**

```
$ jq -r '.background.wallpaperPath' <<< '{}'; echo "rc=$?"
null
rc=0
```

So `|| echo ""` never fired and `imgpath="null"` flowed into `set_wallpaper_path`.

**Changed** (`87f02631`): `switchwall.sh:410` reads `jq -r '.background.wallpaperPath // empty'`; the existing `-z "$imgpath"` guard in `switch()` then prints `Aborted` and exits 0.

**Check:** `tests/test_switchwall_noswitch.sh` step 1 (config with no wallpaper, `--noswitch`): asserts `Aborted`, `wallpaperPath` still unset, matugen not run.

```
$ bash tests/test_switchwall_noswitch.sh
switchwall --noswitch test passed
# same test with the b49e613d switchwall.sh copied over the fixed one:
FAIL: expected 'Aborted' with no wallpaper, got:
```

## M2 — venv path sourced while possibly unset

**Verdict: confirmed.**

```
$ env -u ILLOGICAL_IMPULSE_VIRTUAL_ENV bash -c 'echo "[$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")/bin/activate]"'
[/bin/activate]
```

**Changed** (`26081646`): `VENV_DIR="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$XDG_STATE_HOME/quickshell/.venv}"` (the default `hyprland/env.lua:40` and `sdata/lib/common.sh:27` use) and an `activate_venv()` that prints `switchwall: no Python venv at …; run './setup install --only-setups'` and returns 1 when `bin/activate` is missing. `switch()` calls it before matugen and exits 1 on failure, so a missing venv leaves the current theme whole; `detect_scheme_type_from_image` returns 1 and the existing fallback to `scheme-tonal-spot` fires. The `eval echo` is gone: the value is an absolute path from our own config.

**Check:** `tests/test_switchwall_noswitch.sh` steps 2 and 3: with no venv → exit 1, message on stderr, matugen not run; with a venv at the default path and the env var unset → exit 0, matugen run, `material_colors.scss` written.

```
# pre-fix script, steps 2-3 only:
FAIL: a missing venv exited 0
# pre-fix script, step 3 only (venv at the default path, env var unset):
FAIL: material_colors.scss was not written
```

## M3 — wallpaper categorization writes into a directory nothing creates

**Verdict: confirmed.** `grep -rn 'generated/wallpaper' dots sdata` finds the write in `switchwall.sh`, a read in `Directories.qml:46`, and matugen's `wallpaper/path.txt` template (`matugen/config.toml:42`), which is the only thing that ever creates the directory and runs after `categorize_wallpaper` has already been forked into the background.

```
$ bash -c 'STATE_DIR=$(mktemp -d); echo nature > "$STATE_DIR/user/generated/wallpaper/category.txt"; echo "rc=$?"'
bash: line 1: /home/userx/.tmp/tmp.BXfiw6oNUa/user/generated/wallpaper/category.txt: No such file or directory
rc=1
```

**Changed** (`e690a4cb`): `mkdir -p "$STATE_DIR/user/generated/wallpaper"` before the write.

**Check:** `tests/test_switchwall_noswitch.sh` step 3 asserts the directory does not exist before the run and `category.txt` holds `nature` after it (polled, the categoriser is backgrounded). Passes on the fixed script; the pre-fix script cannot reach this point (fails at M2 first, output above).

## H9 — failed app recipe still reports "applications installed"

**Verdict: confirmed.** `apps.sh:46` sourced the recipe unchecked; `install-apps.sh:20` dropped `arch_install_pkgbuild`'s return value, which is 1 without a die when makepkg is skipped at the prompt or builds no package (`arch.sh:133,147`).

**Changed** (`204820ee`): `source "$recipe" || { err "the $OS_GROUP_ID application recipe failed"; return 1; }` (mirrors `deps.sh:23`) and `arch_install_pkgbuild koompi-apps || return 1`.

**Check:** `tests/test_apps_abort_propagation.sh` — `./setup install --only-apps --yes` with makepkg predicting a package it never produces, pacman/paru/sudo/git and every agent CLI stubbed, no network.

```
$ bash tests/test_apps_abort_propagation.sh
apps abort propagation test passed
# with b49e613d apps.sh + install-apps.sh:
the failed recipe was not reported by install_apps
```

Fixed-tree output excerpt: `xx koompi-apps built no package to install` / `xx the arch application recipe failed`, no `applications installed`, no `==> KOOMPI Workbench` step. See the note to the lead about `setup:225`.

## M20 — zig builds use the subshell-abort anti-pattern

**Verdict: confirmed.** `setups.sh:30-34` and `:82` were `( cd "$src" && run zig build … )`; `common.sh:103-114` documents why that swallows `die`. `setup_global_menu` passed no `--cache-dir`, so `.zig-cache` grew inside the installed config tree.

**Changed** (`8802cc43`): both use `run_in_dir`. The global menu build gets `--cache-dir "$XDG_CACHE_HOME/koompi/build/global-menu/cache" --global-cache-dir "$XDG_CACHE_HOME/zig"`; not the audit's `build/globalmenu`, which is already the cargo target dir of `setup_globalmenu_rs`. The prefix stays `zig-out/` in the tree because `GlobalMenuService.qml` and `setup doctor` resolve the daemon there.

**Check:** `tests/test_zig_build_abort.sh` sources `common.sh` + `setups.sh` under `ASSUME_YES=true` with a zig stub that reports 0.16.0 and fails the build.

```
$ bash tests/test_zig_build_abort.sh
zig build abort test passed
# with b49e613d setups.sh:
FAIL: setup_global_menu exited 0 after zig build failed
```

(The CLI half of the old code was caught downstream by `run install` on the missing binary, as the audit said; the test covers both functions plus the cache-dir and no-prefix assertions.)

## L20 — `mktemp -u` race

**Verdict: confirmed.** `setups.sh:425` picked a name and let the daemon create it; `rm -f "$db"` also missed sqlite's `-wal`/`-shm` siblings (`koompi-agent-memd/src/db.rs` opens it with rusqlite).

**Changed** (`ffb4a007`): `db_dir="$(mktemp -d …)"`, DB at `$db_dir/memory.db`, `rm -rf -- "${db_dir:?}"`; a failed mktemp warns and returns 0 like the other soft failures in that function.

**Check:** no separate test; the function needs a built daemon and a 100 MB model fetch. Reviewed by shellcheck (`-x`, clean apart from the pre-existing line 168 info) and by reading: `db_dir` is always set before the `rm -rf`, and `:?` refuses an empty value.

## M22 — koompi-displays needs lua/luac, declared nowhere

**Verdict: confirmed.** `grep -rn lua sdata/dist-arch/*/PKGBUILD | grep -i depend` → nothing.

```
$ bash -c 'PATH=/nonexistent; if luac -p /dev/null 2>/dev/null || lua -e "" 2>/dev/null; then echo validated; else echo "falls to: failed lua validation, not persisted"; fi'
falls to: failed lua validation, not persisted
```

**Changed** (`bc0f61d5`): `validate_lua()` runs `luac -p`, else `lua -e assert(loadfile)`, else returns 0. The file is a fixed template filled by jq; adding `lua` to a PKGBUILD is J16's file, so the fallback was the fix inside my files.

**Check:** `tests/test_displays_persist.sh` — `place HDMI-A-1 right` with hyprctl stubbed and a PATH containing no lua: persists, two `hl.monitor` hot-applies, file passes the host's real `luac -p`; then with a `luac` stub that exits 1: exit 1, `failed lua validation`, file unchanged.

```
$ bash tests/test_displays_persist.sh
displays persist test passed
# with b49e613d koompi-displays:
FAIL: place exited 1 with no lua interpreter: koompi-displays: generated monitors.lua failed lua validation, not persisted
```

## L18 — predictable /tmp names, no cleanup trap in koompi-stacking

**Verdict: confirmed.** `koompi-stacking:73-74,146-147` used `/tmp/.koompi-stacking-{mon,cli,act}.$$`; `maximize` runs under `set -e` outside a command substitution, so a failing `hyprctl activewindow` left the monitor snapshot behind.

**Changed** (`fe303c26`): one `SCRATCH="$(mktemp -d)"` at startup with `trap 'rm -rf -- "${SCRATCH:?}"' EXIT`; the two `rm -f` lines are gone.

**Check:** `tests/test_stacking_scratch.sh` — `clamp` with a window out of bounds (moved, TMPDIR empty afterwards) and `maximize` with `hyprctl activewindow` failing (exit non-zero, TMPDIR empty, nothing new under `/tmp/.koompi-stacking-*`).

```
$ bash tests/test_stacking_scratch.sh
stacking scratch test passed
# with b49e613d koompi-stacking:
FAIL: scratch files written to the shared /tmp: /tmp/.koompi-stacking-act.734477
/tmp/.koompi-stacking-mon.734477
```

## L19 — fixed `.tmp` sibling races concurrent config writers in koompi-wallpaper

**Verdict: confirmed.** Lines 148, 177, 215 wrote `"$CONFIG_FILE.tmp"`; `json_update` at line 73 used `mktemp` in `$TMPDIR`, so its `mv` is a copy when `$TMPDIR` is tmpfs.

`dots/.local/bin/koompi-wallpaper` is a symlink to `dots/.config/hypr/custom/scripts/koompi-wallpaper.sh`; the edit is to the target, which no other job owns (`.work/BACKLOG.md`).

**Changed** (`868e5746`): `json_update` takes extra jq args, creates its temp with `mktemp -- "$CONFIG_FILE.XXXXXX"` (same directory, so the `mv` is a rename), removes it and fails if jq fails; the three inline writers call it. `commit_config`'s `jq -e 'type == "object"'` before the `mv` is unchanged.

**Check:** `tests/test_wallpaper_config_write.sh` — a pre-planted `config.json.tmp` stands in for another writer; `set`, `mode`, `seed` on a throwaway config must leave it untouched, leave no `config.json.*` of their own, and keep the config valid.

```
$ bash tests/test_wallpaper_config_write.sh
wallpaper config write test passed
# with b49e613d koompi-wallpaper.sh:
FAIL: the other writer's config.json.tmp was consumed or overwritten
```

## L24 — hyprlock status reads every power supply

**Verdict: confirmed.** `status.sh:11,23` read `/sys/class/power_supply/*/status|capacity | head -1`. On this machine it works by accident (`AC` has no `status` file, `BAT0` sorts next); any supply that sorts before the pack and has those files answers for it.

**Changed** (`5b43ca19`): both reads use the `$battery` the `*BAT*` loop selected. `POWER_SUPPLY_DIR` (default `/sys/class/power_supply`) exists so the test can point the script at a fake tree.

**Check:** `tests/test_hyprlock_battery.sh` — fake tree with `AAA-hidpp_battery_0` (sorts first), `BAT0`, a `ucsi-source-psy-*`; charging, discharging, and no-battery cases.

```
$ bash tests/test_hyprlock_battery.sh
hyprlock battery test passed
# with b49e613d status.sh:
FAIL: charging pack beside other supplies: got '(+) 40%', want '(+) 80%'
```

## L25 — hardcoded touchdevice output eDP-1

**Verdict: confirmed, milder than stated.** Hyprland 0.56.2 (`src/managers/input/InputManager.cpp` `setTouchDeviceConfigs`): a bound name that resolves to no monitor logs `Failed to bind touch device` at every config load; `src/managers/input/Touch.cpp` `onTouchDown` then falls back to the focused monitor. So on a desktop with a touchscreen and no eDP the effect is an error per reload plus the same mapping as the default, not a mapping to a nonexistent output. The hard-coded per-machine name is still wrong in a shipped config.

`hl.get_monitors()` exists in the Lua API (`LuaBindingsQuery.cpp`) but Hyprland loads the config before the backend creates monitors, so it answers nothing on first start. The DRM connector list is available at config time and uses the same names.

**Changed** (`4a70a153`): `internal_panel()` reads `ls /sys/class/drm` via `io.popen` (the config already uses `io`/`os` in `lib/init.lua`; `io.popen` verified in the live session with `hyprctl eval`) and returns the first `card*-eDP-*` connector name; `touchdevice.output` is that or unset. On this laptop: `card0-eDP-1` → `eDP-1`, unchanged behaviour. `luac -p general.lua` clean.

**Check:** `tests/test_touch_output.sh` loads `general.lua` under system `lua` with `hl` stubbed and `io.popen` answering a chosen listing: `eDP-1`, `eDP-2` on another card, and no eDP → unset. Skips with a note when `lua` is absent.

```
$ bash tests/test_touch_output.sh
touch output test passed
# with b49e613d general.lua:
FAIL: panel on a different connector index: got 'eDP-1', want eDP-2
```

Not verified: a Hyprland restart with the new config (stop condition; the session running this job is the one it would restart). The Lua was exercised only under system `lua` and, for `io.popen`, via `hyprctl eval` in the live session.

---

## Gates

```
$ shellcheck -x setup install.sh sdata/install/*.sh; shellcheck -x -s bash sdata/lib/*.sh; shellcheck -x -s bash sdata/dist-*/install-deps.sh sdata/dist-*/install-apps.sh
In sdata/install/setups.sh line 168: SC2016 (info)      # pre-existing, 160c55a93 2026-08-01, not a J17 line
$ shellcheck -x switchwall.sh koompi-displays koompi-wallpaper.sh status.sh tests/test_{switchwall_noswitch,apps_abort_propagation,zig_build_abort,displays_persist,stacking_scratch,wallpaper_config_write,hyprlock_battery,touch_output}.sh
TOUCHED_SHELLCHECK_OK
$ shellcheck -x dots/.local/bin/koompi-stacking
line 246: SC2015 (info)                                  # pre-existing, not a J17 line
$ luac -p dots/.config/hypr/hyprland/general.lua && echo LUAC_OK
LUAC_OK
$ (cd cli && zig build test); echo rc=$?
rc=0
$ (cd installer && zig build test)
build.zig:14:10: error: no field named 'root_source_file' in struct 'Build.ExecutableOptions'   # pre-existing, installer/ untouched
```

## `./tests/run.sh` tail

```
$ ./tests/run.sh | tail -8
  ok test_workspace_icon_migration.sh
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

66 passed, 0 failed
run.sh rc=0
```

66 tests discovered (58 at `b49e613d`, the branch base, + 8 from this job; the `.work/BACKLOG.md` baseline of 56 predates J13/J14); every one passes.

