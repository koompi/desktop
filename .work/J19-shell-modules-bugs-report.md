# J19 report: Quickshell modules bugs

Branch `j19-shell-modules-bugs`, 17 commits on top of `928f1b01`, one per finding (two per tightly-coupled pair).
Every file touched is in the contract's list; nothing under `services/` (Weather.qml was read, not changed), nothing in `BarContent.qml`, `InterfaceConfig.qml`, `FeedbackService.qml`, `AiChat.qml`.

Verdicts: 16 confirmed and fixed (H8 in a sharper form than written), 4 not a bug (M17, M18, L16, and the "unnotified push" halves of H8 and L17).
The Stop conditions held: no process killed, `~/.config/koompi/config.json` and the live shell (`~/.config/quickshell/koompi` is a copy, not a link) untouched, no sudo, no installs, no lock, no hypridle or keep-awake change.

## Tooling used for every QML check

- `/usr/lib/qt6/bin/qmllint` 6.11.2 (`/usr/bin/qmllint` is the Qt 5 one and analyses nothing).
  The shell's `qs.*` modules are not resolvable outside Quickshell, so `[import]`, `[unqualified]` and `[unused-imports]` are disabled and every touched file is diffed against its pre-change output (`.work/tmp/lint-before/` vs `lint-after/`).
  Result: no new warning on any file.
  The only differences are line-number shifts, `CircleSelectionDetails.qml` losing its three `missing-property` warnings, and the same `signal-handler-parameters` note on the two new `onExited: (exitCode, exitStatus)` handlers that the tree's existing handlers (GameMode, PlayerControl) already carry.
- `qs -p <file>` with Quickshell 0.2.1 for the runtime facts. The harnesses are kept in `.work/J19-checks/`.
- `node .work/J19-checks/checks.js` for the pure-JS findings (exit 0, 27 checks).

### The fact that decides three verdicts: list mutation does notify

The audit's H8, M18 and L17 rest on "`list.push()` on a QML list property does not notify and does not persist". On this Qt it does. `.work/J19-checks/listpush.qml` and `repeater.qml`:

```
$ qs -p .work/J19-checks/listpush.qml
a changed -> ["x"]                          # list<string>.push
inc changed -> true                         # a binding on a.includes("x") re-evaluated
b changed -> [{"t":1}]                      # list<var>.push
b changed -> []                             # list<var>.splice
b changed -> [{"t":9}]                      # b[0].t = 9 (element write)
after c.push: len 1                         # property var: no "c changed" - a plain JS array does NOT notify
d changed -> 1                              # list<point>.push
$ qs -p .work/J19-checks/repeater.qml       # JsonAdapter { property list<var> toggles }, mutated through a local const
adapterUpdated -> [{"size":2,"type":"y"}]   # after splice(0, 1)
adapterUpdated -> [{"size":1,"type":"y"}]   # after list[0].size = 3 - list[0].size
```

A sequence obtained from a typed list property is a reference; writes go through the property setter, which emits the change signal, and a JsonAdapter's `adapterUpdated` follows.
Only `property var` arrays are copies. None of the pushes the audit named are on `var` properties.
(M6 in the audit, owned by another job, claims the same class of bug for timer laps and tray pins; whoever holds it should check the property types before fixing.)

## H8 overlay pinning - confirmed, sharper than written

`StyledOverlayWidget.qml:90` `property bool open: Persistent.states.overlay.open` binds a bool to a `list<string>`; a list reference coerces to `true` whatever it holds, so the `open` gate on `actuallyPinned`/`actuallyClickable` was constant.
The pushes in `OverlayContext.pin`, `registerClickableWidget` and `OverlayTaskbar` notify (above), so that half is not a bug and those files are unchanged.

What actually fails: `OverlayContent` instantiates one widget per entry of `overlay.open` through a Repeater. Closing removes the entry; the Repeater releases the delegate, and a released delegate's bindings never fire again, so `open` cannot flip to false before destruction, not even with the audit's `includes()` binding. Nothing unregistered, so a closed pinned widget stayed in `pinnedWidgetIdentifiers` (keeping the overlay window loaded, `hasPinnedWidgets` true) and its dead `contentItem` stayed in `clickableWidgets` (keyboard focus `OnDemand`, a Region on a destroyed item).

Changed: `open` is `readonly` and asks `includes(root.identifier)`; `Component.onDestruction` withdraws both registrations. `Persistent.qml` needed no change.

Check, `.work/J19-checks/h8.qml`, two Instantiators over the same list - "before" is the shipped gate, "after" the fix:

