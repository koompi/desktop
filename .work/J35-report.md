# J35 report — Cheatsheet rows searchable and executable (O13)

Branch `j35-cheatsheet-executable`. Session locked the whole time (`loginctl ... LockedHint=yes`), so nothing here touched the live shell.

## What the machine actually does (changes the design in the brief)

- Every one of the 432 binds in `hyprctl binds` is `dispatcher: __lua`, `arg: <index>`. The config is Lua (`~/.config/hypr/hyprland.lua`); the index is Hyprland's registry slot, not something a client can fire.
- Under a Lua config `hyprctl dispatch` evaluates its argument as Lua: `hyprctl dispatch exec true`, `hyprctl dispatch global quickshell:cheatsheetToggle` and `hyprctl dispatch __lua 82` all fail with `')' expected near ...`; `hyprctl dispatch 'hl.dsp.global("quickshell:cheatsheetToggle")'` returns `ok` (tested live, it toggled the sheet under the lock).
- `HL.Keybind` (`/usr/share/hypr/stubs/hl.meta.lua:640`) has `is_enabled/set_enabled/unbind/remove` and no way to trigger it; `hl` has no bind listing.
- So the brief's `hyprctl dispatch <dispatcher> <arg>` is dead on this machine. What works is what Omarchy does (`omarchy-menu-keybindings:6-83`): replay the config's bind files under a recording `hl` and keep the expression each bind was declared with.

## Files

| file | lines |
| --- | --- |
| `services/HyprlandKeybinds.qml` | 253 |
| `services/hyprlandKeybinds/recorder.lua` (new; the layout `services/hyprlandAntiFlashbangShader/*.glsl` and `services/gCloud/*.sh` already use) | 189 |
| `modules/koompi/cheatsheet/CheatsheetKeybinds.qml` | 133 |
| `modules/koompi/cheatsheet/CheatsheetKeybindsCategory.qml` | 244 |
| `modules/koompi/cheatsheet/Cheatsheet.qml` | 243 |
| `tests/test_cheatsheet_dispatch.sh` (new) | 377 |

The recorder is one file outside the owned list, next to the service that runs it; it needed a home that is not a UI directory.

## Do

1. `HyprlandKeybinds`:
   - `recorder.lua` runs under `lua` (a dependency of the `hyprland` package, so present wherever the config is Lua) with `package.path` on the config dir and the modules `hyprland.lua` requires for binds (`hyprland.keybinds`, `hyprland.keybinds_notifications`, `custom.keybinds`, same order; a missing file is skipped like `hyprland.lua` does, none found is an error). `hl.dsp.*` is a proxy that serialises the call (`hl.dsp.window.move({ direction = "r" })`), `hl.bind` records `modmask, key, submap, description, expr`, every other `hl.*` is a no-op; `hl.exec_cmd`/`hl.env` run nothing. Config dir: `$HYPRLAND_CONFIG`'s directory (Hyprland's own override) else `$XDG_CONFIG_HOME/hypr`.
   - Records are joined to `hyprctl binds` rows on `modmask|key|submap|description` (key = last token of the chord, `code:N` from keycode when empty). Real config: 432/432 recorded, 333 unique keys, 133 of the 159 described binds dispatchable.
   - `dispatchable(bind)`: false for `catchall`, a submap, an empty dispatcher, `bindm`, and a `__lua` bind with no recovered expression (closures: zoom in/out, the numbered workspace binds that go through `workspace_in_group`, the VM submap toggle; `mouse = true` drags; stale rows).
   - `dispatchArgv`/`dispatch`: `__lua` → `["hyprctl","dispatch", expr]`; anything else → `["hyprctl","dispatch", dispatcher, arg]` (classic config; `exec` and `global` fall in here as `hyprctl dispatch exec <cmd>` / `hyprctl dispatch global <name>`). Always through `hyprctl`, never `koompi-launch`: an exec bind replays exactly the command the key runs, and the config already wraps in `koompi-launch` where it wants to (`app()` in keybinds.lua) — wrapping again would double it. `Quickshell.execDetached`, so a PATH shim can see the argv.
   - `modifiersOf`, `keyOf`, `searchText` moved/added on the service; `CheatsheetKeybindsCategory` uses `modifiersOf` instead of its own copy.
2. `BindLine` is a `Rectangle` with a `MouseArea`: hover → `colLayer1Hover`, pointer cursor, click → `activate` = `HyprlandKeybinds.dispatch(bind)` then `GlobalStates.cheatsheetOpen = false`. Non-dispatchable rows: MouseArea disabled, no hover, arrow cursor.
3. Search field (`ToolbarTextField`) at the top of the keybinds page. `Fuzzy.go` over `searchText` (chord + key + description, and the category through the description prefix) with `key: "name"`, `threshold: 0.5` (the floor Search uses for window titles; descriptions are long enough to need it). Matching rows stay in their category columns; empty categories hide. The best dispatchable match is highlighted (`colSecondaryContainer`) and Enter runs it, only while the keybinds page is the current tab. Escape with text clears (accepted); Escape on an empty field bubbles to the sheet's handler, which closes. On open the field is cleared and takes focus; `closeButton` no longer binds `focus`. Field focus verified in the probe (`fieldFocus=true`); keyboard delivery could not be tried live, see Acceptance 2.
4. Test below.

