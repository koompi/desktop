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
| — | C1 (start-hyprland) | FALSE: owned by stock hyprland 0.56.2 | — | closed | — |
| — | H1 H2 M21 | folded into J11 (addendum sent) | — | — | — |

Contended: `tests/file-length-allow.txt` is written by J01 and later trimmed by J09 only; refactor jobs never touch it (a shrunk file still passes). `tests/run.sh` is not owned by anyone: it auto-discovers `test_*.sh` (`tests/run.sh:21`).

Opencode's bug audit (`/tmp/koompi-audit.md`, running) is folded in before dispatch: any finding inside a job's owned files goes into that job's Do as a numbered step, so the fix and the split land in one verified diff; findings elsewhere become J10+.
