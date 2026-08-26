# J47 - User manual report

Branch `j47-user-manual`. Three commits: the manual, the README pointer, the test.

**This is a draft for line-by-line approval. The voice is not settled.**
I wrote it to VOICE.md's register in its terser technical mode: short declaratives, second
person, plain dash, no hedging. Whether that is Rithy's voice for a manual, rather than for a
reflective post, is his call and not mine to declare settled.

## Chapters

Eleven, plus the index. Printing, USB drives and backups-as-a-separate-thing were dropped;
why is under Dropped below.

```
$ nice -n 19 ionice -c 3 wc -l docs/manual/*.md
   93 docs/manual/01-coming-from-mac-or-windows.md
   75 docs/manual/02-opening-things.md
   63 docs/manual/03-desks.md
   58 docs/manual/04-windows.md
   83 docs/manual/05-the-strip-along-the-top.md
   60 docs/manual/06-files.md
   44 docs/manual/07-getting-online.md
   43 docs/manual/08-capturing-the-screen.md
   68 docs/manual/09-the-assistant.md
   66 docs/manual/10-updates-and-going-back.md
   68 docs/manual/11-settings-and-help.md
   31 docs/manual/README.md
  752 total
```

## Acceptance

### 1. `wc -l docs/manual/*.md` - 12 chapters or fewer, none over 150 lines

Above. Eleven chapters (01-11) plus `README.md`, the index. Longest chapter: 93 lines.

### 2. `bash tests/test_manual_references.sh` - all PASS, rc 0

```
$ nice -n 19 ionice -c 3 bash tests/test_manual_references.sh; echo "rc=$?"
PASS 130 literal chords read from keybinds.lua and its siblings
PASS 38 loop-generated chords, each with its loop still in place
PASS every keybind named in the manual is bound (84 checked)
PASS every koompi subcommand named in the manual is in the CLI (11 checked)
PASS every koompi-* name in the manual exists (1 checked)
PASS 11 chapters, within the cap of 12
PASS every chapter is 150 lines or fewer
rc=0
```

### 3. The deliberate-failure demonstration

Two fake references appended to `docs/manual/04-windows.md`: a keybind we do not bind, and a
subcommand the CLI does not have.

```
$ cat >> docs/manual/04-windows.md <<'EOF'

`Super+Shift+F9` opens the widget shelf.

`koompi frobnicate` rebuilds the index.
EOF
$ nice -n 19 ionice -c 3 bash tests/test_manual_references.sh; echo "rc=$?"
PASS 130 literal chords read from keybinds.lua and its siblings
PASS 38 loop-generated chords, each with its loop still in place
FAIL keybind 'Super+Shift+F9' (SHIFT+SUPER+F9) is in the manual but bound nowhere
FAIL 'koompi frobnicate' is in the manual but is not a koompi subcommand
PASS every koompi-* name in the manual exists (1 checked)
PASS 11 chapters, within the cap of 12
PASS every chapter is 150 lines or fewer
rc=1
```

Removed again:

```
$ nice -n 19 ionice -c 3 bash tests/test_manual_references.sh; echo "rc=$?"
PASS 130 literal chords read from keybinds.lua and its siblings
PASS 38 loop-generated chords, each with its loop still in place
PASS every keybind named in the manual is bound (84 checked)
PASS every koompi subcommand named in the manual is in the CLI (11 checked)
PASS every koompi-* name in the manual exists (1 checked)
PASS 11 chapters, within the cap of 12
PASS every chapter is 150 lines or fewer
rc=0
```

Note which lines went red: the chord check and the subcommand check each name the offending
token, and the subcommand PASS line disappears rather than lying. The two counts read out of
the bind modules stayed PASS, which is what tells you the parser was healthy and the manual
was wrong, not the other way round.

### 4. Chapter 01 in full