## Acceptance

### 1. New test and suite tail

```
$ nice -n 19 ionice -c 3 bash tests/test_cheatsheet_dispatch.sh
ok   qmllint: 6 cheatsheet files and HyprlandKeybinds.qml parse without errors
ok   recorder: 8 fixture binds recorded with the expressions they were declared with
ok   recorder: a broken module is reported and the rest is kept
ok   recorder: a directory with no bind module is an error, not an empty config
PASS hyprctl binds and the recorder both answered  binds=12 recorded=6
PASS 12 binds parsed  12
PASS classic exec is dispatchable as hyprctl dispatch exec <arg>  ["hyprctl","dispatch","exec","kitty"]
PASS classic workspace builds hyprctl dispatch workspace 3  ["hyprctl","dispatch","workspace","3"]
PASS classic global builds hyprctl dispatch global <name>  ["hyprctl","dispatch","global","quickshell:cheatsheetToggle"]
PASS a catchall submap row is not dispatchable
PASS a Lua exec bind replays the exec_cmd it was declared with, unwrapped  ["hyprctl","dispatch","hl.dsp.exec_cmd(\"koompi-launch --id brave brave\")"]
PASS a Lua global bind with a keycode chord matches on the last token  ["hyprctl","dispatch","hl.dsp.global(\"quickshell:workspaceOne\")"]
PASS a namespaced dispatcher keeps its table argument  ["hyprctl","dispatch","hl.dsp.window.move({ direction = \"r\" })"]
PASS custom.keybinds binds are recovered too  ["hyprctl","dispatch","hl.dsp.exec_cmd(\"kiri voice\", { float = true })"]
PASS a Lua closure is not dispatchable  expr=""
PASS a mouse drag is not dispatchable  expr=""
PASS a submap bind is not dispatchable
PASS a bind the source no longer declares is not dispatchable  expr=""
PASS searchText carries chord, key and description  Super Alt code:10 Workspace: One
PASS modifiersOf follows the user-facing order  ["Ctrl","Shift","Alt"]
PASS keybindCategories come from the merged list  ["App","Workspace","Shell","Window","Screen","Kiri"]
PASS dispatch returns true for a runnable bind and false otherwise
PASS the shim saw exactly the two runnable dispatches, argv intact  ["dispatch\texec\tkitty","dispatch\thl.dsp.exec_cmd(\"koompi-launch --id brave brave\")"]
PROBE OK
ok: HyprlandKeybinds merges hyprctl binds with the recorded Lua declarations and dispatches through hyprctl
```

```
$ nice -n 19 ionice -c 3 ./tests/run.sh   (tail)
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

84 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

87 tests, was 86: baseline +1. The three skips are the pre-existing ones.

### 2. Live

The live shell runs `~/.config/quickshell/koompi` (a real directory, not this worktree) and has not loaded this QML; it was not restarted. The session was also locked for the whole job, so no surface could take keyboard focus and `wtype` was never sent.

Stand-in: a `qs -p` probe that instantiates `CheatsheetKeybinds` in a `SwipeView` inside a `PanelWindow` from this worktree, with the real `hyprctl binds` and the real `~/.config/hypr` config, and a `hyprctl` shim that logs `dispatch` instead of running it. The field was filled the way keys would land (`text = "screenshot"`), the card was rendered with `grabToImage` (the layer sits under the lock, so `grim` shows only the lock screen), and the field's own `accepted` signal (Enter) was fired:

```
PROBE binds=432 described=159 dispatchable=133 fieldFocus=true recorded=333
PROBE query="screenshot" matches=3 first="Utilities: Screenshot (region or full screen)" fieldFocus=true
      shown=["Utilities: Screenshot (region or full screen)","Utilities: Screenshot >> clipboard & file","Utilities: Screenshot whole screen >> file + clipboard"]
PROBE grab saved=true
PROBE closed
--- shim log ---
dispatch	hl.dsp.global("quickshell:regionScreenshot")
```

`/tmp/j35-cheatsheet.png`: the field with "screenshot", the Utilities column with the three rows, the first highlighted. `Print` → `hl.dsp.global("quickshell:regionScreenshot")` is what Enter ran; the sheet closed after.

Not verified live: that Hyprland delivers keys to the `OnDemand` surface on open. Escape already reaches the sheet today through the same path, and the field holds item focus inside the window (`fieldFocus=true`); the surface-level check needs an unlocked session.

### 3. Line counts

See Files above; largest is the test at 377, every QML file ≤ 253.

## Decisions to know about

- Dependency: `lua` (already a dependency of `hyprland`; `pacman -Qi hyprland` lists it). No new package.
- 26 described rows are not clickable and show no hover: the closures listed under Do 1. Making them clickable means declaring them as `hl.dsp.*` dispatchers in `keybinds.lua`, out of scope here.
- `ShortcutsConfig.qml` in settings keeps its own `modMaskToStringList`; not touched (not owned).
