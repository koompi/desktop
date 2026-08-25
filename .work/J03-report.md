# J03 report — move the emoji table out of fuzzel-emoji.sh (AUDIT D2)

Branch `j03-emoji-data-file`, based on main `422c58e4`.
Files touched: `dots/.config/hypr/hyprland/scripts/fuzzel-emoji.sh` (1956 → 23 lines), `dots/.config/hypr/hyprland/scripts/fuzzel-emoji.txt` (new, 1928 lines), `tests/file-length-allow.txt` (the one row), this file.
No other file was changed.

## Blocker: do not merge until two files this job does not own are updated

The job brief lists one consumer of the script (the keybind). There is a second one it did not see: `dots/.config/quickshell/koompi/services/Emojis.qml` reads `fuzzel-emoji.sh` through a `FileView` (line 15) and slices everything after the literal `### DATA ###` (lines 16, 48-53) to feed the launcher's emoji search (`services/LauncherSearch.qml:369`). `tests/test_services_qml_bugs.sh:61` copies the script into its fixture and asserts that search works (check L2).

With the marker gone, both break. This branch alone:

```
$ ./tests/run.sh
78 passed, 3 skipped, 1 failed
failed: test_services_qml_bugs.sh

$ ./tests/test_services_qml_bugs.sh
FAIL L2 sloppy emoji search works on the loaded list  fuzzy=0 sloppy=0 list=0
  WARN qml: No data section found in emoji script file.
PROBE FAILED 1
```

Not fixed here because both files are outside this job's ownership; the brief says stop and report rather than edit. The patch below is the fix. I applied it, ran the suite, and reverted it before committing:

```
$ git apply /tmp/j03-followup.patch && ./tests/test_services_qml_bugs.sh
PASS L2 sloppy emoji search works on the loaded list  fuzzy=153 sloppy=73 list=1928
PROBE OK
$ ./tests/run.sh
79 passed, 3 skipped, 0 failed
```

The exact command that clears the block, from the repo root on this branch, after saving the patch to a file:

```
git apply j03-followup.patch && ./tests/test_services_qml_bugs.sh
```

```diff
--- a/dots/.config/quickshell/koompi/services/Emojis.qml
+++ b/dots/.config/quickshell/koompi/services/Emojis.qml
@@ -12,8 +12,7 @@
  */
 Singleton {
     id: root
-    property string emojiScriptPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-emoji.sh`
-	property string lineBeforeData: "### DATA ###"
+    property string emojiDataPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-emoji.txt`
     property bool sloppySearch: Config.options?.search.sloppy ?? false
     property real scoreThreshold: 0.2
     property list<var> list
@@ -45,19 +44,13 @@
     }
 
     function updateEmojis(fileContent) {
-        const lines = fileContent.split("\n")
-        const dataIndex = lines.indexOf(root.lineBeforeData)
-        if (dataIndex === -1) {
-            console.warn("No data section found in emoji script file.")
-            return
-        }
-        const emojis = lines.slice(dataIndex + 1).filter(line => line.trim() !== "")
-        root.list = emojis.map(line => line.trim())
+        root.list = fileContent.split("\n").map(line => line.trim()).filter(line => line !== "")
+        if (root.list.length === 0) console.warn(`No emoji entries in ${root.emojiDataPath}`)
     }
 
     FileView { 
         id: emojiFileView
-        path: Qt.resolvedUrl(root.emojiScriptPath)
+        path: Qt.resolvedUrl(root.emojiDataPath)
         onLoadedChanged: {
             const fileContent = emojiFileView.text()
             root.updateEmojis(fileContent)
--- a/tests/test_services_qml_bugs.sh
+++ b/tests/test_services_qml_bugs.sh
@@ -58,7 +58,7 @@
 for entry in "$SHELL_ROOT"/*; do
     ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
 done
-cp "$REPO_ROOT/dots/.config/hypr/hyprland/scripts/fuzzel-emoji.sh" "$WORK/xdg/config/hypr/hyprland/scripts/"
+cp "$REPO_ROOT/dots/.config/hypr/hyprland/scripts/fuzzel-emoji.txt" "$WORK/xdg/config/hypr/hyprland/scripts/"
 
 cat > "$WORK/bin/cliphist" <<'SH'
 #!/usr/bin/env bash
```

