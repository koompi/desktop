# J10 — Qt apps take ~6 s to open (XWayland path)

Evidence, lead's pane, 2026-08-25 11:25, machine idle enough (load 3, 21 GB free):

| launch | window after |
|---|---|
| `hyprctl dispatch 'hl.dsp.exec_cmd("dolphin")'` (the keybind/launcher path, `QT_QPA_PLATFORM=xcb` from `env.lua:30`) | 6.40 s, 6.38 s |
| `env QT_QPA_PLATFORM=xcb dolphin` from a shell | 6.39 s, 6.29 s |
| `env QT_QPA_PLATFORM=wayland dolphin` | 0.24 s, 0.22 s |
| `env QT_QPA_PLATFORM=wayland Telegram` | 0.54 s |

A constant ~6.3 s regardless of app is a timeout, not work. The global env is set in
`dots/.config/hypr/hyprland/env.lua:26-30`: xcb is forced so Qt exports its menubar over
D-Bus for the global menu (`sdata/dist-arch/koompi-shell/PKGBUILD:22-25` explains the same).
Apps launched by the shell inherit it too (`hl.exec_cmd` env); only `qs` itself runs on
wayland (`execs.lua:7`).

## Files you own
- `dots/.config/hypr/hyprland/env.lua`
- `dots/.config/hypr/hyprland/execs.lua`
- the global-menu daemon and its launcher under `dots/` (locate it; name the paths in your report)
- `docs/` page that documents the global menu or environment, if one exists
- `.work/J10-report.md` (your report)

## Do
1. Reproduce with `.work/tools/timelaunch.sh dolphin before hyprctl dispatch 'hl.dsp.exec_cmd("dolphin")'` three times. Do the same with `Telegram` (class `org.telegram.desktop`) only if no Telegram window is open; never kill a window you did not open.
2. Find the exact wait. `strace -f -r -tt -e trace=connect,poll,ppoll,recvmsg,read -o /tmp/dolphin.strace env QT_QPA_PLATFORM=xcb dolphin` and `QT_LOGGING_RULES='qt.qpa.*=true;qt.dbus*=true' env QT_QPA_PLATFORM=xcb dolphin` are the first two tools. Name the fd/socket and the component on the other end (Xwayland, XSETTINGS, an XIM/`QT_IM_MODULE` input method, the `com.canonical.AppMenu.Registrar` name, qt6ct, xdg-desktop-portal, kwallet/kded, something else).
3. Fix it at the root. If the wait is on a service that should be there and is not (or is slow to own its D-Bus name), fix the service or its unit ordering so the wait disappears while `QT_QPA_PLATFORM=xcb` stays. If the wait is a client-side timeout that a config or env var removes, set that in `env.lua` with a comment saying what it removes and why.
4. If, after the analysis, the only remaining fix is to stop forcing xcb globally: STOP and write the report. That trades the Qt global menu for launch speed and Rithy decides it, not you.
5. `hyprctl reload`, then re-measure through the real path (step 1 command) three times for dolphin and once for Telegram. Also open one GTK app and one Electron app the same way and record their times so nothing regressed.
6. Confirm the global menu still works for a Qt app after the fix: focus dolphin, screenshot the bar (`grim -o eDP-1 .work/J10-globalmenu.png`; eDP-1 is the laptop panel) showing its File/Edit menu.

## Acceptance
1. Paste the strace/log lines showing the ~6 s gap, with the name of what it waited on.
2. Paste timelaunch output before and after: dolphin three runs each, Telegram one run each. After: every run under 1.0 s through `hl.dsp.exec_cmd`.
3. Paste the GTK and Electron timings before/after.
4. `.work/J10-globalmenu.png` exists and shows dolphin's menu in the bar.
5. `./tests/run.sh` tail: no new failures against the baseline in `.work/BACKLOG.md`.
6. Report in `.work/J10-report.md`: root cause in two sentences, the diff summary, the numbers above.

## Out of scope
- Refactoring `env.lua`, `execs.lua`, or any Quickshell QML.
- Removing `xorg-xwayland`/`xorg-xprop` from the package.
- Any `sudo pacman` change; if a package is needed, name it in the report and stop.

## Stop conditions
- Step 4: dropping xcb globally is a product decision. Report, do not commit it.
- Never `pkill`/`killall` by name; kill only PIDs you launched. The lead killed Rithy's Telegram this way today.
- Do not touch `~/.config/koompi/config.json` or any file outside your worktree except `/tmp`.
