# J04 — split InterfaceConfig.qml into one file per section

## Files you own
- `dots/.config/quickshell/koompi/modules/settings/InterfaceConfig.qml`
- `dots/.config/quickshell/koompi/modules/settings/interface/**` (new directory)

## Do
1. (D4) Read `InterfaceConfig.qml` end to end and `modules/common/widgets/ContentSection.qml`. Sections and line ranges: Cheat sheet 10-101, Dock 102-143, Lock screen 144-252, Notifications 253-294, Overlay General 295-316, Overlay Crosshair 317-355, Overlay Floating Image 356-370, Region selector 371-464, Sidebars 465-693, OSD 694-710, Overview 711-807, Wallpaper selector 808-821, Fonts 822-930.
2. (D4) Create `modules/settings/interface/` with one file per section, root element `ContentSection`, names: `CheatSheetSection.qml`, `DockSection.qml`, `LockScreenSection.qml`, `NotificationsSection.qml`, `OverlaySection.qml` (the three overlay sections merged, they are 75 lines together), `RegionSelectorSection.qml`, `SidebarsSection.qml`, `OsdSection.qml`, `OverviewSection.qml`, `WallpaperSelectorSection.qml`, `FontsSection.qml`. Move code verbatim; only indentation changes.
3. (D4) Rewrite `InterfaceConfig.qml` as imports + `ContentPage { forceWidth: true; CheatSheetSection {} ... }` in the original order. Keep the filename: `services/SettingsPages.qml:38` loads it by path.
4. Match how sibling module directories are imported (look at how `qs.modules.common.widgets` is resolved, and whether a `qmldir` is needed in new directories elsewhere in the tree).
5. `qmllint` every new file (it catches unresolved ids), then run the live check in Acceptance 3.

## Acceptance
1. `wc -l` of `InterfaceConfig.qml` (expect ≤ 40) and each section file (largest, Sidebars, ≈ 230).
2. `git diff --stat` and a `diff` of the concatenated section bodies against the original ranges showing only whitespace changes (`diff -w`).
3. Live: deploy the changed files to `~/.config/quickshell/koompi/modules/settings/` (copy), run `koompi settings`, open the Interface page, and paste `qs log -c koompi | grep -i 'interface\|Section' | tail` showing no errors, plus a screenshot path of the page rendered with all 13 sections visible on scroll.
4. `./tests/run.sh` tail, unchanged count.

## Out of scope
- Any other `*Config.qml` page.
- Changing option keys, labels, or behaviour.

## Stop conditions
- If a section turns out to reference an id outside itself (the map found none), stop and report the id rather than hoisting state.
- If `qs` refuses to resolve the new directory without a change outside your files, report the exact file needed.