```markdown
# Coming from Mac or Windows

You already know how to use a computer.
This chapter is only about the handful of things KOOMPI does differently.
Once these are in your hands, the rest of the manual is ordinary.

## The Super key

The key between Ctrl and Alt, the one printed with a Windows logo or a Command symbol, is called **Super** here.
It is the one key you have to learn.

Tap it on its own and let go, and Search opens.
Hold it and press another key, and you have given a command.

`Super+/` puts every shortcut on the screen.
`Super+Shift+/` starts the guided tour, which opens each part of the desktop as it names it.
You are not expected to remember any of this from reading.

## Where the taskbar and the dock went

There is neither.
There is a strip along the top of the screen, and it never moves.

On the left is the KOOMPI star and the name of the program you are in.
In the middle are your desks.
On the right are the clock, sound, network, battery, and anything asking for your attention.

You do not click along a taskbar to change programs.
You tap Super and type the name, or press `Super+Tab` and see every window at once.

A dock exists and it ships switched off.
Settings has the switch if you want one back.

## Windows arrange themselves

Nothing overlaps by default.
Open one window and it fills the screen.
Open a second and the screen splits between the two.
Open a third and it takes its share of the split.

You do not drag windows into position.
`Super+Left` and `Super+Right` move your attention between them.
`Super+Shift+Left` and `Super+Shift+Right` move the window itself.

When you want one window loose, `Super+Alt+Space` sets it free to float.
When you want the whole desktop to behave the way Windows does, `Super+Shift+Space` switches every window to stacking and back.

## What replaced Finder and Explorer

`Super+E` opens the file manager.
On a full KOOMPI install that is Dolphin.

For finding rather than browsing, tap Super and put `~` in front of what you type.
That searches your files and nothing else.

## Where the settings live

`Super+I` opens KOOMPI Settings, and `Super+I` again closes it.
Sound, network, Bluetooth, displays, power, the bar, the sidebars and the assistant are all in there.

The desktop takes its colours from your wallpaper.
`Ctrl+Super+T` picks a new one.
`Ctrl+Super+Shift+D` swaps light for dark.

## Installing software

KOOMPI ships no software shop.
Programs come from your distribution's package manager, in a terminal, the same as on any Linux machine.

A website can become a program of its own:

```sh
koompi webapp install "HEY" https://hey.com
```

It gets an icon, an entry in Search, and a window with no browser wrapped around it.
`koompi webapp remove HEY` takes it away again.

## What closing the lid does

It locks the screen.
It does not lock when an external monitor is attached, so a docked laptop keeps working with the lid down.

Left alone, the machine shows a screensaver after two minutes, locks after five, turns the screen off after ten, and sleeps after fifteen.
The **Keep awake** tile in the right-hand panel stops all four while it is on.

## Two habits to unlearn

`Alt+F4` does not close a window here.
`Super+Q` does, and pressing `Alt+F4` tells you so instead of ignoring you.

`Ctrl+Alt+Delete` is not a rescue key.
It opens the session menu: lock, sleep, log out, task manager, shut down, restart.
```

### 5. Verification table

Shell paths are relative to `dots/.config/quickshell/koompi/`; everything else is repo-relative.

Every keybind the manual names, with the line that binds it. `(loop)` means the chord is one
of a family a Lua loop produces, and the line given is the loop; the test declares each family
against that loop's text and rejects the family if the loop goes away.

