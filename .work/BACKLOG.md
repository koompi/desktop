# Backlog — file length refactor

Baseline 2026-08-25 at `bf678012`: `./tests/run.sh` → `56 passed, 0 failed`. `cli` and `installer` `zig build test` exit 0 (installer 4/4). shellcheck as in `.github/workflows/installer.yml:41-45` clean.

Gate for every job: those three stay green, the job's own acceptance demonstrations pass in the lead's pane, and the touched file(s) are under cap or shrank.

`.work/` is gitignored (`.gitignore:34`); contracts are force-added before dispatch (`git add -f .work/AUDIT.md .work/BACKLOG.md .work/jobs`) so worktrees carry them.

| id | title | deltas | owns | state | pairs with |
|---|---|---|---|---|---|
| J01 | length cap + ratchet test | D3 | `docs/conventions.md`, `tests/test_file_length.sh`, `tests/file-length-allow.txt` | ready | — |
| J02 | delete dead vaxis | D1 | `installer/zig-pkg/**`, `installer/build.zig.zon` (comment only) | ready | — |
| J03 | emoji data out of script | D2 | `dots/.config/hypr/hyprland/scripts/fuzzel-emoji.sh`, `dots/.config/hypr/hyprland/scripts/fuzzel-emoji.txt` | ready | — |
| J04 | split InterfaceConfig.qml | D4 | `dots/.config/quickshell/koompi/modules/settings/InterfaceConfig.qml`, `dots/.config/quickshell/koompi/modules/settings/interface/**` | ready | — |
| J05 | split setups.sh | D5 | `sdata/install/setups.sh`, `sdata/install/setups/**` | ready | — |
| J06 | split installer main.zig | D6 | `installer/src/**` | after J02 | J02 (same dir tree, serial) |
| J07 | split FeedbackService | D7 | `dots/.config/quickshell/koompi/services/ai/FeedbackService.qml`, `services/ai/feedbackRules.js`, `services/ai/FeedbackStore.qml`, `services/ai/HabitTable.qml`, `services/ai/TrustLedger.qml`, `services/ai/HallucinationReport.qml`, `tests/test_ai_correction.sh` | ready | — |
| J08 | split AiChat.qml | D8 | `dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/AiChat.qml`, `.../sidebarLeft/aiChat/ChatCommands.qml`, `CommandCompletion.qml`, `ChatTranscript.qml`, `ChatComposer.qml`, `RecallStrip.qml`, `ContextMeter.qml`, `testMessage.js` | ready | — |
| J09 | ratchet allow-list cleanup | D3 | `tests/file-length-allow.txt` | after J01 J03 J04 J05 J06 J07 J08 | lead-only, no pane |
| J10 | Qt apps take ~6 s to open (xcb) | B4 | `hypr/hyprland/env.lua`, `execs.lua`, global-menu daemon | ready | — |
| J11 | `koompi update` delivers nothing / config defaults never migrate | B1 B2 B3 | `libexec/update`, `sdata/install/update.sh`, `files.sh`, `koompi-migrate`, new tests | ready | — |
| J12 | published ISO cannot install the desktop | B5 | ISO profile, CI | blocked-on-user | — |
| J13 | packaged tools list + agent docs | O01 O20 | `koompi-shell/PKGBUILD`, `docs/agents/{hooks,plugins}.md`, new test | ready | — |
| J14 | low-RAM defaults (zram, oomd, shutdown) | O06 | new sysdefaults package, meta depends, `setups.sh` one fn | ready | — |
| J15 | lid lock, bar mode indicators, keybind descriptions | O07 O11 O04 | `keybinds.lua`, bar QML, new `koompi-lid`, new test | ready | — |
| J16 | packaging, CI, test harness bugs | H3 H4 H5 H6 M4 M5 L21 L22 L23 | PKGBUILDs (shell, hyprland-config, microtex), repo/CI workflows, `tests/run.sh` | ready | — |
| J17 | shell script + Lua config bugs | M1 M2 M3 H9 M20 L20 M22 L18 L19 L24 L25 | `switchwall.sh`, `apps.sh`, `setups.sh` (lines), 3 bins, `status.sh`, `general.lua` | after J14 | — |
| J18 | Quickshell services bugs | H7 M6 M7 M8 M13 M14 M16 L2-L5 L7 L11 L12 L13 | 17 files under `services/` | ready | — |
| J19 | Quickshell modules bugs | H8 M9-M12 M15 M17-M19 L1 L6 L8-L17 | ~30 files under `modules/` | after J15 | — |
| J20 | lock screen unlocks itself after 2.6 s | J15 finding | `modules/koompi/lock/*`, `common/panels/lock/pam/*`, new test | ready | — |
| J21 | launch apps as app-*.scope so oomd can act | J14 finding | new `koompi-launch`, exec paths in keybinds + 4 QML call sites, new test | after J15 J19 (same QML files) | — |
| J22 | hypridle output to the journal / packaged unit; prove Lock handling | J15 finding 3 | `execs.lua` (one line), optional user unit + `setup_services`, new test | ready | — |
| J24 | `koompi update` hardening: lock, inhibit, free space, reboot advice, lock-aware reload | O02 O10 O21 | `libexec/update`, `koompi-reload`, new test | ready (after J11, merged) | — |
| J25 | port installer/src to zig 0.16 std.Io | J06 finding | `installer/src/**`, `.zon` min version | ready (after J06, merged) | — |
| J26 | length walk: Rust (cap 600) and libexec/update | J01 finding | `tests/test_file_length.sh`, allow-list (add rows), `docs/conventions.md` table | ready | J09 after it (same allow-list) |
| J27 | 0xAlpha is the default remote AI model | Rithy 15:20 | `ModelRegistry.qml`, `Persistent.qml` (default), `Config.qml` sample, new test | ready | — |
| J28 | `/model` with no argument wipes remote state | J08 finding | `ModelRegistry.qml` setModel, probe test | ready | — |
| J29 | migrations delivered: clickable toast, reload guard, per-file refresh, authoring guide | O03 O22 O26 O27 | `koompi-migrate` (+ optional `libexec/migrate-lib.sh`), `koompi-migrate-notify.service`, `docs/agents/migrations.md`, new test | ready | — |
| J30 | `koompi update` transcript + `doctor --last-update` diagnosis + firmware advice | O28 O31 | `libexec/update` (≤695), `update-lib.sh`, `koompi-health`, new test | ready | J33 ships fwupd (no file overlap) |
| J31 | `koompi toggle` with predicate + notification keybinds | O24 O12 | `services/{Idle,Hyprsunset,Notifications}.qml`, new `koompi-toggle`, `cli/src/main.zig`, `koompi-shell/PKGBUILD`, `keybinds.lua` (≤447) + `keybinds_notifications.lua` + `hyprland.lua`, new test | ready | J32/J34 after it (PKGBUILD `_tools`, keybinds) |
| J32 | OSD from the command line + battery-low hook + TUI launch convention | O23 O29, ALREADY BUILT battery row | `OnScreenDisplay.qml`, new `koompi-osd`, `koompi-shell/PKGBUILD`, `services/Battery.qml`, `hyprland/scripts/launch_*.sh`, `rules.lua` | after J31 | — |
| J33 | packages: ufw default-deny (+KDE Connect, LocalSend ports), localsend, fwupd, tesseract-data-khm | O25 O17 O31 khm | `koompi-sysdefaults/**`, `koompi-apps`/`koompi-basic`/`koompi-screencapture` PKGBUILDs, `setups/system.sh`, `post_install.sh`, tests | ready | — |
| J34 | update badge on the KOOMPI bar + bar popups by keyboard | O09 O34 | `services/Updates.qml`, `modules/koompi/bar/**`, `keybinds_*.lua` | after J31 | — |
| J35 | cheatsheet rows searchable and executable | O13 | `modules/koompi/cheatsheet/**`, `services/HyprlandKeybinds.qml`, new test | ready | — |
| J36 | hibernation system half: swapfile, resume hook, cmdline; doctor line | O14 | new `libexec/hibernation-setup`, `post_install.sh`, `setups/system.sh`, `koompi-health` (one line), PKGBUILD install line, new test | after J33 J30 | — |
| J37 | fingerprint enrolment wizard + first-run invitation | O15 | new `koompi-hw-fingerprint`, `koompi-setup-fingerprint`, `pam/fprintd.conf`, `FirstRunExperience.qml`, `LockScreenSection.qml`, tests | after J31 | — |
| J38 | factory reset from @baseline | O16 | new `koompi-factory-reset`, `koompi-snapshot` | blocked-on-user | — |
| J39 | one text-size knob (shell, GTK, wezterm) | O18 | `Appearance.qml` (≤467), `Config.qml` (≤827), `FontsSection.qml`, `koompi-theme`, `wezterm.lua`, new test | ready | — |
| J40 | crash watch → local-agent diagnosis | O30 | new `koompi-crash-watch`, `koompi-crash-diagnose`, user unit, `docs/agents/crash.md`, new test | after J31 J33 | — |
| J41 | branded idle screen before lock | O32 | new `modules/koompi/screensaver/**`, `KoompiFamily.qml`, `GlobalStates.qml`, `hypridle.conf`, new test | ready | — |
| J42 | hardware quirk layer keyed on DMI | O08 | new `koompi-hw-match`, `koompi-hw-laptop`, `sdata/hardware/**`, `libexec/apply-hardware`, `post_install.sh`, `setups/system.sh`, `update-lib.sh` (one call), new test | after J33 J31 J30 | — |
| J43 | shell honours `koompi-notify-send --exec` (click runs the argv) | J29 finding | `services/Notifications.qml`, `widgets/NotificationItem.qml`, new test | after J31 | J37 J40 click paths need it |
| J44 | remote route: key gate on send, `extraModels` read, real window for remote | Rithy 19:40 | `services/ai/{Requester,ModelRegistry,OpenAiApiStrategy,MistralApiStrategy,AiModel,Conversation}.qml` + new siblings, `Config.qml` (comments), `tests/test_ai_remote_default.sh`, `docs/agents/ai.md` | ready | J45 (disjoint files) |
| J45 | model picker inside the sidebar; `/key` `/model` stop pointing at Settings | Rithy 19:40 | `modules/koompi/sidebarLeft/AiChat.qml`, `sidebarLeft/aiChat/{ChatComposer,ChatCommands,ChatTranscript,CommandCompletion}.qml`, `aiChat/composer/{ChatStatusBar,ModelPicker}.qml`, `tests/test_ai_model_picker.sh`, CI allow-list block | ready | J44 |
| — | C1 (start-hyprland) | FALSE: owned by stock hyprland 0.56.2 | — | closed | — |
| — | H1 H2 M21 | folded into J11 (addendum sent) | — | — | — |

Contended (wave 3): `sdata/dist-arch/koompi-shell/PKGBUILD` `_tools` rows are appended by J32 J37 J40 J42; workers leave `pkgrel` alone and the lead resolves the list as the union and bumps `pkgrel` once per merge. `post_install.sh` and `setups/system.sh` get one function + one call each from J36 J42 after J33.

Contended: `tests/file-length-allow.txt` is written by J01 and later trimmed by J09 only; refactor jobs never touch it (a shrunk file still passes). `tests/run.sh` is not owned by anyone: it auto-discovers `test_*.sh` (`tests/run.sh:21`).

Opencode's bug audit (`/tmp/koompi-audit.md`, running) is folded in before dispatch: any finding inside a job's owned files goes into that job's Do as a numbered step, so the fix and the split land in one verified diff; findings elsewhere become J10+.