```
$ qs -p .work/J19-checks/h8.qml
pinned while both open  before: ["crosshair","notes"]  after: ["crosshair","notes"]
closed crosshair        before: ["crosshair","notes"]  after: ["notes"]
empty list<string> as a bool gate reads: true
```

## M9 calendar misspelled property - confirmed

`CalendarView.qml:82` passed `root.locale.firstdayOfWeek` (undefined) so DateUtils used its Monday default. Changed to `firstDayOfWeek`.

```
ok   M9 firstdayOfWeek (undefined) lands on: got 11     # Wed 7 Jan 2026, Sunday-first locale: Sunday of the *next* week
ok   M9 firstDayOfWeek = 0 lands on Saturday: got 10
ok   M9 CalendarView no longer reads firstdayOfWeek: got false
```

## L1 month-length helpers - confirmed

`getNextMonthDays(7)` returned 30 (August has 31), `getPrevMonthDays(8)` returned 30 (July has 31); every other month happened to be right. Both now call `getMonthDays` for the actual neighbour, with the year rolled at December/January.

```
ok   L1 getNextMonthDays(7, 2026) (August): got 31
ok   L1 getPrevMonthDays(8, 2026) (July): got 31
ok   L1 getNextMonthDays(12, 2027) (Jan 2028): got 31
ok   L1 getPrevMonthDays(1, 2028) (Dec 2027): got 31
ok   L1 getNextMonthDays(1, 2028) (leap Feb): got 29
ok   L1 all twelve months of 2026 agree with Date: got true
```

(`checks.js` loads `calendar_layout.js` itself through `vm`, so this runs the shipped file.)

## M10 media duplicate detection - confirmed

No absolute value and `A && B || C` precedence: any player behind another by more than two seconds matched `-diff <= 2` on its own. Changed to `Math.abs` on both differences with the title clause parenthesised; the OR structure (same title, or same position and length) is kept because a title match is not required for the position test to mean something, and players with no title metadata would otherwise never dedupe.

```
ok   M10 before: A behind B counts as duplicate: got true      # A at 10/200, B at 120/300
ok   M10 after: A behind B is not a duplicate: got false
ok   M10 after: B ahead of A is not a duplicate: got false
ok   M10 after: same title still groups: got true
ok   M10 after: same position and length still groups: got true
```

Observed and left as is: two idle players both at position 0 / length 0 still group, exactly as before this change.

## M11 cover-art curl exit ignored - confirmed

`onExited` set `downloaded = true` regardless; the MPRIS URL was pasted raw into `bash -c`, and `artFilePath` was unquoted in the `[ -f ]` test. Two things made the exit code hollow even once read: without `-f`, curl writes a 404 page to the cache file with exit 0, and the `[ -f ]` guard then serves it forever.

Changed: `downloaded = exitCode === 0` (failure logged), `-f`, `shellSingleQuoteEscape(targetFile)`, and quotes around the path.