```
Alt+F4                         dots/.config/hypr/hyprland/keybinds.lua:247
Ctrl+Alt+Delete                dots/.config/hypr/hyprland/keybinds.lua:78
Ctrl+Alt+R                     dots/.config/hypr/hyprland/keybinds.lua:144
Ctrl+Shift+Alt+Super+Delete    dots/.config/hypr/hyprland/keybinds.lua:428
Ctrl+Shift+Escape              dots/.config/hypr/hyprland/keybinds.lua:443
Ctrl+Super+Alt+/               dots/.config/hypr/custom/keybinds.lua:1
Ctrl+Super+Alt+T               dots/.config/hypr/hyprland/keybinds.lua:102
Ctrl+Super+Left                dots/.config/hypr/hyprland/keybinds.lua:353 (loop)
Ctrl+Super+P                   dots/.config/hypr/hyprland/keybinds.lua:112
Ctrl+Super+R                   dots/.config/hypr/hyprland/keybinds.lua:109
Ctrl+Super+Right               dots/.config/hypr/hyprland/keybinds.lua:353 (loop)
Ctrl+Super+Shift+D             dots/.config/hypr/hyprland/keybinds.lua:104
Ctrl+Super+T                   dots/.config/hypr/hyprland/keybinds.lua:100
Print                          dots/.config/hypr/hyprland/keybinds.lua:152
Shift+Print                    dots/.config/hypr/hyprland/keybinds.lua:159
Super                          dots/.config/hypr/hyprland/keybinds.lua:33
Super+'                        dots/.config/hypr/hyprland/keybinds.lua:259
Super+,                        dots/.config/hypr/hyprland/keybinds_shell_extra.lua:15
Super+.                        dots/.config/hypr/hyprland/keybinds.lua:46
Super+/                        dots/.config/hypr/hyprland/keybinds.lua:71
Super+0                        dots/.config/hypr/hyprland/keybinds.lua:328 (loop)
Super+1                        dots/.config/hypr/hyprland/keybinds.lua:328 (loop)
Super+;                        dots/.config/hypr/hyprland/keybinds.lua:258
Super+A                        dots/.config/hypr/hyprland/keybinds.lua:47
Super+Alt+,                    dots/.config/hypr/hyprland/keybinds_shell_extra.lua:19
Super+Alt+0                    dots/.config/hypr/hyprland/keybinds.lua:277 (loop)
Super+Alt+1                    dots/.config/hypr/hyprland/keybinds.lua:277 (loop)
Super+Alt+A                    dots/.config/hypr/hyprland/keybinds.lua:48
Super+Alt+S                    dots/.config/hypr/hyprland/keybinds.lua:320
Super+Alt+Space                dots/.config/hypr/hyprland/keybinds.lua:261
Super+C                        dots/.config/hypr/hyprland/keybinds.lua:438
Super+Ctrl+1                   dots/.config/hypr/hyprland/keybinds_shell_extra.lua:34 (loop)
Super+Ctrl+2                   dots/.config/hypr/hyprland/keybinds_shell_extra.lua:34 (loop)
Super+Ctrl+3                   dots/.config/hypr/hyprland/keybinds_shell_extra.lua:34 (loop)
Super+Ctrl+4                   dots/.config/hypr/hyprland/keybinds_shell_extra.lua:34 (loop)
Super+D                        dots/.config/hypr/hyprland/keybinds.lua:267
Super+Down                     dots/.config/hypr/hyprland/keybinds.lua:229 (loop)
Super+E                        dots/.config/hypr/hyprland/keybinds.lua:436
Super+Escape                   dots/.config/hypr/custom/keybinds.lua:8
Super+F                        dots/.config/hypr/hyprland/keybinds.lua:269
Super+I                        dots/.config/hypr/hyprland/keybinds.lua:442
Super+J                        dots/.config/hypr/hyprland/keybinds.lua:79
Super+K                        dots/.config/hypr/hyprland/keybinds.lua:75
Super+L                        dots/.config/hypr/hyprland/keybinds.lua:419
Super+Left                     dots/.config/hypr/hyprland/keybinds.lua:229 (loop)
Super+N                        dots/.config/hypr/hyprland/keybinds.lua:64
Super+P                        dots/.config/hypr/hyprland/keybinds.lua:273
Super+PageDown                 dots/.config/hypr/hyprland/keybinds.lua:362 (loop)
Super+PageUp                   dots/.config/hypr/hyprland/keybinds.lua:362 (loop)
Super+Q                        dots/.config/hypr/hyprland/keybinds.lua:253
Super+Return                   dots/.config/hypr/hyprland/keybinds.lua:433
Super+Right                    dots/.config/hypr/hyprland/keybinds.lua:229 (loop)
Super+S                        dots/.config/hypr/hyprland/keybinds.lua:379
Super+Shift+,                  dots/.config/hypr/hyprland/keybinds_shell_extra.lua:17
Super+Shift+/                  dots/.config/hypr/hyprland/keybinds.lua:74
Super+Shift+A                  dots/.config/hypr/hyprland/keybinds.lua:123
Super+Shift+Alt+,              dots/.config/hypr/hyprland/keybinds_shell_extra.lua:21
Super+Shift+Alt+Q              dots/.config/hypr/hyprland/keybinds.lua:254
Super+Shift+Alt+R              dots/.config/hypr/hyprland/keybinds.lua:146
Super+Shift+C                  dots/.config/hypr/hyprland/keybinds.lua:135
Super+Shift+Down               dots/.config/hypr/hyprland/keybinds.lua:243 (loop)
Super+Shift+E                  dots/.config/hypr/hyprland/keybinds.lua:56
Super+Shift+I                  dots/.config/hypr/hyprland/keybinds.lua:51
Super+Shift+K                  dots/.config/hypr/custom/keybinds.lua:7
Super+Shift+L                  dots/.config/hypr/hyprland/keybinds.lua:420
Super+Shift+Left               dots/.config/hypr/hyprland/keybinds.lua:243 (loop)
Super+Shift+PageDown           dots/.config/hypr/hyprland/keybinds.lua:311 (loop)
Super+Shift+PageUp             dots/.config/hypr/hyprland/keybinds.lua:311 (loop)
Super+Shift+R                  dots/.config/hypr/hyprland/keybinds.lua:138
Super+Shift+Right              dots/.config/hypr/hyprland/keybinds.lua:243 (loop)
Super+Shift+S                  dots/.config/hypr/hyprland/keybinds.lua:120
Super+Shift+Space              dots/.config/hypr/hyprland/keybinds.lua:265
Super+Shift+T                  dots/.config/hypr/hyprland/keybinds.lua:128
Super+Shift+Up                 dots/.config/hypr/hyprland/keybinds.lua:243 (loop)
Super+Shift+X                  dots/.config/hypr/hyprland/keybinds.lua:126
Super+Space                    dots/.config/hypr/hyprland/keybinds.lua:97
Super+T                        dots/.config/hypr/hyprland/keybinds.lua:434
Super+Tab                      dots/.config/hypr/hyprland/keybinds.lua:44
Super+Up                       dots/.config/hypr/hyprland/keybinds.lua:229 (loop)
Super+V                        dots/.config/hypr/hyprland/keybinds.lua:45
Super+W                        dots/.config/hypr/hyprland/keybinds.lua:437
Super+X                        dots/.config/hypr/hyprland/keybinds.lua:440
Super+Y                        dots/.config/hypr/hyprland/keybinds.lua:59
Super+\                        dots/.config/hypr/hyprland/keybinds.lua:61
```

