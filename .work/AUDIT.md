# Audit — file length and maintainability

Standard applied (external references, not opinion):
- ESLint `max-lines` default 300 lines per file; `max-lines-per-function` default 50. https://eslint.org/docs/latest/rules/max-lines
- Linux kernel coding style: a function fits one or two screenfuls (~48 lines), one thing, 5-10 locals max. https://www.kernel.org/doc/html/latest/process/coding-style.html
- Google Shell Style Guide: a script over 100 lines with non-trivial control flow should be a structured language. We keep bash for `setup` by decision; the number is the warning line for a single file.
- SonarQube "files should not have too many lines" default 1000 is the ceiling nobody should reach.

Our caps (chosen so the current tree passes except the rows below, then ratcheted):
| kind | file cap | function cap |
|---|---|---|
| QML | 400 | 60 |
| JS, Lua | 300 | 50 |
| bash | 400 | 60 |
| Zig | 600 | 80 |

Measured 2026-08-25 over `git ls-files` minus vendored/generated/tests: 874 files; 819 under 400, 42 in 400-800, 11 in 800-1500, 2 over 1500.

| id | title | ours | target | effort | why |
|---|---|---|---|---|---|
| D1 | dead vendored vaxis | `installer/zig-pkg/vaxis-0.6.0-*/` 55 files, 776 KB; `installer/build.zig.zon:3` says "No dependencies: vaxis was imported but never actually wired" | directory absent | S | Dead code in git that shows up in every grep and every line count. |
| D2 | emoji table inside a script | `dots/.config/hypr/hyprland/scripts/fuzzel-emoji.sh` 1956 lines; code is lines 1-27, data after `### DATA ###` (line 28), read back via `sed` on `$0` (line 9) | ~30-line script + `fuzzel-emoji.txt` data file | S | Data in a script defeats shellcheck (file disables SC2317/SC1089 for it) and any length rule. |
| D3 | no cap, no ratchet | `docs/conventions.md` has naming rules only (lines 9-55), nothing on size; `tests/run.sh:21` runs every `tests/test_*.sh` | conventions section with the table above + `tests/test_file_length.sh` that fails a new file over cap and fails any allow-listed file that grows | S | Without a gate the outliers come back. |
| D4 | InterfaceConfig.qml 932 lines | `modules/settings/InterfaceConfig.qml`: 13 `ContentSection`s, no shared ids/props (only `editorButton`:342, `mouseArea`:620, each local); loaded by path at `services/SettingsPages.qml:38` | `InterfaceConfig.qml` ~25 lines + 11 section files in `modules/settings/interface/` | S | Purely mechanical; zero coupling. |
| D5 | setups.sh 630 lines | `sdata/install/setups.sh`: 21 functions; `setup:27` sources it; `setup:234`, `setup:237`, `sdata/install/update.sh:75` call `setup_global_menu`/`setup_services` directly; sibling files are one-concern-per-file (`deps.sh` 26, `apps.sh` 56) | `setups.sh` = source lines + `run_setups` (<30 lines); 9 files under `sdata/install/setups/` | M | Entry points must keep their names; shellcheck must stay clean (`.github/workflows/installer.yml:41`). |
| D6 | installer main.zig 931 lines | `installer/src/main.zig`: 8 clusters (theme/TOML 23-277, ANSI 278-362, glyphs 363-405, model 406-484, input 486-530, handlers 531-568, frame render 569-817, driver 818-892), tests 894-931; `build.zig:14,31` name only `src/main.zig` | `theme.zig`, `term.zig`, `app.zig`, `ui.zig`, `main.zig` (~80 lines) with a `test { _ = @import(...) }` block so `zig build test` still reaches the moved tests | M | Only `draw` and `Ctx` cross from render to driver; clean seam. |
| D7 | FeedbackService.qml 1094 lines | `services/ai/FeedbackService.qml`: pure rules 61-363 (26 functions, no QML types, banner at 61-64), persistence 997-1072, habit table 941-991, trust ledger 794-888, report 890-936, hub 366-792; `tests/test_ai_correction.sh:15,57-75` lifts the pure functions by name from this file; facade at `services/Ai.qml:184-206,241`; `ToolRunner.qml:287` reads `filterRecall` | `feedbackRules.js` + `FeedbackStore.qml` + `HabitTable.qml` + `TrustLedger.qml` + `HallucinationReport.qml`, hub keeps the same public surface so no consumer changes | L | Highest-value split: the rules become a plain JS module a node test can import directly. |
| D8 | AiChat.qml 1389 lines | `modules/koompi/sidebarLeft/AiChat.qml`: command table 56-495 (22 commands, 55-line fixture at 440-495), completion 608-711 + 952-983, composer 713-729 + 1073-1387, transcript 739-902, status strips 904-1041, sheets 1043-1071; single instantiation `SidebarLeftContent.qml:93`; composer and transcript welded by ids (`messageInputField`, `messageListView`) | `aiChat/ChatCommands.qml`, `CommandCompletion.qml`, `ChatTranscript.qml`, `ChatComposer.qml`, `RecallStrip.qml`, `ContextMeter.qml`; `AiChat.qml` ~180 lines wiring them with signals | L | Largest and most entangled; the two id couplings become signals. |

## ALREADY BUILT
- `Config.qml` 827 lines is the options schema with defaults: data, not logic. Left alone; listed in the allow-list.
- `fuzzysort.js` 682 lines is a vendored library. Left alone; allow-listed.
- `BackgroundConfig.qml` 683, `LockSurface.qml` 734, `Conversation.qml` 729, `koompi-quicklook/shell.qml` 667, `audiod/engine.zig` 698: over cap, under 800, single concern each. Allow-listed with their current length so they can only shrink; not in this campaign.
- `docs/conventions.md` already has one-component-per-file for QML (line 13) and a private-member convention (40-41); D3 extends it rather than replacing it.

## Bugs found 2026-08-25 (not deltas against a target; evidence in the job files)

| id | title | ours | evidence | job |
|---|---|---|---|---|
| B1 | packaged `koompi update` cannot deliver our packages | `libexec/update` `is_packaged` → `pacman -Syu` | `[koompi]` repo skeleton: `sdata/dist-arch/repo/README.md:20`, `iso/koompi/pacman.conf:26` | J11 |
| B2 | changed config defaults never reach existing users | `Config.qml` defaults, `files.sh` rsync skips `config.json` | user screenshot vs `Config.qml:725` | J11 |
| B3 | dev machine config ≠ shipped defaults | `~/.config/koompi/config.json` | `quickSliders.enable` true vs false | J11 (diff only) |
| B4 | Qt apps ~6.3 s to first window | `env.lua:30` `QT_QPA_PLATFORM=xcb` | timelaunch 6.4 s vs 0.24 s wayland | J10 |
| B5 | ISO installs stock Arch, installer wants `[koompi]` packages | `packages.x86_64`, `archinstall.zig:31` | `pacman.conf:26` disabled | J12 |
