# J01 report — length cap in conventions + ratchet test

Branch `j01-length-cap-ratchet` on top of `d552876a`.
Files touched: `docs/conventions.md`, `tests/test_file_length.sh` (new), `tests/file-length-allow.txt` (new). Nothing else.

## Do

1. `docs/conventions.md`: new "File and function length" section between "Files and directories" and "Identifiers inside QML". Caps table (QML 400/60, JS+Lua 300/50, bash 400/60, Zig 600/80), a paragraph on why, a paragraph on the ratchet, the four sources from `.work/AUDIT.md`.
2. `tests/test_file_length.sh`: walks `git ls-files`, keeps `*.qml *.js *.lua *.sh *.zig`, `setup`, `install.sh`, `dots/.local/bin/*`; skips any path under `installer/zig-pkg/`, `graphify-out/`, `translations/`, `tests/`. Counts lines with `awk 'END{print NR}'` (counts a last line with no newline; `wc -l` does not). Fails on a file over cap not in the allow-list, on an allow-listed file over its listed count, on a malformed, duplicate, unsorted or stale allow-list row. Hooks: `FILE_LENGTH_FILES` (path list instead of `git ls-files`) and `FILE_LENGTH_ROOT` (where to read them). shellcheck clean. Runtime 4.4 s.
3. `tests/file-length-allow.txt`: generated from the tree at `d552876a` with the same counting rule, `LC_ALL=C` sorted. 35 rows.
4. `./tests/run.sh` tail below.

## Decisions taken (not in the job text)

- **Two Python scripts in `dots/.local/bin/`** (`koompi-remotedesktop-portal` 526, `touch-gestures` 297). The job walks `dots/.local/bin/*` as one group and the stop condition only names extensionless files *outside* that directory, so no stop. They take the bash cap (400), as everything in that directory does; the conventions row says so. `koompi-remotedesktop-portal` is therefore allow-listed. If Python should have its own row, that is a one-line change to `cap_for` and the table.
- **`translations/` is matched at any depth.** No top-level `translations/` exists; the job can only mean `dots/.config/quickshell/koompi/translations/`. That skips `translations/tools/manage-translations.sh` (155 lines, under cap anyway).
- **35 rows, not ~55.** The audit's 42+11+2 counted every kind at a 400 threshold over a wider set. Of the 55 files over 400 in the same tree, 18 are Rust (`shell-services/*/src/*.rs`, no cap in the table), 1 is `dots/.local/share/koompi/libexec/update` (695-line bash, no extension, not in the walk the job defines), and the rest are html/css/svg/png/md/kvconfig/lock. Zig's cap is 600 so `audiod/src/engine.zig` 698 and `installer/src/main.zig` 931 are in; JS/Lua at 300 adds `app.js` 391, `layouts.js` 302, `general.lua` 371. The walk covers 813 files.
- **Out of the walk but over 400 and clearly code:** `dots/.local/share/koompi/libexec/update` (695, bash, owned by J11) and three Rust services (`network/src/service.rs` 1198, `mpris/src/service.rs` 898, `tray/src/watcher.rs` 683). Not added: the job fixes the walk and the table. Rithy's call whether J09 or a new row extends either.

## Acceptance

### 1. `tests/file-length-allow.txt`

```
audiod/src/engine.zig	698
docs/brainstorm/js/app.js	391
dots/.config/hypr/hyprland/general.lua	371
dots/.config/hypr/hyprland/keybinds.lua	447
dots/.config/hypr/hyprland/scripts/fuzzel-emoji.sh	1956
dots/.config/quickshell/koompi-quicklook/shell.qml	667
dots/.config/quickshell/koompi/modules/common/Appearance.qml	467
dots/.config/quickshell/koompi/modules/common/Config.qml	827
dots/.config/quickshell/koompi/modules/common/functions/fuzzysort.js	682
dots/.config/quickshell/koompi/modules/koompi/background/Background.qml	473
dots/.config/quickshell/koompi/modules/koompi/launchpad/LaunchpadContent.qml	575
dots/.config/quickshell/koompi/modules/koompi/lock/LockSurface.qml	734
dots/.config/quickshell/koompi/modules/koompi/onScreenKeyboard/layouts.js	302
dots/.config/quickshell/koompi/modules/koompi/regionSelector/RegionSelection.qml	554
dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/AiChat.qml	1389
dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/aiChat/AiMessage.qml	577
dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/aiChat/memory/MemoryBrowser.qml	525
dots/.config/quickshell/koompi/modules/koompi/sidebarRight/SidebarRightContent.qml	532
dots/.config/quickshell/koompi/modules/koompi/wallpaperSelector/WallpaperSelectorContent.qml	453
dots/.config/quickshell/koompi/modules/settings/AiConfig.qml	510
dots/.config/quickshell/koompi/modules/settings/BackgroundConfig.qml	683
dots/.config/quickshell/koompi/modules/settings/InterfaceConfig.qml	932
dots/.config/quickshell/koompi/scripts/colors/switchwall.sh	526
dots/.config/quickshell/koompi/services/LauncherSearch.qml	508
dots/.config/quickshell/koompi/services/MemoryService.qml	475
dots/.config/quickshell/koompi/services/ai/Conversation.qml	729
dots/.config/quickshell/koompi/services/ai/FeedbackService.qml	1094
dots/.config/quickshell/koompi/services/ai/ModelRegistry.qml	403
dots/.config/quickshell/koompi/services/ai/ToolRunner.qml	449
dots/.config/quickshell/koompi/welcome.qml	511
dots/.local/bin/koompi-quicklook	426
dots/.local/bin/koompi-remotedesktop-portal	526
installer/src/main.zig	931
sdata/dist-arch/koompi-branding/files/sddm/theme/Main.qml	437
sdata/install/setups.sh	710
```