Until that lands, SUPER+Period (fuzzel path) works on this branch and the quickshell launcher's emoji search returns nothing.

## Do 1: data moved verbatim

Everything after `### DATA ###` (old line 28 onward, 1928 lines) is now `fuzzel-emoji.txt`, same directory. Byte-identical check against the pre-change script (`/tmp/fuzzel-emoji.sh.orig` is a copy taken before editing):

```
$ diff <(sed '1,/^### DATA ###$/d' /tmp/fuzzel-emoji.sh.orig) fuzzel-emoji.txt && echo "diff exit 0"
diff exit 0
$ head -2 fuzzel-emoji.txt; tail -1 fuzzel-emoji.txt
😀 grinning face face smile happy joy :D grin
😃 grinning face with big eyes face happy joy haha :D :) smile funny
🪎 treasure chest gold loot pirate
```

The old script ended with a newline (checked with `od -c`), so the data file does too.

## Do 2: the script

Line 9 (now line 6) reads the data file instead of `$0`; the trick comment, the `shellcheck disable=SC2317,SC1089` line and the marker are gone. The bare `exit` before the marker existed only to stop bash from reaching the data, so it went with it.

```
$ git diff dots/.config/hypr/hyprland/scripts/fuzzel-emoji.sh | head -20
@@ -1,12 +1,9 @@
 #!/bin/bash
-# Everything after '### DATA ###' is emoji data read back out of $0 by sed, never
-# executed. shellcheck parses it as code and chokes on faces like ":)".
-# shellcheck disable=SC2317,SC1089
 set -euo pipefail

 MODE="${1:-type}"

-emoji="$(sed '1,/^### DATA ###$/d' "$0" | fuzzel --match-mode fzf --dmenu | cut -d ' ' -f 1 | tr -d '\n')"
+emoji="$(fuzzel --match-mode fzf --dmenu < "$(dirname "$0")/fuzzel-emoji.txt" | cut -d ' ' -f 1 | tr -d '\n')"
@@ -24,1933 +21,3 @@ case "$MODE" in
         exit 1
         ;;
 esac
-exit
-### DATA ###
```

## Do 3: the installer picks the new file up without registration

`sdata/install/files.sh` never lists individual files under `dots/`; it copies the tree:

- line 283, `run cp -a "$REPO_ROOT/dots/." "$stage/"`, stages the whole of `dots/`.
- lines 309-310, `sync_tree "$stage/.config" "$XDG_CONFIG_HOME" "${excludes[@]}"`, rsyncs `.config/` into `~/.config`; `sync_tree` (line 243) is `rsync -a`, and the excludes (lines 293-296) are `.git`, `.gitignore`, `.claude`, `zig-out`, `.zig-cache`, `__pycache__`, `*.pyc`, `.qmlls.ini`, none of which match a `.txt`.
- line 213, `backup_existing` walks `find . -type f -o -type l` over `dots/`, so the new file is also covered by the pre-install backup.

A sibling file in `hyprland/scripts/` therefore lands in `~/.config/hypr/hyprland/scripts/` next to the script, which is where `$(dirname "$0")` looks.

## Do 4: shellcheck

```
$ shellcheck fuzzel-emoji.sh && echo "shellcheck exit 0"
shellcheck exit 0
```

## Acceptance

### 1. Line counts

```
$ wc -l fuzzel-emoji.sh fuzzel-emoji.txt
   23 fuzzel-emoji.sh
 1928 fuzzel-emoji.txt
```

### 2. diff

Empty, exit 0 (Do 1 above).

### 3. shellcheck

Empty, exit 0 (Do 4 above).

### 4. bash -n and a run of the script

```
$ bash -n fuzzel-emoji.sh && echo "bash -n exit 0"
bash -n exit 0
$ sed -n '$=' fuzzel-emoji.txt
1928
```

