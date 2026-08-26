# J48 — Command tree inside Search (O05)

Branch `j48-search-commands`, commit `374c720f`. Seventeen leaves, one flat index,
groups as headings. `LauncherSearch.qml` is still 508 lines.

## The shape, as built

Rithy's hybrid, unchanged from the contract:

- One flat index. `nig` reaches Night light in the unprefixed search, mixed with the
  apps, and the row reads `Night light   off   · Toggles`.
- The action scope (`/`) with nothing after it is the grouped view: every available
  leaf in group order, the first row of each group carrying the heading. The existing
  `/dark`, `/todo …` actions still follow underneath, so nothing that used to answer
  to `/` stopped answering.
- No drilling, no back key, no new mode. A leaf is a `LauncherSearchResult`, so Enter,
  Tab, the arrow keys and the ripple are the ones Search already had. The heading is
  drawn inside the first row of its group rather than as a row of its own, so the
  arrow keys still only ever land on a leaf.
- The empty unprefixed query is untouched: still `recentResults()`.
- A row the machine cannot run is absent. Nothing is greyed.

## Where it lives

| File | Lines | Cap |
| --- | --- | --- |
| `services/CommandTree.qml` | 122 | 400 |
| `services/commandTree/Entries.qml` | 255 | 400 |
| `services/commandTree/Conditions.qml` | 52 | 400 |
| `services/commandTree/CommandResult.qml` | 18 | 400 |
| `services/LauncherSearch.qml` | 508 | 508 |
| `modules/koompi/overview/SearchItem.qml` | 354 | 400 |
| `tests/test_search_commands.sh` | 234 | — |

`SearchWidget.qml` needed no change and got none (303 lines, untouched).

`LauncherSearch.qml` grew by nothing. The whole wiring is one line, which replaced
the line it sits on:

```diff
-        //////////////// Apps //////////////////
-        result = result.concat(appResultObjects);
+        //////// Command tree, then apps ///////
+        result = result.concat(CommandTree.results(root.query), appResultObjects);
```

`CommandResult.qml` is a `LauncherSearchResult` with three extra fields (`group`,
`heading`, `stateText`), so no file outside the ones this job owns was touched —
in particular `modules/common/models/LauncherSearchResult.qml` is unchanged.

## Acceptance

### 1. `bash tests/test_search_commands.sh` — every PASS, rc 0

`rc=0`, 46 PASS across the two probe runs, 0 FAIL, `PROBE OK` twice.
The file is shellcheck clean.