Commands:

```
koompi doctor     cli/src/main.zig:14    dots/.local/bin/koompi-health
koompi preview    cli/src/main.zig:21    dots/.local/bin/koompi-quicklook
koompi reload     cli/src/main.zig:22    dots/.local/bin/koompi-reload
koompi settings   cli/src/main.zig:16    dots/.local/bin/koompi-settings
koompi signature  cli/src/main.zig:24    dots/.local/bin/koompi-signature
koompi snapshot   cli/src/main.zig:31    dots/.local/bin/koompi-snapshot
koompi toggle     cli/src/main.zig:27    dots/.local/bin/koompi-toggle
koompi update     cli/src/main.zig:13    @update (routed in main.zig)
koompi wallpaper  cli/src/main.zig:18    dots/.local/bin/koompi-wallpaper
koompi webapp     cli/src/main.zig:29    @webapp (routed in main.zig)
koompi workbench  cli/src/main.zig:23    dots/.local/bin/koompi-workbench
koompi-kiri       sdata/dist-arch/koompi-kiri/PKGBUILD:1
```

Arguments and flags the manual spells out, each read from the helper that implements it:

| In the manual | Proof |
| --- | --- |
| `koompi update --dry-run`, `--yes`, `--no-reload`, `--firmware` | `dots/.local/share/koompi/libexec/update:72-75` |
| "2 GiB free", "one run at a time" | `dots/.local/share/koompi/libexec/update-lib.sh:76-83`, `:54-57` |
| transcript, `koompi doctor --last-update` | `dots/.local/share/koompi/libexec/update:68-69`, `dots/.local/bin/koompi-health:70,122` |
| `config.json.bak-<timestamp>` | `dots/.local/share/koompi/libexec/update:64-65` |
| `koompi snapshot create --description`, `list`, `rollback <N>` | `dots/.local/bin/koompi-snapshot:20-22,107-109` |
| snapshot taken before a packaged upgrade | `dots/.local/bin/koompi-snapshot:73-84` |
| rollback does not reboot, prints the rest | `dots/.local/bin/koompi-snapshot:22-23,67-71` |
| snapshots exit 0 on non-btrfs / from-git | `dots/.local/bin/koompi-snapshot:10-13,39-45` |
| `koompi preview install`, `drive` | `dots/.local/bin/koompi-quicklook:7-8,372-376` |
| Space in Dolphin after `preview install` | `dots/.local/bin/koompi-quicklook:55-79` |
| Quick Look kinds: image, video, audio, PDF, text | `dots/.local/bin/koompi-quicklook:125-149` |
| Drive: rclone uploads, otherwise clipboard, browser either way | `dots/.local/bin/koompi-quicklook:205-229` |
| `koompi signature capture`, `from`, `list`, `install-okular` | `dots/.local/bin/koompi-signature:103-111` |
| `koompi wallpaper status`, `set <1-10> <path>`, `seed` | `dots/.local/bin/koompi-wallpaper:18,24,27` |
| `koompi toggle silent` | `dots/.local/bin/koompi-toggle:16-20,39` |
| `koompi settings bluetooth` / `power` | `dots/.local/bin/koompi-settings:32-35`, page ids from `services/SettingsPages.qml:107-110` |
| `koompi webapp install <name> <url> [icon]`, `remove` | `dots/.local/bin/koompi-webapp-install:5-7`, `koompi-webapp-remove:4` |
| favicon service is a third party | `dots/.local/bin/koompi-webapp-install:13-17` |
| `koompi workbench` needs Herdr, `--only-apps` | `dots/.local/bin/koompi-workbench:5-9` |
| `kiri model download silero-vad` / `parakeet` | `sdata/dist-arch/koompi-kiri/PKGBUILD:20-24` |