`fuzzel` and `wl-copy` are installed and `WAYLAND_DISPLAY=wayland-1` is set, but Rithy is using this desktop, so I did not pop a dmenu on it or overwrite the clipboard. Instead the real script ran with a `fuzzel` stand-in on `PATH` that reports how many candidates arrived on stdin and echoes the first, and a `wl-copy` stand-in that prints its argument:

```
$ PATH="$SHIM:$PATH" fuzzel-emoji.sh copy; echo "script exit $?"
fuzzel-shim: 1928 candidates, args: --match-mode fzf --dmenu
wl-copy-shim: [😀]
script exit 0
$ PATH="$SHIM:$PATH" fuzzel-emoji.sh bogus; echo "script exit $?"
fuzzel-shim: 1928 candidates, args: --match-mode fzf --dmenu
Usage: dots/.config/hypr/hyprland/scripts/fuzzel-emoji.sh [type|copy|both]
script exit 1
```

All 1928 lines reach fuzzel, the first field of the chosen line reaches wl-copy, and the usage path still exits 1. The interactive fuzzel UI itself was not exercised.

## File-length ratchet

`fuzzel-emoji.sh` is 23 lines, so its row left `tests/file-length-allow.txt` (35 → 34 rows). `fuzzel-emoji.txt` is not a kind the test measures.

```
$ grep -c fuzzel-emoji tests/file-length-allow.txt
0
$ ./tests/test_file_length.sh; echo "exit $?"
ok: 779 files under cap, 34 allow-listed and not grown
exit 0
```

## Stop conditions

`dots/.config/hypr/hyprland/keybinds.lua:119` still calls `hyprScripts .. "/fuzzel-emoji.sh copy"`; the path and argument are unchanged, so the listed stop condition did not fire. The unlisted consumer (`Emojis.qml`) is the blocker at the top of this report.

## Test suite

Baseline on main `422c58e4`: 79 passed, 3 skipped, 0 failed.
This branch as committed: 78 passed, 3 skipped, 1 failed (`test_services_qml_bugs.sh`, L2).
This branch plus the patch above: 79 passed, 3 skipped, 0 failed.

## Round 2: the follow-up patch, now owned and landed

Lead addendum: `services/Emojis.qml` and `tests/test_services_qml_bugs.sh` are mine for this fix (J18 merged). The patch from the blocker section above applied unchanged as `[33m40404bc3[m fix(emojis): read the data file, not the script`. The blocker at the top of this report is cleared.

### qmllint on Emojis.qml, before and after

Same invocation as `tests/test_services_qml_bugs.sh:34-38`: `/usr/lib/qt6/bin/qmllint -I "$LINT" -I /usr/lib/qt6/qml services/Emojis.qml`, where `$LINT/qs` is a symlink to the shell root.

Before (main + the D2 split, Emojis.qml untouched): exit 0, 9 warnings.
After the fix: exit 0, 9 warnings.

The nine are the same nine, shifted by one line: four `[import]` warnings on `qs.modules.common` and `qs.modules.common.functions` (the lint fixture cannot resolve the `qs` module tree; the test tolerates these and only fails on `^Error`), and five `[unqualified]` on `Directories`, `Config`, `Fuzzy` (x2) and `Levendist`, which are the singletons those imports would have provided. The fix adds no warning and removes none. The only changed warning line:

```
-Emojis.qml:15:41: Unqualified access [unqualified]
-    property string emojiScriptPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-emoji.sh`
+Emojis.qml:15:39: Unqualified access [unqualified]
+    property string emojiDataPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-emoji.txt`
```

### tests/test_services_qml_bugs.sh

```
ok   source: guarded lines present in MemoryService, Notifications, LauncherSearch, Ai, Audio, MprisController, LatexRenderer
ok   qmllint: 14 touched services parse without errors
PASS L2 sloppy emoji search works on the loaded list  fuzzy=153 sloppy=73 list=1928
PROBE OK
ok   services: cliphist queue, checkupdates exit codes, xkb variants, wallpaper dir validation, easyeffects readback, emoji sloppy search, latex argv and exit code
```

### ./tests/run.sh

```
79 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

Matches the main baseline. Branch is merge-ready.
