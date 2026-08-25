# J21 — launch apps as app-*.scope units so systemd-oomd can act (J14 follow-up)

J14 (`.work/J14-report.md`, "Finding") shipped oomd with `ManagedOOMMemoryPressure=kill` on the user
`app.slice`, and proved that on KOOMPI nothing lives there: Hyprland (`koompi-session` → `start-hyprland`, no
uwsm) and everything it execs — keybind `hl.dsp.exec_cmd(...)` (`dots/.config/hypr/hyprland/keybinds.lua`),
the Search launcher (`services/LauncherSearch.qml:254` `entry.execute()`), the dock (`modules/koompi/dock/
DockAppButton.qml:66`), `Quickshell.execDetached` everywhere — sit in `session-N.scope`, which oomd never
considers. So the 4 GB machine still loses the whole session. Omarchy gets apps into `app.slice` because
`uwsm-app` starts each as an `app-*.scope` under the user manager.

## Files you own
- new `dots/.local/bin/koompi-launch` (or a sourced shell function if a script is the wrong shape; say why)
- `dots/.config/hypr/hyprland/keybinds.lua` (only the exec paths; J15's descriptions and lid binds stay)
- `dots/.config/hypr/hyprland/variables.lua` if the app commands live there
- `services/LauncherSearch.qml`, `modules/koompi/dock/DockAppButton.qml`, `modules/koompi/launchpad/LaunchpadContent.qml`, `modules/koompi/overview/SearchItem.qml` (the `execute()` call sites only)
- `docs/navigation.md` one paragraph; new `tests/test_app_slice.sh`; `.work/J21-report.md`
- Not yours: `services/Idle.qml`, `ConflictKiller.qml`, anything that kills by name; the sysdefaults package (J14)

## Do
1. Read `systemd-run --user --scope --slice=app.slice --unit=app-<desktop-id>-<rand>.scope` semantics and
   `app2unit` (Arch package) as the two candidates; pick one and say why (dependency count, desktop-entry
   `Exec` parsing with `%u`/`%F`, `DBusActivatable`, `Terminal=true`). The KOOMPI answer must not add a heavy
   dependency for a wrapper.
2. Route every launch path through it: keybinds (`exec_cmd`), Search/launchpad/overview/dock `execute()`
   (Quickshell's `DesktopEntry.execute()` cannot be wrapped; use the entry's `command` through the wrapper),
   `xdg-open`-style launches from the shell. Terminals and TUI launches included.
3. Keep out of `app.slice`: the shell itself, `koompi-global-menu-daemon`, hypridle, hyprsunset, the wallpaper
   and colour pipeline, anything the session cannot lose. List them in the report with the cgroup they end up in.
4. Test: with the wrapper, launch a GUI app and a terminal; `systemd-cgls --user` shows each under
   `app.slice/app-*.scope`; `oomctl` lists `.../app.slice` under "Memory Pressure Monitored CGroups"; the app's
   environment is the session one (`WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`, `QT_QPA_PLATFORM`
   unchanged — `systemd-run --scope` inherits, a service would not). `tests/test_app_slice.sh` asserts the
   cgroup of a launched `sleep` and that the wrapper preserves argv with spaces and `%u` expansion.
5. Window rules and the dock's toplevel matching must still work: app-id/class unchanged (paste `hyprctl clients`
   for two apps before/after).

## Acceptance
1. Paste `systemd-cgls --user` excerpt showing the launched apps under `app.slice`, the shell outside it.
2. Paste `oomctl` output and the test run.
3. Paste timings from `.work/tools/timelaunch.sh` for dolphin via keybind path before/after (the wrapper must
   not add more than ~50 ms).
4. `./tests/run.sh` tail on the merged tree; `luac5.4 -p` on keybinds.lua; `qmllint` delta on touched QML.

## Out of scope
- uwsm adoption, changing `koompi-session`, the sysdefaults package.

## Stop conditions
- Never kill by name; kill only pids you started. Never touch `~/.config/koompi/config.json`.
- If the only way to reach `app.slice` is to change how the session starts (`start-hyprland` → uwsm), stop and
  report; that is Rithy's call.
