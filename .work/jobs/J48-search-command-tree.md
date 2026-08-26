# J48 — Command tree inside Search (O05)

`.work/OMARCHY-AUDIT.md` row O05, the audit's own "single biggest UX gap": everything `koompi`
can do should be reachable by typing three letters, gated by what the machine has.
Today `services/LauncherSearch.qml:40-64` loads flat executables out of `~/.config/koompi/actions/`
and we ship **none**; `:66-125` `searchActions` is a small hardcoded list with no metadata,
no conditions and no grouping.

## The shape (Rithy, 2026-08-26): hybrid

- One flat index of every leaf. Three letters always wins, and a leaf shows its group as a
  trailing label on the row (`Night light   off   · Toggles`).
- Groups are headings, not levels. There is **no drilling and no back key**.
- The grouped view is the **empty state of the action scope** (`Config.options.search.prefix.action`,
  which already exists at `LauncherSearch.qml:17` and already has `scopeHints` machinery at `:285-311`).
  Leaves still match in the unprefixed flat search, mixed with apps, so nothing is hidden behind a prefix.
- The unprefixed empty state stays what it is: recent apps (`recentResults()`, `:319-322`).
  Do not replace it. Rithy's sketch showed groups on an empty query; the action scope is where that
  lands without taking recents away — say so in your report if you disagree, do not change it silently.

## The file-length rule

`dots/.config/quickshell/koompi/services/LauncherSearch.qml` is on `tests/file-length-allow.txt:21`
at **508 lines**. It must not exceed 508. Put the tree in a new sibling — `services/CommandTree.qml`
plus a `services/commandTree/` directory, the pattern every other service here uses (`ai/`,
`network/`, `hyprlandKeybinds/`) — and wire it into LauncherSearch in as few lines as possible,
moving code out if you need the room. Every new QML file stays ≤ 400 lines, JS ≤ 300.

## Files you own

- new `dots/.config/quickshell/koompi/services/CommandTree.qml`
- new `dots/.config/quickshell/koompi/services/commandTree/**` (entry data, the condition runner)
- `dots/.config/quickshell/koompi/services/LauncherSearch.qml` (≤ 508 lines, wiring only)
- `dots/.config/quickshell/koompi/modules/koompi/overview/SearchWidget.qml` and `SearchItem.qml`
  (group headings and the state column only; leave every other behaviour alone)
- new `tests/test_search_commands.sh`
- `docs/navigation.md` — the Search section only, if the behaviour it describes changed

Not yours: `Config.qml`, the waffle start menu, `SearchBar.qml`, `SearchPanel.qml`, keybinds.

## Do

1. Read `~/.tmp/omarchy/default/omarchy/omarchy-menu.jsonc` for the data model it settled on
   (`when` / `checked` / `disabled` per row) and `docs/menu.md` for the user overlay. Take the model,
   not the file format: ours is QML/JS, and a JSON file the shell has to shell out to evaluate is
   the wrong trade.
2. Define an entry: id, label, group, an `execute`, an optional `when` (show the row at all), an
   optional `state` (the right-hand text: `off`, `on`, `reader found`), and keywords for the fuzzy match.
   Conditions must be **cheap and non-blocking** — read existing singletons (`Idle`, `Hyprsunset`,
   `Notifications`, `Battery`, `Updates`, `ChargeLimit`, …) wherever the state already lives. A
   condition that has to spawn a process may only do so through an existing service's already-polled
   property. Never block the UI thread; never poll on a timer you introduce.
3. Ship the first set of entries — **15 to 20, no more** — chosen from what already exists and is
   verifiable: night light, keep awake, do-not-disturb / notifications, screensaver, OSD-worthy
   toggles, text size, snapshot create, update, reload, crash report, fingerprint setup (gated on
   `koompi-hw-fingerprint`), hibernate (gated on the J36 predicate), factory reset only if J38 has
   landed on main by the time you start. Each entry cites the command or service it drives, at a
   `file:line`, in your report. An entry you cannot verify does not ship.
4. Grouped empty state for the action scope; flat results with a group label otherwise. Keyboard
   behaviour and Enter-to-run must be exactly what Search already does — you are adding rows, not a mode.
5. Rows that are unavailable are **absent**, not greyed, unless the greyed row teaches something
   (a fingerprint row on a machine with no reader teaches nothing; omit it).
6. `tests/test_search_commands.sh`: a headless `qs` probe in the style of
   `tests/test_ai_model_picker.sh`. Assert the entry set loads, every entry has a group and a
   label, `when` false removes the row, the flat query "nig" reaches night light, the action-scope
   empty state groups, and no entry's id collides.
7. `qmllint` clean (0 errors) on every file you touch; `bash tests/test_file_length.sh` green.

## Acceptance

Paste real output for each:

1. `bash tests/test_search_commands.sh` — every PASS, rc 0.
2. `qmllint` on each touched file, 0 errors.
3. `wc -l` on every file you created or touched, against the caps (LauncherSearch ≤ 508).
4. `bash tests/test_file_length.sh` and `bash tests/run.sh` tails.
5. The entry table: id, group, `when`, `state`, and the `file:line` of the thing it drives.
6. A headless capture of the action-scope empty state and of the query `nig`, and say what you see.

## Out of scope

- New keybinds, a new panel, a new prefix, changing what an unprefixed empty query shows.
- The user overlay file (`~/.config/koompi/commands.json` or similar). Design the entry list so an
  overlay can be added later; do not build it.
- More than 20 entries. The rest is a follow-up job, and a fat first set is how this one overruns.
- Anything in the waffle start menu.

## Stop conditions

- A condition can only be answered by spawning a process on every keystroke → stop and report;
  that is a service-level change and the lead decides it.
- LauncherSearch.qml cannot stay at or under 508 lines → stop and report before you exceed it.
- The grouped empty state would cost the recent-apps view → stop; that is Rithy's call, not yours.