```
ok   static: LauncherSearch.qml is 508 lines, wired in one line, still answers an empty query with recents
ok   static: every new or touched QML file outside the allow-list is under 400 lines
ok   static: no timer anywhere, one one-shot probe, nothing spawned per keystroke
ok   static: a leaf is a LauncherSearchResult with group, heading and state; Enter is unchanged
ok   qmllint: the seven touched files parse without errors
--- neither a reader nor a crash report ---
PASS entries: the first set is 15 to 20 leaves  got=[true,true,17]
PASS entries: every leaf has an id, a label, a group and something to run  got=[]
PASS entries: every group is one of the declared headings  got=[]
PASS entries: no id collides  got=17
PASS entries: every optional condition is a function  got=[]
PASS when: the fingerprint row follows the reader  got=false
PASS when: the crash row follows a written report  got=false
PASS when: available is a subset of the entry set  got=[]
VIEW  flat 'nig':
VIEW     | Night light | off | Toggles
VIEW     | Dark mode | on | Toggles
PASS flat: 'nig' reaches night light first  got="Night light"
PASS flat: the row carries its group as a trailing label  got="Toggles"
PASS flat: a flat row has no heading  got=""
PASS flat: the row shows the switch's state  got=true
PASS flat: the leaves cannot crowd out the app list  got=true
PASS flat: an empty unprefixed query adds nothing, so recents stand  got=[]
PASS flat: a query already inside another scope gets no leaves  got=[0,0,0,0,0,0,0,0,0]
VIEW  action scope, empty:
VIEW    Toggles | Night light | off | 
VIEW     | Keep awake | off | 
VIEW     | Do not disturb | off | 
VIEW     | Dark mode | on | 
VIEW     | Battery charge limit | 80% | 
VIEW    Display | Text bigger | 16 px | 
VIEW     | Text smaller | 16 px | 
VIEW    Session | Start screensaver |  | 
VIEW     | Lock screen |  | 
VIEW    System | Reload desktop |  | 
VIEW     | Create system snapshot |  | 
VIEW     | Install updates |  | 
PASS grouped: every available leaf is listed  got=12
PASS grouped: the headings are the declared groups in order  got=["Toggles","Display","Session","System"]
PASS grouped: a heading opens its group and repeats nowhere  got=4
PASS grouped: a headed row does not also carry the trailing label  got=0
PASS grouped: the first heading is the first declared group  got="Toggles"
PASS scoped: '/nig' answers with the same leaf  got="Night light"
PASS scoped: a typed scope row keeps its group label  got="Toggles"
PASS row: a leaf is a LauncherSearchResult with a verb and an icon  got=["Run","bedtime","function"]
PROBE OK
--- a reader and a crash report on the machine ---
PASS entries: the first set is 15 to 20 leaves  got=[true,true,17]
PASS entries: every leaf has an id, a label, a group and something to run  got=[]
PASS entries: every group is one of the declared headings  got=[]
PASS entries: no id collides  got=17
PASS entries: every optional condition is a function  got=[]
PASS when: the fingerprint row follows the reader  got=true
PASS when: the crash row follows a written report  got=true
PASS when: available is a subset of the entry set  got=[]
VIEW  flat 'nig':
VIEW     | Night light | off | Toggles
VIEW     | Dark mode | on | Toggles
PASS flat: 'nig' reaches night light first  got="Night light"
PASS flat: the row carries its group as a trailing label  got="Toggles"
PASS flat: a flat row has no heading  got=""
PASS flat: the row shows the switch's state  got=true
PASS flat: the leaves cannot crowd out the app list  got=true
PASS flat: an empty unprefixed query adds nothing, so recents stand  got=[]
PASS flat: a query already inside another scope gets no leaves  got=[0,0,0,0,0,0,0,0,0]
VIEW  action scope, empty:
VIEW    Toggles | Night light | off | 
VIEW     | Keep awake | off | 
VIEW     | Do not disturb | off | 
VIEW     | Dark mode | on | 
VIEW     | Battery charge limit | 80% | 
VIEW    Display | Text bigger | 16 px | 
VIEW     | Text smaller | 16 px | 
VIEW    Session | Start screensaver |  | 
VIEW     | Lock screen |  | 
VIEW    System | Reload desktop |  | 
VIEW     | Create system snapshot |  | 
VIEW     | Install updates |  | 
VIEW     | Latest crash report | 1 | 
VIEW     | Set up fingerprint |  | 
PASS grouped: every available leaf is listed  got=14
PASS grouped: the headings are the declared groups in order  got=["Toggles","Display","Session","System"]
PASS grouped: a heading opens its group and repeats nowhere  got=4
PASS grouped: a headed row does not also carry the trailing label  got=0
PASS grouped: the first heading is the first declared group  got="Toggles"
PASS scoped: '/nig' answers with the same leaf  got="Night light"
PASS scoped: a typed scope row keeps its group label  got="Toggles"
PASS row: a leaf is a LauncherSearchResult with a verb and an icon  got=["Run","bedtime","function"]
PROBE OK
ok   command tree: 17 leaves load with a group and a label, no id collides, a false when removes the row, 'nig' reaches night light flat and scoped, and the action scope's empty query groups them under their headings
```

### 2. qmllint on each touched file, 0 errors

```
services/CommandTree.qml                           rc=0 errors=0 warnings=28
services/commandTree/CommandResult.qml             rc=0 errors=0 warnings=3
services/commandTree/Conditions.qml                rc=0 errors=0 warnings=4
services/commandTree/Entries.qml                   rc=0 errors=0 warnings=60
services/LauncherSearch.qml                        rc=0 errors=0 warnings=7
modules/koompi/overview/SearchItem.qml             rc=0 errors=0 warnings=151
modules/koompi/overview/SearchWidget.qml           rc=0 errors=0 warnings=60
```

