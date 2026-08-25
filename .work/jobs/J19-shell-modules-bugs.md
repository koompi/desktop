# J19 — Quickshell modules bugs

Findings from `.work/BUG-AUDIT.md` (opencode audit 2026-08-25; the lead verified H1 true and C1 false). Read each finding's full text there before starting.

## Findings you own
- H8 overlay pinning built on list-to-bool coercion and non-notifying mutations
- M9 calendar misspelled property; L1 month-length helpers wrong across July/August
- M10 media duplicate detection; M11 cover-art curl exit ignored
- M12 weather widget throws until first fetch
- M15 content transparency ignores its master switch
- M17 OSD pinned to startup screen
- M18 android quick-toggle edit mutates Config list in place
- M19 background geometry from unchecked magick output
- L6 reload popup shows previous failure text
- L8 self-binding / self-comparison (GameMode, NotesContent)
- L9 `visionParagraphs == []`
- L10 vertical bar hides by the horizontal bar height
- L11 (modules part) GammaIndicator precedence, ScreenCorners `||`
- L12 (modules part) FpsLimiter, ImageDownloaderProcess/FloatingImage
- L14 "put back" memory not restored until next recall
- L15 unguarded overview dereferences; L16 Behavior on wrong item; L17 region selection pushes + dead helper

## Files you own
- under `dots/.config/quickshell/koompi/modules/`: `koompi/overlay/StyledOverlayWidget.qml`, `overlay/OverlayContext.qml`, `overlay/OverlayTaskbar.qml`, `overlay/notes/NotesContent.qml`, `overlay/fpsLimiter/FpsLimiterContent.qml`, `common/Persistent.qml` (H8 only), `common/widgets/CalendarView.qml`, `koompi/sidebarRight/calendar/calendar_layout.js`, `koompi/mediaControls/MediaControls.qml`, `PlayerControl.qml`, `koompi/background/widgets/weather/WeatherWidget.qml` + `services/Weather.qml`, `common/Appearance.qml`, `koompi/onScreenDisplay/OnScreenDisplay.qml`, `onScreenDisplay/indicators/BrightnessIndicator.qml`, `GammaIndicator.qml`, `koompi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml`, `quickToggles/classicStyle/GameMode.qml`, `koompi/background/Background.qml`, `ReloadPopup.qml`, `koompi/screenTranslator/ScreenTextOverlay.qml`, `koompi/verticalBar/VerticalBar.qml`, `koompi/screenCorners/ScreenCorners.qml`, `common/utils/ImageDownloaderProcess.qml`, `FloatingImage.qml`, `koompi/intelligence/IntelligenceContext.qml`, `koompi/overview/OverviewWindow.qml`, `OverviewWidget.qml`, `koompi/bar/Resource.qml`, `koompi/regionSelector/RegionSelection.qml`, `CircleSelectionDetails.qml`
- Not yours: `koompi/bar/BarContent.qml` (J15 live), `InterfaceConfig.qml`, `FeedbackService.qml`, `AiChat.qml` (planned splits)

## Rules for every finding
1. Re-verify it in the tree before touching anything (read the code, reproduce where a command can). If a row is wrong, say so in the report with the evidence and skip it; do not "fix" a non-bug.
2. Fix the root cause, smallest diff, in the style of the surrounding code. No drive-by refactors.
3. One atomic commit per finding (or per tightly-coupled pair), subject `fix(<area>): <what>`, body: why it was wrong and how it failed.
4. Leave one runnable check per non-trivial fix: a `tests/test_*.sh` in the existing style for scripts/PKGBUILDs/workflows; for QML, `qmllint` clean on the touched file plus the smallest `qs -p` or `bash -c` reproduction you can paste.
5. Report: `.work/<JOB>-report.md` with one section per finding: verdict (confirmed / not a bug), what changed, the check and its pasted output. End with `./tests/run.sh` tail.

## Stop conditions
- Never `pkill`/`killall` by name; kill only pids you started. Never touch `~/.config/koompi/config.json`; test against copies.
- No `sudo`, no package installs; name what you need and stop.
- A fix that needs a file you do not own: stop, report which finding and which file.