Everything else the manual asserts:

| Claim | Proof |
| --- | --- |
| Search opens on Super *release* | `dots/.config/hypr/hyprland/keybinds.lua:18-33` |
| Search prefixes `>` `~` `@` `#` `=` `?` `$` `;` `:` `/` | `dots/.config/quickshell/koompi/modules/common/Config.qml:645-657` |
| unprefixed query answers from every provider | `services/LauncherSearch.qml:309-311,462-481` |
| Enter on a clipboard entry copies, does not paste | `services/LauncherSearch.qml:345-347` |
| Launchpad is 4-finger spread, no keybind | `dots/.config/hypr/hyprland/general.lua:40-51`, `docs/navigation.md` Roles table |
| app keys open the first installed of a list | `dots/.config/hypr/hyprland/variables.lua:11-19` |
| Dolphin is the file manager KOOMPI installs | `sdata/dist-arch/koompi-kde/PKGBUILD:13`, `sdata/dist-fedora/packages.list:66` |
| ten desks | `modules/common/Config.qml:413-415` (`bar.workspaces.shown: 10`) |
| an occupied desk is filled in | `modules/koompi/bar/Workspaces.qml:61-64,139` |
| Overview closes on Escape | `modules/koompi/overview/OverviewPanel.qml:72` |
| drag a window between desks in Overview | `modules/koompi/overview/OverviewWidget.qml:243-263` |
| 4-finger horizontal = desks, up/down = Overview | `dots/.config/hypr/hyprland/general.lua:19-36` |
| snap preview: side half, corner quarter, top whole | `docs/navigation.md` "Entry points" |
| the dock ships off | `modules/common/Config.qml:475-476`, switch at `modules/settings/interface/DockSection.qml:13-16` |
| bar: star, app identity, then desks, then clock and indicators | `modules/koompi/bar/BarContent.qml:82-96,107-121,143,181` |
| clicking the app identity opens the window actions menu | `modules/koompi/bar/ActiveWindow.qml:115-122,189` |
| the program's own menus sit beside it | `modules/koompi/bar/ActiveWindow.qml:167`, `modules/koompi/bar/GlobalMenu.qml:12-21` |
| the indicator cluster is the right sidebar's button | `modules/koompi/bar/BarContent.qml:201-226` |
| coffee cup = Keep awake, moon = Night light, red mic = dictation | `modules/koompi/bar/ModeIndicators.qml:80-95` |
| update count: click runs `koompi update`, middle-click rechecks | `modules/koompi/bar/UpdateBadge.qml:13,30-31,67-77` |
| keyboard-layout indicator shows only with >1 layout (us,kh ships two) | `modules/koompi/bar/HyprlandXkbIndicator.qml:10-11`, `dots/.config/hypr/hyprland/general.lua:312` |
| opening the right panel clears the unread count | `docs/navigation.md` "Entry points" |
| `Ctrl+Super+P` cycles two panel families | `dots/.config/quickshell/koompi/shell.qml:41-61` |
| bar can go vertical or to the bottom in Settings | `modules/settings/BarConfig.qml:33-57` |
| Internet tile: click toggles, right-click lists networks | `modules/common/models/quickToggles/NetworkToggle.qml:8-16`, `modules/koompi/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml:179-191` |
| Wi-Fi list asks for a password | `modules/koompi/sidebarRight/wifiNetworks/WifiNetworkItem.qml:53-68` |
| Settings > Network has the list and a rescan | `modules/settings/NetworkConfig.qml:12-89` |
| Bluetooth tile behaves the same | `modules/koompi/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml:56-69` |
| screenshots save as well as copy, to `~/Pictures/Screenshots` | `modules/common/Config.qml:737-741`, `modules/common/Directories.qml:19` |
| recordings go to Videos | `modules/common/Config.qml:733-735`, `scripts/videos/record.sh:1-14,26-27` |
| pressing the record key again stops it | `modules/koompi/regionSelector/RegionSelection.qml:199-214`, `scripts/videos/record.sh:49-51` |
| Screen record tile in the right panel | `modules/common/Config.qml:707-708` |
| the assistant is on by default | `modules/common/Config.qml:161-162` (`policies.ai: 1`) |
| the star only shows when AI or the translator is on | `modules/koompi/bar/LeftSidebarButton.qml:14` |
| the last conversation reopens at login | `modules/common/Config.qml:174` |
| `/help /model /key /clear /save /load /attach /remember /forget /memories` | `modules/koompi/sidebarLeft/aiChat/ChatCommands.qml:37-357` |
| most models need a key, and say where to get it | `services/ai/AiModel.qml:27`, `services/ai/KeyGate.qml:34-45`, `services/ai/ModelRegistry.qml:254` |
| memory on by default, switch in Settings > AI | `modules/common/Config.qml:190-191`, `modules/settings/AiConfig.qml:299-318` |
| the translator ships off, switch under Interface | `modules/common/Config.qml:666-668`, `modules/settings/interface/SidebarsSection.qml:25-28` |
| settings page list and their order | `services/SettingsPages.qml:15-103` |
| `Super+I` toggles Settings shut | `dots/.local/bin/koompi-settings:26-29` |
| `Super+/` is generated from the binds' own descriptions | `docs/navigation.md` header |
| user keybinds live in `~/.config/hypr/custom/keybinds.lua`, never overwritten | `docs/navigation.md` Kiri section, `dots/.config/hypr/custom/keybinds.lua:1` |
| session menu: lock, sleep, logout, task manager, shutdown, reboot | `modules/koompi/sessionScreen/SessionScreen.qml:111-215` |
| lid closes to a lock unless an external monitor is attached | `dots/.local/bin/koompi-lid:3-6,33-42`, `dots/.config/hypr/hyprland/keybinds.lua:425` |
| screensaver 2 min, lock 5, screen off 10, sleep 15 | `dots/.config/hypr/hypridle.conf:19,26,31,37` |
| Keep awake stops all four idle steps | `dots/.local/bin/koompi-toggle:18`, `services/Idle.qml:62-72` (a systemd idle inhibitor, which hypridle honours) |
| Keep awake does **not** stop the lid lock, and the manual does not say it does | `dots/.local/bin/koompi-lid:3-10` blocks logind's `handle-lid-switch` suspend only; the lock is unconditional |
| `Alt+F4` answers with a notification and stays non-consuming | `dots/.config/hypr/hyprland/keybinds.lua:247-252`, `docs/navigation.md` Window section |