Zero errors on all seven. The warnings are what this repo's isolated lint always
reports: `qs.*` will not resolve through a single symlinked import root, so every
`Appearance`, `StyledText` and `Translation` reads as unqualified. `SearchItem.qml`
is 151 warnings against 129 on `main`; every one of the 22 is an `[unqualified]` or
`[unresolved-type]` on the `Appearance`/`StyledText` references in the rows I added,
none is a new category, and the one `[redundant-optional-chaining]` is on line 104,
which is `main`'s.

### 3. `wc -l` against the caps

```
  122 dots/.config/quickshell/koompi/services/CommandTree.qml
   18 dots/.config/quickshell/koompi/services/commandTree/CommandResult.qml
   52 dots/.config/quickshell/koompi/services/commandTree/Conditions.qml
  255 dots/.config/quickshell/koompi/services/commandTree/Entries.qml
  508 dots/.config/quickshell/koompi/services/LauncherSearch.qml
  354 dots/.config/quickshell/koompi/modules/koompi/overview/SearchItem.qml
  303 dots/.config/quickshell/koompi/modules/koompi/overview/SearchWidget.qml
  234 tests/test_search_commands.sh
 1846 total
```

`LauncherSearch.qml` is exactly 508, its allow-list number, and the allow-list entry
is unchanged. Every new QML file is under 400.

### 4. `bash tests/test_file_length.sh` and `bash tests/run.sh`

```
$ bash tests/test_file_length.sh
ok: 941 files under cap, 34 allow-listed and not grown

$ bash tests/run.sh
==> test_search_commands.sh
  ok test_search_commands.sh
...
96 passed, 3 skipped, 1 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
failed: test_services_qml_bugs.sh
```

100 test files against `main`'s 99: the suite is the baseline plus this job's one
test, and `test_search_commands.sh` passes in the run. The three skips are `main`'s.

**`test_services_qml_bugs.sh` fails, and it fails the same way on `main`.** One
assertion, `L5 a successful check counts the lines`, depends on this machine's
battery: `Updates.refresh()` returns early while the pack is low and discharging
(`services/Updates.qml:38,50-53`), and the probe's own log says so.

```
 DEBUG qml: [Updates] Battery low, skipping the update check
 DEBUG qml: FAIL L5 a successful check counts the lines  count=7
 DEBUG qml: PROBE FAILED 1
```

The battery is at 19% and discharging. Run against a detached worktree of `main`,
the same test produces the same three lines and the same `rc=1`, so nothing on this
branch caused it. This branch touches neither that test nor `Updates.qml`,
`Battery.qml`, and its probe never loads `CommandTree` (`grep -c CommandTree
tests/test_services_qml_bugs.sh` is 0). An earlier run of the full suite on this
branch, before the battery dropped, was 97 passed / 3 skipped / 0 failed.

### 5. The entry table

Seventeen entries. Every `when` and every `state` reads a property a service already
keeps, except the two probed once in `Conditions.qml`; none of them spawns anything
per keystroke. `file:line` is the thing the row drives, verified in this tree.

