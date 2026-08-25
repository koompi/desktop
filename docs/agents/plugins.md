# Plugins

Two unrelated things share the name "plugin" in this repo. Don't conflate them.

## `plugins/` — Hyprland gesture plugin (real, built)

`plugins/koompi-swipe-progress/` is a C++ Hyprland plugin (`main.cpp`, a `Makefile`,
a `rebuild` script) — native Hyprland plugin API, unrelated to the Quickshell shell
or to any shell-widget concept. If you're asked to add a Hyprland-level gesture or
compositor behavior that can't be expressed in the `hl.*` Lua bridge
(see `docs/agents/hyprland.md`), this is the precedent to follow.

## Shell-widget plugin ("clone-to-fork") — real, PoC scoped to one widget

`PluginSlot.qml` (`dots/.config/quickshell/koompi/modules/common/PluginSlot.qml`) is a
`Loader` that wraps a widget call site: it loads
`~/.config/koompi/plugins/<pluginId>/Widget.qml` when that file exists and otherwise
instantiates the shipped `builtin` component. File presence is the only signal — no
registry, no ordering, no enable state (`PluginSlot.qml:5-8`). A missing or broken
`Widget.qml` resolves to `Loader.Error` and falls back to the builtin
(`PluginSlot.qml:23-28`), so a bad fork cannot take the bar down.

Exactly one slot exists: the clock, `modules/koompi/bar/BarContent.qml:179-184`,
`pluginId: "koompi.clock"`. Every other bar widget is still instantiated inline, so
forking one of those still means editing `BarContent.qml` and losing the edit on the
next update (see `docs/agents/SKILL.md`'s ownership table).

`koompi-plugin` (`dots/.local/bin/koompi-plugin`, also `koompi plugin ...` via
`cli/src/main.zig:28`) manages the plugins directory:

- `list` — one line per plugin: id, `enabled`/`disabled`, manifest `name`.
- `clone <builtin-id>` — only `koompi.clock` (`koompi-plugin:88-98`). Copies
  `ClockWidget.qml` to `Widget.qml` and `ClockWidgetPopup.qml` under its own name (QML
  resolves the popup by same-directory type name, so the filename must not change),
  from `~/.config/quickshell/koompi` or, failing that, `/etc/xdg/quickshell/koompi`,
  then writes `manifest.json`. Refuses if the id already exists enabled or disabled.
- `enable <id>` / `disable <id>` — rename `<id>` ⇄ `<id>.disabled`.
- `remove <id>` — `rm -rf` both forms.
- `validate <id>` — `manifest.json` is a JSON object, `schemaVersion` is `1`, `id`
  matches the directory, `entryPoints["bar-widget"]` names an existing file. Needs `jq`.

Layout after `koompi plugin clone koompi.clock`:

```
~/.config/koompi/plugins/
  koompi.clock/                 (or koompi.clock.disabled/ after `disable`)
    manifest.json               {"schemaVersion":1,"id":"koompi.clock","name":"Clock",
                                 "kinds":["bar-widget"],"entryPoints":{"bar-widget":"Widget.qml"}}
    Widget.qml                  your copy of ClockWidget.qml — edit this
    ClockWidgetPopup.qml        unchanged copy, referenced by Widget.qml
```

`KOOMPI_PLUGINS_DIR` and `KOOMPI_SHELL_DIR` override the two directories for tests.

This is explicitly a proof of concept for one widget, not a general plugin system —
don't extrapolate a wider API surface from it.

## Not implemented

- `clone` of anything but `koompi.clock` dies (`koompi-plugin:95-97`); there is no
  second `PluginSlot` in `BarContent.qml` to fork into.
- `PluginSlot` never reads `manifest.json`: the entry point is hard-coded to
  `Widget.qml` (`PluginSlot.qml:19`). `kinds` and `entryPoints` are consumed only by
  `list` and `validate`, so today they are metadata, not a contract.
- No IPC rerouting through the slot. `PluginSlot.qml` is the 35-line `Loader` above and
  nothing else; a fork gets whatever the copied QML imports give it, unchanged
  (`koompi-plugin:110` copies the file verbatim).
- No live reload. `source` is bound to `pluginId` alone (`PluginSlot.qml:21`), so
  `clone`, `enable`, `disable`, and `remove` take effect on the next shell start —
  run `koompi reload` afterwards; `koompi-plugin` does not do it for you.