Every `file:line` in this report - 91 of them, including the ones in the sections below - was
machine-checked: every path resolves in this tree and every cited line is inside its file.

### 6. shellcheck

```
$ nice -n 19 ionice -c 3 shellcheck tests/test_manual_references.sh; echo "rc=$?"
rc=0
$ nice -n 19 ionice -c 3 shellcheck -x tests/test_manual_references.sh; echo "rc=$?"
rc=0
```

Both silent, both rc 0.
The only suppression in the file is one `SC2206` on the deliberate word-split of a chord on
`+`, which is the whole point of that line.

### 7. `git diff README.md` - one pointer, nothing else

```diff
diff --git a/README.md b/README.md
index e7cc8a83..a827c01f 100644
--- a/README.md
+++ b/README.md
@@ -23,9 +23,10 @@ Then log out and pick **KOOMPI** at your display manager. It is installed as
 an additional Hyprland-based session; existing KDE Plasma and GNOME sessions
 stay installed and selectable.
 
-The keyboard map, the gestures, and which panel owns what are in
-[`docs/navigation.md`](docs/navigation.md). `Super+/` shows the same bindings
-from inside the session.
+New to it? Read [`docs/manual/`](docs/manual/README.md), which starts with
+coming from Mac or Windows. The keyboard map, the gestures, and which panel owns
+what are specified in [`docs/navigation.md`](docs/navigation.md). `Super+/` shows
+the same bindings from inside the session.
 
 ## What `./setup` does
 
```

