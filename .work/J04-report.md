# J04 report — split InterfaceConfig.qml into one file per section (AUDIT D4)

Branch `j04-split-interface-config`, based on main `7cabe951`.
Files touched: `modules/settings/InterfaceConfig.qml` (932 → 19 lines), 11 new section files plus a `qmldir` in `modules/settings/interface/`, and the one `InterfaceConfig.qml` row in `tests/file-length-allow.txt`.
No other file was changed.

## Two things the brief did not anticipate

1. **`interface/qmldir` is required.**
   `import qs.modules.settings.interface` failed live: `WARN scene: @modules/settings/InterfaceConfig.qml[3:1]: module "qs.modules.settings.interface" is not installed`.
   Quickshell resolves `qs.*` by scanning imports transitively from the entry file and serving a generated qmldir for every directory it reached.
   `InterfaceConfig.qml` is loaded by path (`services/SettingsPages.qml:38`), so its imports are never scanned and the new directory is never registered; the log shows the fallback lookup `modules/settings/interface/qmldir contains ""` hitting the real filesystem.
   A relative `import "interface"` fails the same way (`FontsSection is not a type`: no directory listing through the `qs:` interceptor).
   The fix is a plain Qt `qmldir` in the new directory, which is inside the files this job owns, so the stop condition ("a change outside your files") did not trigger.
   It is the only qmldir in the tree; a comment in it says why.
   Any section added later must be listed there.
2. **`OverlaySection.qml` root is a `ColumnLayout`, not a `ContentSection`.**
   The brief merges three `ContentSection`s into one file; a QML file has one root, so the three sit verbatim inside `ColumnLayout { Layout.fillWidth: true; spacing: 30 }`, the same spacing `ContentPage` puts between sections.
   Rendered output is identical (screenshot below).
   Every other section file has root `ContentSection`.

Neither stop condition fired: no section references an id outside itself (`editorButton` and `mouseArea` are each used only inside their own section).

## Acceptance 1: line counts

```
$ wc -l InterfaceConfig.qml interface/*.qml
   19 InterfaceConfig.qml
   98 interface/CheatSheetSection.qml
   47 interface/DockSection.qml
  115 interface/FontsSection.qml
  114 interface/LockScreenSection.qml
   47 interface/NotificationsSection.qml
   22 interface/OsdSection.qml
   86 interface/OverlaySection.qml
  102 interface/OverviewSection.qml
   99 interface/RegionSelectorSection.qml
  234 interface/SidebarsSection.qml
   19 interface/WallpaperSelectorSection.qml
```

All under 400; the allow-list row for `InterfaceConfig.qml` (932) is removed and `tests/test_file_length.sh` reports `ok: 780 files under cap, 33 allow-listed and not grown`.

## Acceptance 2: diff stat and verbatim check

```
$ git diff --cached --stat
 .../koompi/modules/settings/InterfaceConfig.qml    | 937 +--------------------
 .../settings/interface/CheatSheetSection.qml       |  98 +++
 .../modules/settings/interface/DockSection.qml     |  47 ++
 .../modules/settings/interface/FontsSection.qml    | 115 +++
 .../settings/interface/LockScreenSection.qml       | 114 +++
 .../settings/interface/NotificationsSection.qml    |  47 ++
 .../modules/settings/interface/OsdSection.qml      |  22 +
 .../modules/settings/interface/OverlaySection.qml  |  86 ++
 .../modules/settings/interface/OverviewSection.qml | 102 +++
 .../settings/interface/RegionSelectorSection.qml   |  99 +++
 .../modules/settings/interface/SidebarsSection.qml | 234 +++++
 .../interface/WallpaperSelectorSection.qml         |  19 +
 .../koompi/modules/settings/interface/qmldir       |  15 +
 tests/file-length-allow.txt                        |   1 -
 14 files changed, 1010 insertions(+), 926 deletions(-)
```

Original ranges 10-101, 102-142, 144-251, 253-293, 295-369, 371-463, 465-692, 694-709, 711-806, 808-820, 822-930 concatenated, against the eleven section files with their six import/blank header lines stripped, in the same order:

```
$ diff -w /tmp/j04-orig-bodies.txt /tmp/j04-new-bodies.txt
282a283,286
> ColumnLayout {
>     Layout.fillWidth: true
>     spacing: 30
>
357a362
> }
```

The only non-whitespace difference is the Overlay wrapper described above.

### qmllint

`/usr/bin/qmllint` is the Qt5 one (`qmllint 1.0`, syntax only; it passes a file with an unknown type).
`/usr/lib/qt6/bin/qmllint` 6.11.2 was run against a temp copy of the shell tree with a generated qmldir per directory so `qs.*` resolves; it flags an injected `nosuchid.foo` as `[unqualified]` and an injected `NoSuchWidget {}` as `was not found`, so it is a real check.
Result for `InterfaceConfig.qml` and all 11 section files: exit 0, zero `[unqualified]`, zero `was not found`.
The warning set (locations stripped, sorted) is byte-identical to the original file's: 117 rows, all `[missing-property]` on `Config.options.*` (JsonObject is dynamic) plus one pre-existing `Quick.layout-positioning` at `SidebarsSection.qml:163` (was line 621).

## Acceptance 3: live

Backup of the overwritten original: `/home/userx/.tmp/j04-backup-mk7vU0/InterfaceConfig.qml` (the deployed copy was byte-identical to main; `interface/` did not exist).
Deployed by `cp` into `~/.config/quickshell/koompi/modules/settings/`; `diff -rq` against the worktree shows the two trees equal for these files.

The settings app is its own instance (`koompi settings` → `dots/.local/bin/koompi-settings` → `exec qs -p ~/.config/quickshell/koompi/settings.qml`); the main shell does not load `modules/settings` and was not touched.
No process was killed by name: `koompi settings <page>` re-launches through `qs kill -p`.

`koompi settings interface` at 14:55:03, window `org.quickshell "KOOMPI Settings"` focused, Interface page rendered (Cheat sheet, Dock, Lock screen visible before Rithy's Telegram window covered it):

```
$ qs log -p ~/.config/quickshell/koompi/settings.qml | grep -v propertyCache | tail -6
  INFO: Launching config: "/home/userx/.config/quickshell/koompi/settings.qml"
  INFO: Shell ID: "d814ccec1fe42d284bf6fd29bb5d0c82" Path ID "d814ccec1fe42d284bf6fd29bb5d0c82"
  INFO: Saving logs to "/run/user/1000/quickshell/by-id/hjevrbfbkt/log.qslog"
 DEBUG qml: [Translation] Language changed to en_US
  INFO: Configuration Loaded
  WARN scene: QML MouseArea at @modules/settings/interface/SidebarsSection.qml[161:17]: Detected anchors on an item that is managed by a layout. This is undefined behavior; use Layout.alignment instead.

$ qs log -c koompi | grep -i 'interface\|Section' | tail
(no output: the main shell never loads this page)
```

The one WARN is pre-existing (original line 621, flagged by qmllint on the original file too).

**Screenshot: `/home/userx/.tmp/j04-shots/interface-all-sections.png`** (1274×3995; copy at `/tmp/j04-shots/`).
Rithy was working in Telegram and Slides on top of the settings window and closed it within a minute, and scrolling it with ydotool would have moved their pointer and focus, so the full-page capture was taken without the desktop: the same `qs` binary, same deployed `~/.config/quickshell/koompi` files (symlinked into a temp root with a 30-line harness that loads `modules/settings/InterfaceConfig.qml`, sizes the window to `contentHeight`, and `grabToImage`s the page), under `cage` on the wlroots headless backend, so nothing appeared on screen.
Harness log: `Configuration Loaded`, `contentHeight 3995`, the same single SidebarsSection WARN, no errors.
All 13 section headings are in the image: Cheat sheet, Dock, Lock screen, Notifications, Overlay: General, Overlay: Crosshair, Overlay: Floating Image, Region selector, Sidebars, On-screen display, Overview, Wallpaper selector, Fonts.
`QT_QPA_PLATFORM=offscreen` was tried first and does not work (`No PanelWindow backend loaded`).

## Acceptance 4: test suite

```
$ ./tests/run.sh | tail -3
79 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

Same as the main baseline.
