# J21 report — launch apps as app-*.scope units so systemd-oomd can act

Branch `j21-apps-into-app-slice`.
Files touched: `dots/.local/bin/koompi-launch` (new), `dots/.config/hypr/hyprland/keybinds.lua` (exec paths of the `App:` binds only), `services/LauncherSearch.qml`, `modules/koompi/dock/DockAppButton.qml`, `modules/koompi/launchpad/LaunchpadContent.qml`, `docs/navigation.md` (one paragraph), `tests/test_app_slice.sh` (new), this file.
One line outside the owned list: `sdata/dist-arch/koompi-shell/PKGBUILD` gains `koompi-launch` in `_tools`, because `tests/test_packaged_tools.sh` (J13) fails the suite for any `dots/.local/bin/koompi-*` that is neither shipped nor excluded, and a wrapper that is not in `/usr/bin` on KOOMPI OS does nothing.
`variables.lua` and `modules/koompi/overview/SearchItem.qml` are unchanged; why is under "Do 2".

## Do 1: `systemd-run --scope` over app2unit

`systemd-run --user --scope --slice=app.slice --unit=app-<id>-<n>.scope` wins.

| | `systemd-run --scope` | app2unit |
|---|---|---|
| dependency | systemd, already required | not in the Arch repos (`pacman -Si app2unit`: not found); AUR only, ~1000 lines of POSIX sh |
| env, cwd, stdio | inherited: `--scope` registers systemd-run's own pid in the scope and `exec`s the command in place (verified: the launched process's parent is the caller's shell, not systemd-run) | same, it calls `systemd-run --scope` underneath |
| cost | 7 ms per launch, measured over 20 runs (`systemd-run --user --scope … true`); the whole wrapper (bash start + systemd-run + exec) is also 7 ms | more, it parses the entry in sh |
| Exec parsing, `%u`/`%F` | not provided; the wrapper does it (below) | yes |
| `DBusActivatable` | ignored; the Exec line runs as a process. D-Bus activation would put the app in a `dbus-:1.x-<name>.service` under the same `app.slice`, so nothing is lost, and it is one code path instead of two | supports it |
| `Terminal=true` | wrapper: `--terminal CMD`, else `$TERMINAL`, else the first installed of the `variables.lua` terminal list, run as `TERM -e CMD…` | via xdg-terminal-exec |

Two things `systemd-run --scope` does that the man page does not make obvious, both handled:

- `--expand-environment` defaults to true even for scopes: a literal `$HOME` in argv came out as `/home/userx`. The wrapper passes `--expand-environment=no`; the test's raw-argv case pins `$HOME` and `%u` as literals.
- A scope whose main process exits non-zero stays around as failed. `--collect` garbage-collects it.

What the wrapper has to parse itself: Quickshell's `DesktopEntry.command` is already argv (its `parseExecString` handles quotes and drops every field code), so the shell's paths pass argv straight through and `--id`/`--cwd`/`--terminal` carry the id, `Path=` and `Terminal=` it also exposes.
The `.desktop` mode (`koompi-launch APP.desktop [FILE|URL…]`) exists for `xdg-open`-style launches and the test, and does the spec's two passes in bash: string unescape (`\s \n \t \r \\`) then quote splitting with `\" \` \$ \\` inside quotes, then per-argument field codes (`%f %u` first file, `%F %U` all, `%i` → `--icon ICON`, `%c` Name, `%k` path, `%%`, deprecated `%d %D %n %N %v %m` dropped, `--url=%u` inline).

Scope naming follows the XDG systemd app-unit convention `app-<ApplicationID>-<RANDOM>.scope`, with the id escaped the way `systemd-escape` does (alnum `: _ .` pass, everything else `\xHH`, so `term-scratch` becomes `term\x2dscratch` and the `-` separators stay unambiguous).

Fallback: without `systemd-run` or without `$XDG_RUNTIME_DIR/systemd/private` the command runs directly, and one line goes to stderr and `logger -t koompi-launch`.
That is what lets the test's parsing half run in CI, which has no user manager.

