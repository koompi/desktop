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

Contended: `tests/file-length-allow.txt` is written by J01 and later trimmed by J09 only; refactor jobs never touch it (a shrunk file still passes). `tests/run.sh` is not owned by anyone: it auto-discovers `test_*.sh` (`tests/run.sh:21`).

Opencode's bug audit (`/tmp/koompi-audit.md`, running) is folded in before dispatch: any finding inside a job's owned files goes into that job's Do as a numbered step, so the fix and the split land in one verified diff; findings elsewhere become J10+.