One hunk, three lines changed into four. Nothing else in README.md moved.

## Dropped chapters

**Printing.** The tree ships no printing.
No CUPS and no `print-manager` in any `sdata/dist-*/packages.list`, and no print surface anywhere in the shell.
A case-insensitive grep for `cups|print-manager|printer|printing` across `sdata/`, `dots/`, `setup`, `cli/` and `install.sh` finds nothing to do with paper.
Every hit is a coincidence: `dots/.config/hypr/hyprland/scripts/fuzzel-emoji.txt:1099` is the printer emoji, `dots/.config/fish/config.fish:21` is a comment about printing to a terminal, and the rest - `services/SearchBench.qml:75` and the AI files - are all the identifier `printErrors`.
A chapter would have documented a feature we do not have.

**USB drives.** Nothing in the shell touches removable media.
A grep for `udisks`, `removable`, `/run/media` and `mount -o` across `services/` and `modules/` returns nothing at all.
`koompi preview drive` is Google Drive, not a USB drive.
Mounting a stick belongs to Dolphin, and Dolphin is not ours to document.
Chapter 06 covers files and says nothing about USB.

**Backups as a thing separate from snapshots.** There is no backup tool in the tree.
`koompi snapshot` is btrfs snapshots over snapper, and the pre-update snapshot is taken by
`koompi update` itself, so the two belong in one chapter. That is chapter 10.