```
$ python3 -m http.server 18745 &  # in an empty dir
$ curl -sSL  -o missing.bin http://127.0.0.1:18745/nope; echo rc=$?  -> rc=0 size=460   (the 404 page, saved)
$ curl -sSLf -o missing2.bin http://127.0.0.1:18745/nope           -> rc=22 exists=no
$ url="http://127.0.0.1:1/it's.png"
old form: bash: -c: line 1: unexpected EOF while looking for matching `''   rc=2
new form: curl: (7) Failed to connect to 127.0.0.1:1 ...                    rc=7
```

## M12 weather widget throws until first fetch - confirmed

`Weather.data` starts as `temp: 0`; `(0).substring` throws and `??` cannot catch a throw. The service is left with its mixed types (the bar's WeatherPopup only concatenates them); the widget guards on `typeof === "string"`. Line 48's `getWeatherIcon(wCode)` was checked too: `String(0)` misses the map and the `?? "cloud"` applies, no throw.

```
ok   M12 old expression on temp: 0 throws: got "TypeError"
ok   M12 new expression on temp: 0: got "--°"
ok   M12 new expression on temp: '25°C': got "25°"
ok   M12 new expression on undefined data: got "--°"
```

## M15 content transparency ignores its master switch - confirmed

`contentTransparency` is the `transparentize` amount for every layer colour (0 = opaque, same convention as `backgroundTransparency`, which already returned 0 when `enable` is off). Wrapped in the same `enable ? … : 0`. Check: qmllint diff clean; the expression is the one already used one line above.

## M17 OSD pinned to startup screen - not a bug

Two claims, both wrong for this tree:

1. "`focusedScreen` is a one-shot find" - it is a property binding on `Hyprland.focusedMonitor?.name`, which is a notifying property, so it re-evaluates on every focus change and the `onFocusedScreenChanged` handler does fire.
2. The real question is what happens at creation, since the Loader builds a fresh `PanelWindow` each time the OSD opens and `screen` is never set. Quickshell source (`src/wayland/wlr_layershell.cpp:129-131`, `src/wayland/wlr_layershell/surface.cpp`): `compositorPicksScreen` defaults to `true` and only becomes `false` when `screen` is set to a non-null value; with it true the layer surface is created with a null `wl_output`, and Hyprland places a layer surface with no output on the focused monitor.

So an OSD opens on the focused monitor by compositor default and moves with focus while open. `BrightnessIndicator.qml:9-10` is the same reactive binding; not stale. Cannot be exercised here (one monitor: `eDP-1`), but the mechanism the audit describes does not exist. No change.

## M18 android quick-toggle edit mutates the Config list - not a bug

`toggles` is `property list<var>` on a `JsonObject` (`Config.qml:692`); `splice`, `push` and `toggleList[index].size = …` through a local reference all write through, emit the change (so `AndroidQuickPanel.toggles` re-evaluates) and fire `adapterUpdated`, which `Config.qml:141` turns into `writeAdapter()`. Evidence is the `repeater.qml` run above, which uses exactly that shape (JsonAdapter, `list<var>` of objects, mutation through `const list = adapter.toggles`). No change.

## M19 background geometry from unchecked magick output - confirmed

Empty output on failure gave `Number("") = 0`, `Math.max(w/0, h/0) = NaN` into `minSuitableScale`. Also found while reproducing: on an animated image `identify -format "%w %h"` prints one pair per frame with no separator, so the height came out as e.g. `480320`.

Changed: the size is only applied when both numbers are finite and positive (failure logged, previous size kept); the command asks for frame `[0]`.

```
$ magick -size 640x480 xc:red -size 320x240 xc:blue anim.gif
identify anim.gif     -> '640 480320 240'
identify anim.gif[0]  -> '640 480'
identify missing.png  -> identify: unable to open image ... (rc=1, empty stdout)
ok   M19 old parse of empty output gives: got "NaN"
ok   M19 new parse of empty output: got null
ok   M19 new parse of 'identify: unable to open image': got null
ok   M19 new parse of '3840 2160': got [3840,2160]
```

## L6 reload popup shows previous failure text - confirmed

`onReloadCompleted` cleared `failed` but not `errorString`; body Text is `visible: errorString != ""`. Added `root.errorString = ""`. Check: qmllint diff clean (the file is tab-indented; the edit matched that).

## L8 self-binding / self-comparison - confirmed, one nuance

- `GameMode.qml:10` `toggled: toggled`: verified with qs that on Qt 6.11 it leaves the default and prints no binding-loop warning, so it was dead rather than noisy. Removed.
- `NotesContent.qml:266` `if (root.content !== root.content)` was always false, so the cursor restore never ran, and the unconditional assignment above it reset the cursor on every reload even when the file had not changed. Now compares the loaded text with the current text and restores the selection only when it differs.

```
$ qs -p .work/J19-checks/gamemode.qml
self-bound toggled = false | plain default = false
after assignment, self-bound toggled = true
```

## L9 `visionParagraphs == []` - confirmed

Reference comparison, always false, so the token-ready retry never ran. Changed to `.length === 0`.

```
ok   L9 [] == [] is: got false
ok   L9 [].length === 0 is: got true
```

## L10 vertical bar hides by the horizontal bar height - confirmed

Right-side state slid by `Appearance.sizes.barHeight` while the bar is `verticalBarWidth` wide (`baseVerticalBarWidth: 46`, plus gaps when `cornerStyle === 1`); the left side already used the width. Changed to `verticalBarWidth`. Check: qmllint diff clean; it is the identical expression to line 107.

## L11 (modules part) - confirmed as dead code, no behavioural effect

- `GammaIndicator.qml:13`: `gamma / 100 ?? 0.5` parses as `(gamma / 100) ?? 0.5`; `Hyprsunset.gamma` is `property int` (never null) so the fallback could never apply either way. Dropped the dead operand rather than parenthesising a fallback for a value that cannot be null.
- `ScreenCorners.qml:103,114`: `0.02 || 0.2` is always `0.02`. Dropped `|| 0.2` at both sites. The scroll-down path's missing `Math.max(0, …)` the audit mentions for `Audio.qml` was not verified as reaching PipeWire with a negative value and is left alone.

## L12 (modules part) - confirmed

- `FpsLimiterContent.qml`: `startDetached()` then Success unconditionally. Now runs the process and takes Success/Error from the exit code; the `pkill` is `|| true` so no running game is not a failure. The field is still cleared after apply, as the existing Error path does.
- `ImageDownloaderProcess.qml`: no exit handling, so a failed download left `FloatingImage` blank silently. Added `-f` (a 404 page was otherwise saved and `file`d as the image), `onExited` logging a non-zero exit, and a log line when `file(1)` returns something with no size in it. `FloatingImage.qml` needed no change.

```
new shape, writable dir, no mangohud: rc=0 conf=fps_limit=60
new shape, second run (sed path):     rc=0 conf=fps_limit=60
new shape, missing dir:               rc=1   (bash: .../MangoHud.conf: No such file or directory)
```

## L14 "put back" not restored until next recall - confirmed

`restoreMemory`/`restoreAll` only shrank `droppedMemoryIds`; `enforce()` only ever removed. `enforce` now rebuilds `Ai.recalledMemories` as `MemoryService.lastRecall` minus the drops in both directions, and the restore functions call it. One guard was needed that the audit's fix would have missed: `Requester.qml:365` empties the block before each recall, and a restore in that window must not resurrect last turn's memories into a request that then times out. `_engineCleared` tracks that state from `onRecalledMemoriesChanged`.

Check, `.work/J19-checks/l14.qml`: the singleton's logic verbatim over stubs for `Ai`/`MemoryService`, driven the way Requester drives them.

```
$ qs -p .work/J19-checks/l14.qml
ok   recall in play: "- likes tea - uses zsh"
ok   drop 1 leaves: "- uses zsh"
ok   restore 1 brings it back at once: "- likes tea - uses zsh"
ok   drop both empties the block: ""
ok   restore all from an empty block: "- likes tea - uses zsh"
ok   restore while the engine has cleared stays empty: ""
ok   next recall lands intact: "- on holiday"
all passed
```

The wiring to the real `Ai`/`MemoryService` singletons is verified by qmllint only; the shell was not restarted.

## L15 unguarded overview dereferences - confirmed

`windowData` is `windowByAddress[address]`, undefined for a toplevel `HyprlandData` has not listed yet; every other read in both files uses `?.`. `OverviewWindow.qml:61` and `OverviewWidget.qml:273` now do too. Check: qmllint diff clean.

## L16 Behavior on wrong item - not a bug

`Resource.qml:72-74`: the `Behavior on x` sits inside the `RowLayout { id: resourceRowLayout }` block (lines 17-75; the RowLayout's closing brace is line 75, the Behavior is at 8-space indent between the `Item` child and that brace). It animates `resourceRowLayout.x`, which is the property `x: shown ? 0 : -resourceRowLayout.width` drives. No change.

## L17 region selection - half confirmed

- `RegionSelection.qml:378` `points.push` on `list<point>`: notifies (see `d changed -> 1` above). Not a bug; unchanged.
- `CircleSelectionDetails.qml:14-17` `updatePoints()`: reads `root.dragging`, `root.mouseX`, `root.mouseY`, none declared (qmllint `missing-property` ×3), and nothing in the tree calls it. Deleted.

```
$ /usr/lib/qt6/bin/qmllint ... CircleSelectionDetails.qml   # before: 3 warnings (dragging, mouseX, mouseY)
$ /usr/lib/qt6/bin/qmllint ... CircleSelectionDetails.qml   # after: none
```

## Test baseline

Backlog baseline: `56 passed, 0 failed` at `bf678012`. There are 59 tests now. The one failure is `test_packaged_tools.sh`, which pins `koompi-shell/PKGBUILD`'s `_tools` array to `dots/.local/bin`; J15 added `dots/.local/bin/koompi-lid` on this branch's base without listing it. Neither file is in this job's contract and this branch's 17 commits touch nothing under `sdata/` or `dots/.local/bin` (`git diff --stat 928f1b01..HEAD -- sdata dots/.local/bin` is empty), so the failure is pre-existing and reported, not fixed.

```
$ ./tests/run.sh
...
==> test_packaged_tools.sh
FAIL: dots/.local/bin/koompi-lid is neither in _tools nor in _tools_excluded in koompi-shell/PKGBUILD
  xx test_packaged_tools.sh
...
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh

58 passed, 1 failed
failed: test_packaged_tools.sh
```