| id | group | `when` | `state` | drives |
| --- | --- | --- | --- | --- |
| `toggles.night-light` | Toggles | — | `Hyprsunset.temperatureActive` → on/off (`services/Hyprsunset.qml:28`) | `Hyprsunset.toggleTemperature()` — `services/Hyprsunset.qml:149` |
| `toggles.keep-awake` | Toggles | — | `Idle.inhibit` → on/off (`services/Idle.qml:14`) | `Idle.toggleInhibit()` — `services/Idle.qml:38` |
| `toggles.do-not-disturb` | Toggles | — | `Notifications.silent` → on/off (`services/Notifications.qml:112`) | flips `Notifications.silent`, as the sidebar switch does — `modules/koompi/sidebarRight/notifications/NotificationList.qml:55` |
| `toggles.dark-mode` | Toggles | — | `DarkMode.dark` → on/off (`services/DarkMode.qml:18`) | `DarkMode.toggle()` — `services/DarkMode.qml:69` |
| `toggles.charge-limit` | Toggles | `ChargeLimit.supported` (`services/ChargeLimit.qml:23`) | `80%` when on, else off (`services/ChargeLimit.qml:24,26`) | `ChargeLimit.setEnabled()` — `services/ChargeLimit.qml:30` |
| `display.text-bigger` | Display | `baseSize < 24` (`dots/.local/bin/koompi-theme:25`) | `16 px` (`modules/common/Config.qml:219`) | `koompi-theme text-size N` — `dots/.local/bin/koompi-theme:40` |
| `display.text-smaller` | Display | `baseSize > 9` (`dots/.local/bin/koompi-theme:24`) | `16 px` (`modules/common/Config.qml:219`) | `koompi-theme text-size N` — `dots/.local/bin/koompi-theme:40` |
| `display.text-reset` | Display | `baseSize !== 16` (`dots/.local/bin/koompi-theme:23`) | — | `koompi-theme text-size reset` — `dots/.local/bin/koompi-theme:40` |
| `session.screensaver` | Session | — | — | sets `GlobalStates.screensaverOpen`, with `open()`'s own lock guard — `modules/koompi/screensaver/Screensaver.qml:15-21`, `GlobalStates.qml:30` |
| `session.lock` | Session | — | — | `Session.lock()` — `modules/common/functions/Session.qml:21` |
| `session.hibernate` | Session | `SessionWarnings.canHibernate` (`services/SessionWarnings.qml:16`), the session screen's own gate (`modules/koompi/sessionScreen/SessionScreen.qml:175`) | — | `Session.hibernate()` — `modules/common/functions/Session.qml:40` |
| `system.reload` | System | — | — | `koompi-reload` — `dots/.local/bin/koompi-reload:29-34` |
| `system.snapshot` | System | — | — | `koompi-snapshot create --description …` in a terminal — `dots/.local/bin/koompi-snapshot:48` |
| `system.update` | System | — | `Updates.count` when non-zero (`services/Updates.qml:24`) | `koompi update` in a terminal, the update badge's command — `modules/koompi/bar/UpdateBadge.qml:30-31`, `dots/.local/bin/koompi-update:4` |
| `system.check-updates` | System | `Updates.available`, i.e. `which checkupdates` (`services/Updates.qml:22,73-77`) | `checking` while the check runs (`services/Updates.qml:23`) | `Updates.refresh()` — `services/Updates.qml:48` |
| `system.crash-report` | System | a `*.md` report exists under `$XDG_STATE_HOME/koompi/crash` (`dots/.local/bin/koompi-crash-diagnose:34,182`) | the report count | `xdg-open` on the newest report, as the tool's own fallback does — `dots/.local/bin/koompi-crash-diagnose:226` |
| `system.fingerprint` | System | `koompi-hw-fingerprint` exits 0 (`dots/.local/bin/koompi-hw-fingerprint:2`), probed once | — | `koompi-setup-fingerprint --terminal` — `dots/.local/bin/koompi-setup-fingerprint:32`, the Settings button at `modules/settings/interface/LockScreenSection.qml:81` |

Two conditions had no singleton holding them, so `commandTree/Conditions.qml` holds
them instead: one `Process` that runs `koompi-hw-fingerprint` once at load — the same
shape as `SessionWarnings.qml:44`, which probes `CanHibernate` once — and a
`FolderListModel` on the crash folder, the same watcher `LauncherSearch` already
points at `~/.config/koompi/actions`. No timer was introduced anywhere; the test
asserts that.

**Not shipped:** factory reset. J38 is a contract on `main` (`ac3c9603`) with no
implementation, so there is nothing to drive and the row would have been a lie.

### 6. Headless capture

Two `qs -p` captures of the real `SearchItem` delegate against the real `CommandTree`,
saved under `.work/J48/`.

`.work/J48/action-scope-empty-and-nig.png` — the grouped empty state of the action
scope, then the flat `nig` result under a gap. What I see, top to bottom:

```
Toggles
   ☾  Night light                                        off
   ☕ Keep awake                                          on
   🔕 Do not disturb                                     off
   ☾  Dark mode                                          on
   🔋 Battery charge limit                               80%
Display
   A+ Text bigger                                      16 px
   A− Text smaller                                     16 px
Session
   🖵  Start screensaver
   🔒 Lock screen                                              [hovered: Run]
System
   ↻  Reload desktop
   ☁  Create system snapshot
   ⬇  Install updates
   🐞 Latest crash report                                    1
   ☝  Set up fingerprint

   ☾  Nig̲ht light                            off   · Toggles
   ☾  Dark mode                               on    · Toggles
```