Eleven chapters remain, against the cap of twelve.

## Findings: the tree contradicts itself

Out of scope to fix here, per the job. All three are in the guided tour, which is the first
thing a new user reads, and all three teach a pointer or a gesture the code does not have.

**1. The tour says right-click for the window actions menu; the code says left.**
`modules/koompi/tour/steps.js:78` reads "Right-click the name of the program in the top
strip." `modules/koompi/bar/ActiveWindow.qml:115-122` is a bare `TapHandler`, whose
`acceptedButtons` defaults to the left button, and `docs/navigation.md` states the same:
"Left-clicking the icon, app name, and title opens close, float, fullscreen, pin, and move to
workspace", with "Right-click on the identity stays free." Following the tour does nothing.

**2. The tour says left-click for the program's own menus; that is a different widget.**
`modules/koompi/tour/steps.js:85` reads "Left-click that same name and the program's own menus ... drop down."
The global menu is a separate item beside the identity block
(`modules/koompi/bar/ActiveWindow.qml:167`, `modules/koompi/bar/GlobalMenu.qml`) with its own
click targets. Left-clicking the name opens the window actions menu, per finding 1. Steps 10
and 11 have the two targets swapped.

**3. The tour teaches a three-finger workspace swipe that is bound to something else.**
`modules/koompi/tour/steps.js:92` reads "Three fingers left or right moves between desks."
`dots/.config/hypr/hyprland/general.lua:9-13` binds the 3-finger swipe to `move`, which moves
the window. Desks are the 4-finger horizontal swipe, at `dots/.config/hypr/hyprland/general.lua:19-23`. A student
following the tour drags a window across the screen and does not change desk.

None is a crash and none loses data; each is a first-run instruction that does not work.
Fixing them is three string edits in `steps.js` and belongs in a job that owns that file.

## Two things the manual deliberately does not claim

The dock is described as shipping switched off, because it does
(`modules/common/Config.qml:475-476`). The tour never mentions it and `docs/navigation.md`
only refers to it in passing, so a reader who has heard KOOMPI has a dock now has an answer.

Dictation is described as needing `koompi-kiri` and a downloaded model, because the binds in
`dots/.config/hypr/custom/keybinds.lua` call a `kiri` binary that a from-git install does not
put there - `koompi-kiri` is an Arch package pulled in by `koompi-apps`
(`sdata/dist-arch/koompi-apps/PKGBUILD:107`), and its own PKGBUILD says the models are
downloaded by hand. Promising working dictation would have been the exact failure the job
warns about.

## What I own, and what I did not touch

Written: `docs/manual/*.md` (eleven chapters plus the index), `tests/test_manual_references.sh`.
Edited: the pointer at `README.md:26-28` and nothing else in that file.
Untouched: `docs/navigation.md`, `docs/conventions.md`, `docs/agents/**`, every shell file,
`modules/koompi/tour/steps.js`.

## Commits

```
f68a989a tests: fail when the manual names a keybind or command we do not ship
49bb7bb0 docs: send a new user to the manual, keep navigation.md for us
e25926b5 docs: a manual for the person using KOOMPI, not the person building it
```

## What still needs Rithy

The voice, line by line. Everything above is a factual claim I can defend at a `file:line`;
none of it is a claim that the register is right. The chapters read as short second-person
declaratives with plain dashes and no hedging, which is VOICE.md's terser technical mode, but
VOICE.md itself says to ask which register a technical document wants. I did not ask, so this
ships as a draft.