### 2. Synthetic over-cap file

```
$ seq 401 | sed 's/^/\/\/ line /' > /tmp/x.qml; wc -l /tmp/x.qml
401 /tmp/x.qml
$ printf 'x.qml\n' > /tmp/j01-list.txt
$ FILE_LENGTH_ROOT=/tmp FILE_LENGTH_FILES=/tmp/j01-list.txt bash tests/test_file_length.sh; echo "rc=$?"
FAIL: x.qml is 401 lines, cap is 400; split it by concern (docs/conventions.md, File and function length)
rc=1
--- and at exactly 400 it passes
$ seq 400 | sed 's/^/\/\/ line /' > /tmp/x.qml
$ FILE_LENGTH_ROOT=/tmp FILE_LENGTH_FILES=/tmp/j01-list.txt bash tests/test_file_length.sh; echo "rc=$?"
ok: 1 files under cap, 0 allow-listed and not grown
rc=0
$ rm -f /tmp/x.qml /tmp/j01-list.txt; ls /tmp/x.qml
ls: cannot access '/tmp/x.qml': No such file or directory
```

### 3. Allow-listed file grows (scratch copy under `mktemp -d`, repo untouched)

```
$ rel=dots/.config/quickshell/koompi/modules/settings/BackgroundConfig.qml   # listed at 683
$ cp "$rel" "$scratch/$rel"; echo '// one more line' >> "$scratch/$rel"
$ FILE_LENGTH_ROOT="$scratch" FILE_LENGTH_FILES="$scratch/list.txt" bash tests/test_file_length.sh; echo "rc=$?"
FAIL: dots/.config/quickshell/koompi/modules/settings/BackgroundConfig.qml grew from 683 to 684 lines; an allow-listed file may only shrink (tests/file-length-allow.txt)
rc=1
--- unmodified copy passes
$ cp "$rel" "$scratch/$rel"
$ FILE_LENGTH_ROOT="$scratch" FILE_LENGTH_FILES="$scratch/list.txt" bash tests/test_file_length.sh; echo "rc=$?"
ok: 0 files under cap, 1 allow-listed and not grown
rc=0
$ rm -rf "$scratch"; git status --short
 M docs/conventions.md
?? tests/file-length-allow.txt
?? tests/test_file_length.sh
```

### 4. `./tests/run.sh` tail

Baseline at `d552876a` is 78 passed, 3 skipped, 0 failed (the job text's 57 is stale); with the new test:

```
  ok test_zig_build_abort.sh

79 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

`test_file_length.sh` alone:

```
ok: 778 files under cap, 35 allow-listed and not grown
```

## Gate

- `./tests/run.sh`: 79 passed, 3 skipped, 0 failed (above).
- `cli`: `zig build test` exit 0.
- `installer`: `zig build test` **fails before compiling anything** on this machine, identically on the main checkout: zig 0.16.0 has no `root_source_file` in `Build.ExecutableOptions` (`installer/build.zig:14`). Pre-existing, not in J01's files (`installer/` is J06's tree). The backlog's "installer 4/4" was measured with an older zig.
- shellcheck, the three `installer.yml:41-45` invocations: clean. `tests/test_file_length.sh` also shellcheck clean.
- Touched files under cap: `test_file_length.sh` 90 lines, `conventions.md` is Markdown (no cap).

## Commits

- aa3816d4 docs(conventions): set file and function length caps
- 4f9c9f1f test(length): ratchet source file length against an allow-list