## Do 2: every launch path

| path | before | after |
|---|---|---|
| `App:` keybinds via `variables.lua` roles (terminal ×3, fileManager, browser, codeEditor, officeSoftware, textEditor, volumeMixer, settingsApp, taskManager) | `hl.dsp.exec_cmd(terminal)` | `app("terminal", terminal)` = `exec_cmd("koompi-launch --id terminal " .. terminal)` |
| `SUPER+SHIFT+W` brave, `SUPER+SHIFT+E` koompi-signature | `exec_cmd("brave")` | `app("brave", "brave")` |
| scratchpad widgets discord, whatsapp, telegram, term, sysmon (`toggle_app_scratchpad.sh <special> <class> <launch…>`) | launch = `discord` | launch = `koompi-launch --id discord discord` (the script execs its launch string through `hl.dsp.exec_cmd`, unchanged) |
| Search: app result, app action | `entry.execute()` / `bash -c "<terminal> -e '<joined argv>'"` | `LauncherSearch.launch(entry[, command])` → `Quickshell.execDetached(["koompi-launch", "--id", id, ("--cwd", Path)?, ("--terminal", Config.options.apps.terminal)?, "--", …command])` |
| Search: `>` command runner | `bash -c cmd` | `koompi-launch --id <first word> -- bash -c cmd` |
| Search: web search | `Qt.openUrlExternally(url)` (Qt runs `xdg-open` from inside the shell process, so the browser inherited the shell's cgroup) | `koompi-launch xdg-open url` |
| Launchpad | `entry.execute()` | `LauncherSearch.launch(entry)` |
| dock, click and middle-click | `desktopEntry?.execute()` | `LauncherSearch.launch(desktopEntry)` |
| `SearchItem.qml` | calls the `execute` closures built in `LauncherSearch.appResult`, never `DesktopEntry.execute()` | unchanged, already covered by the row above |

The wrap is at the keybind, not in `variables.lua`, so a user's `custom/variables.lua` override of `terminal = "foot"` still lands in `app.slice`.
Terminal entries (`Terminal=true`) now run as `<terminal words> -e <argv…>` instead of `bash -c "<terminal> -e '<argv joined by spaces>'"`; the old form handed kitty one argument containing the whole command, which the comment above it ("probably needs more proper escaping") already knew.

Not routed, not owned by this job, listed so nobody assumes they are covered:

- `services/SessionRestore.qml:131` `entry.execute()`: restored windows after login land in the session scope.
- `modules/waffle/**` (StartMenu `SearchResultButton`, `AppCategoryGrid`, `BigAppGrid`, `SearchResults`, `TaskAppButton`): the waffle family calls `execute()` directly. `LauncherSearch.launch(entry)` is the one-line replacement when that family is opened.
- `Quickshell.execDetached(["xdg-open", …])` in `SettingsPages.qml`, `HyprlandConfig.qml`, `MessageCodeBlock.qml`, `ScreenshotAction.qml`, `snip_to_search.sh`, and the notification `--exec xdg-open` tests in keybinds: shell utilities opening a file or URL; the handler inherits the shell's cgroup. `koompi-launch xdg-open …` is the drop-in, same as the web-search row.

## Do 3: what stays out of `app.slice`, and where it is

Everything the session cannot lose is still under `hl.dsp.exec_cmd` / `hl.exec_cmd` and sits in the logind session scope, which oomd never considers.
Measured on this machine after the change:

```
Hyprland                     /user.slice/user-1000.slice/session-3.scope
qs                           /user.slice/user-1000.slice/session-3.scope
hypridle                     /user.slice/user-1000.slice/session-3.scope
hyprsunset                   /user.slice/user-1000.slice/session-3.scope
wl-paste                     /user.slice/user-1000.slice/session-3.scope
easyeffects                  /user.slice/user-1000.slice/session-3.scope
```

`koompi-global-menu-daemon` was not running in this session (J10's daemon); it is started from `execs.lua`, so it would land in the same session scope as the rest.
Kept out on purpose in `keybinds.lua`: everything described `Shell:` (restart widgets, welcome guide, wallpaper fallback), `Utilities:` (hyprpicker, hyprshot, grim/slurp/tesseract, record.sh, cliphist, fuzzel fallbacks, the AI buffer query), `Media:`, `Screen:`, `Session:` (lock, suspend, poweroff, koompi-lid) and the hidden test notifications.
`koompi-settings` (`SUPER+I`) is a separate `qs -p settings.qml` process and is an app for this purpose; losing it loses nothing, so it goes through the wrapper with the rest of the `App:` group.

## Do 4 and Acceptance 1: cgroups of a GUI app and a terminal launched through the wrapper

Launched through the real keybind strings (`hyprctl dispatch 'hl.dsp.exec_cmd("<worktree>/dots/.local/bin/koompi-launch --id terminal ~/.config/hypr/hyprland/scripts/launch_first_available.sh …")'`), nothing copied into `~/.config` or `~/.local`:

```
$ systemd-cgls --user   (app.slice, and where the session lives)
│   │ ├─session.slice
│   │ ├─app.slice
│   │ │ ├─app-terminal-3936273400.scope
│   │ │ │ ├─1127589 bash /home/userx/.config/hypr/hyprland/scripts/launch_first
│   │ │ │ ├─1127590 kitty -1
│   │ │ │ └─1127647 /usr/bin/kitten __watch_conf__ 1127590 100 /etc/xdg/kitty/k
│   │ │ ├─kitty-1127590-0.scope
│   │ │ ├─app-volumeMixer-731035749.scope
│   │ │ │ ├─1127591 bash /home/userx/.config/hypr/hyprland/scripts/launch_first
│   │ │ │ └─1127592 pavucontrol-qt
│   └─session-3.scope
│     ├─   2268 Hyprland --watchdog-fd 4
│     ├─   2341 wl-paste --type text --watch bash -c cliphist store && qs -c $q
│     ├─   2343 wl-paste --type image --watch bash -c cliphist store && qs -c $
│     ├─   2606 hyprsunset
│     ├─ 564060 hypridle
│     ├─ 702039 qs -c koompi

$ cgroup of the launched pids
kitty pid=1127590            /user.slice/user-1000.slice/user@1000.service/app.slice/app-terminal-3936273400.scope
pavucontrol-qt pid=1127592   /user.slice/user-1000.slice/user@1000.service/app.slice/app-volumeMixer-731035749.scope

$ systemctl --user list-units "app-*.scope"
app-com.google.Chrome-2875.scope loaded active running app-com.google.Chrome-2875.scope
app-terminal-3936273400.scope    loaded active running [systemd-run] /home/userx/.config/hypr/hyprland/scripts/launch_first_available.sh "kitty -1" foot
app-volumeMixer-731035749.scope  loaded active running [systemd-run] /home/userx/.config/hypr/hyprland/scripts/launch_first_available.sh pavucontrol-qt pavucontrol
```

Environment: `WAYLAND_DISPLAY`, `QT_QPA_PLATFORM`, `HYPRLAND_INSTANCE_SIGNATURE` and the cwd are the caller's inside the scope (checked directly: `WAYLAND_DISPLAY=wayland-1 QT_QPA_PLATFORM=wayland HYPRLAND_INSTANCE_SIGNATURE=efb50993 cwd=/tmp`); pavucontrol-qt above is `xwayland=true` because the session-wide xcb default (J10) reached it, same as before.
Cleanup killed only the pids listed in the two scopes' `cgroup.procs`; both scopes were gone afterwards.

Two apps behave differently from the plain case and are worth knowing:

- KDE apps scope themselves. Dolphin launched the *old* way was already in `app.slice/app-org.kde.dolphin-<pid>.scope/main.scope` (KDBusService moves the process into a transient scope). Through the wrapper it moves from `app-fileManager-<n>.scope` into its own, same slice, so the wrapper is a no-op for KDE apps and the timing below is the pure overhead. Chrome does the same (`app-com.google.Chrome-2875.scope` above). kitty creates an empty `kitty-<pid>-0.scope` beside ours and stays in ours.
- `wezterm` (the first entry of the terminal role) attaches to an already running `wezterm-gui` ("Spawned your command via the existing GUI instance"), so while a wezterm started outside `app.slice` is running, `SUPER+Return` opens a window in that process and inherits its cgroup. On a KOOMPI machine the first wezterm is the keybind's, in `app.slice`, and later ones join it. Here herdr's wezterm predates the session's scoping, which is why the demonstration above uses kitty; `wezterm start --always-new-process` would change the role's semantics (one process per window) and is not this job's call.

## Acceptance 2: `oomctl` and the test run

`oomctl` cannot be shown on this machine: `systemd-oomd` is inactive and `koompi-sysdefaults` (J14) is not installed here, so `app.slice` still reports `ManagedOOMMemoryPressure=auto`:

```
$ systemctl --user show app.slice -p Slice -p ManagedOOMMemoryPressure -p ManagedOOMSwap; systemctl is-active systemd-oomd
Slice=-.slice
ManagedOOMSwap=auto
ManagedOOMMemoryPressure=auto
inactive
$ oomctl
Failed to dump context: Could not activate remote peer 'org.freedesktop.oom1': activation request failed: unknown unit
$ sudo -n true
sudo: a password is required
```

Blocked on sudo; the one command that clears it, after J14's package is installed: `sudo systemctl enable --now systemd-oomd && systemctl --user daemon-reload && oomctl`.
With J14's drop-in the user manager reports `ManagedOOMMemoryPressure=kill` on `app.slice` and `oomctl` lists `/user.slice/user-1000.slice/user@1000.service/app.slice` under "Memory Pressure Monitored CGroups" (J14 report, Do 5); every `app-*.scope` above is a child of that path, which is the whole point.

```
$ bash tests/test_app_slice.sh; echo rc=$?
koompi-launch: argv, field codes, Path=, Terminal=, fallback and call sites hold
rc=0
```

The test: argv with spaces, an empty argument, a double quote, a literal `$HOME` and a literal `%u` reach the app unchanged and `WAYLAND_DISPLAY` is inherited; a `.desktop` with `%i %c "quoted \\"arg\\"" --url=%u %u %% tab\there %k %d` and `Path=` expands to exactly the expected argv in the expected directory; `%F` takes both files and `Terminal=true` becomes `$TERMINAL -e …`; `--terminal` beats `$TERMINAL` and `--cwd` beats `Path=`; a missing `--cwd` warns and still launches; an unknown entry exits 1 with a message; with `XDG_RUNTIME_DIR` pointed at an empty dir the app still starts and stderr says "no user manager"; with a live user manager (`systemctl --user is-system-running` = running/degraded) a launched `sleep` is in `…/app.slice/app-probe\x2dx-<n>.scope` and is killed by its pid; and statically, the three QML files call no `DesktopEntry.execute()` and every `App:` bind in `keybinds.lua` goes through `app()` or `koompi-launch`.
Without a user manager the cgroup half prints "skipping cgroup check" and the run counts as skipped, per `tests/run.sh`.

The QML form was also run for real, because the suite never instantiates QML: a `qs -p` script calling the exact `launch()` body against a real `DesktopEntry` from a temp `XDG_DATA_HOME`:

```
entry: qsprobe command: [".../argdump","one two","three"] wd: .../work term: false
--- argdump output:
cwd=/home/userx/.tmp/tmp.5Nux9ixN77/work
cg=/user.slice/user-1000.slice/user@1000.service/app.slice/app-qsprobe-488347492.scope
[one two]
[three]
```

That probe caught one thing the lints did not: `Quickshell.execDetached({ command, workingDirectory })`, the documented object form, is rejected by this Quickshell build ("Could not convert argument 0 from [object Object] to qs::io::process::ProcessContext"; `processcore.hpp` carries a note about `QML_STRUCTURED_VALUE` and Qt 6.9). The shell uses the list form and the working directory travels as `--cwd`.

## Acceptance 3: timings, dolphin via the keybind path

`.work/tools/timelaunch.sh dolphin <label> hyprctl dispatch 'hl.dsp.exec_cmd("…launch_first_available.sh dolphin")'`, old and new interleaved so drift hits both:

```
old1: 0.23s    new1: 0.35s
old2: 0.24s    new2: 0.33s
old3: 0.34s    new3: 0.33s
old4: 0.36s    new4: 0.33s
old5: 0.35s    new5: 0.34s
old mean 0.304s   new mean 0.336s   Δ +32 ms
```

Three earlier runs each before interleaving: old 0.43/0.24/0.24, new 0.33/0.45/0.34.
The wrapper's own cost, 20 runs of `koompi-launch --id bench true` end to end: 7 ms average (`bash -c true`: 1 ms).
Within the ~50 ms budget; the rest of the spread is dolphin.

## Do 5 and Acceptance 3: app-id/class unchanged

Before (old path; the wezterm rows are herdr's, launched outside the wrapper):

```
class=dolphin initialClass=dolphin title=night-market — Dolphin pid=1095713 xwayland=true
class=org.wezfurlong.wezterm initialClass=org.wezfurlong.wezterm title=herdr pid=2877 xwayland=false
```

After (wrapper, keybind path):

```
class=kitty initialClass=kitty title=~ pid=1127590 xwayland=false
class=pavucontrol-qt initialClass=pavucontrol-qt title=Volume Control pid=1127592 xwayland=true
```

and dolphin through the wrapper matched `"class": "dolphin"` in all eight timed runs (that is what `timelaunch.sh` waits on).
`systemd-run --scope` changes nothing the compositor sees: same binary, same env, same Wayland socket; the dock's toplevel matching and `rules.lua` key on class/app-id, which are set by the app.

## Acceptance 4: gates

```
$ ./tests/run.sh | tail -4
  ok test_zig_build_abort.sh

73 passed, 2 skipped, 0 failed
skipped: test_globalmenu.sh test_search_bench_parity.sh
```

Baseline was 72 passed, 1-2 skipped, 0 failed; the +1 is `test_app_slice.sh` (`ok`, line 26 of the log). `test_packaged_tools.sh` and `test_keybind_descriptions.sh` are `ok` with the changes.

```
$ luac5.4 -p dots/.config/hypr/hyprland/keybinds.lua && echo ok
ok
$ shellcheck -S style dots/.local/bin/koompi-launch tests/test_app_slice.sh && echo clean
clean
```

qmllint (`/usr/lib/qt6/bin/qmllint`, `-I` with the shell root symlinked as `qs`, HEAD tree vs working tree), warnings/errors before → after:

| file | before | after | delta |
|---|---|---|---|
| `services/LauncherSearch.qml` | 7 / 0 | 7 / 0 | none |
| `modules/koompi/launchpad/LaunchpadContent.qml` | 24 / 0 | 24 / 0 | none |
| `modules/koompi/dock/DockAppButton.qml` | 48 / 0 | 50 / 0 | two "Unqualified access" on the two new `LauncherSearch.launch(root.desktopEntry)` lines (67, 76), the same category as the other 48 in the file, because qmllint cannot resolve `qs.services` singletons ("Warnings occurred while importing module qs.services") |

## Stop conditions

Nothing was killed by name: cleanup read `cgroup.procs` of the two scopes this job created and killed those pids, and the one wezterm pane the manual probe opened in herdr's process was closed with `wezterm cli kill-pane --pane-id 3` (its shell, pid 1125867, started at the probe's timestamp).
`~/.config/koompi/config.json` untouched; nothing copied into `~/.config` or `~/.local`.
The session start is unchanged: `app.slice` is reachable per launch with `systemd-run --scope`, so the uwsm question did not arise.