Four headings in declared order, each opening its group and appearing once. The state
column is right-aligned and carries live values, not labels: `on`/`off` read off the
services, `80%` off `ChargeLimit.endThreshold`, `16 px` off `Config`, `1` for the one
crash report seeded in the probe's `XDG_STATE_HOME`. `Hibernate`, `Check for updates`
and `Reset text size` are simply absent — this machine says `CanHibernate` no, the
probe never reached `which checkupdates`, and the text size is already the default.

The `Lock screen` row happened to be under the pointer when the frame was grabbed,
which is the useful accident: the highlight covers that row only, starting *below*
the `Session` heading and stopping *above* the `System` one, and the `Run` verb
appears on it. That is the heading living inside its group's first row, and the
keyboard never landing on a heading.

`.work/J48/flat-nig-mixed-with-apps.png` — the same `nig` query through
`LauncherSearch.results`, so app rows and the fallbacks are in the frame:

```
   ☾  Nig̲ht light                            off   · Toggles
   ☾  Dark mode                              on    · Toggles
   ▨  Open Design (default)
   🖌 GNU Image Manipulation Program
   🐧 Fcitx 5 Configuration
   🌐 Advanced Network Configuration
Command      nig
Math result  in g
Web search   nig
```

The two leaves rank above the apps, which is what "three letters always wins" has to
mean in a flat list. App rows draw exactly as before: no state column, no trailing
group, no heading, and the fuzzy underline still on the app names. The same
integration through `LauncherSearch`, printed rather than drawn:

```
ROWS  [":Night light",":Dark mode","Command:nig","Math result:","Web search:nig"]
SCOPE ["Night light","Keep awake","Do not disturb","Dark mode","Text bigger",
       "Text smaller","Start screensaver","Lock screen","Reload desktop",
       "Create system snapshot","Install updates","/accentcolor","/dark","/light",
       "/randomwallpaper","/superpaste","/todo","/wallpaper","/wipeclipboard","/"]
EMPTY []
```

`SCOPE` is the point about not breaking what was there: the command tree, then the
eight existing `/` actions, then the default rows. `EMPTY` is empty because the probe
has no launch history, which is `recentResults()` behaving.

## Decisions and notes

- **The grouped view is the action scope's empty state**, as the contract directed,
  and recents keep the unprefixed empty query. I agree with that call and did not
  change it.
- **`LauncherSearchResult` was not touched.** The state and group columns needed two
  fields the model does not have; rather than edit a file this job does not own, the
  row type is `commandTree/CommandResult.qml`, a `LauncherSearchResult` with the three
  extra properties. `SearchItem` reads them through a `var` alias so the lookup is
  dynamic and every other provider's rows are unaffected.
- **A label hit outranks a keyword hit.** The first cut indexed label and keywords as
  one string, and `nig` answered with Dark mode, whose keywords mention the night. Two
  passes now: labels first, then keywords for whatever the first pass missed.
- **Leaves cannot flood the list.** Outside the action scope the matches are capped at
  five and floored at a fuzzy score of 0.4; inside it they are uncapped.
- **A query already inside another scope gets no leaves.** `>nig`, `#nig`, `~nig` and
  the rest return nothing from the tree. That was already true by accident, since no
  label contains a `$` or a `?`; `CommandTree.foreignPrefixes` now says it on purpose.
- **Two commands run in a terminal**, not detached: `koompi-snapshot create` and
  `koompi update`. Both print the thing you asked for and both can want a password, so
  a detached run would have been a row that silently does nothing. The terminal is
  `Config.options.apps.terminal`, the one `LauncherSearch` already hands a sudo command.
- **No stop condition was hit.** No condition needed a per-keystroke process,
  `LauncherSearch` stayed at 508, and recents were not taken away.

## Out of scope, untouched

No new keybind, panel or prefix. No user overlay file — entries carry a stable `id` so
one can be layered later, but nothing reads a `commands.json`. Nothing in the waffle
start menu. `Config.qml`, `SearchBar.qml`, `SearchPanel.qml` and the keybinds are
unchanged.
