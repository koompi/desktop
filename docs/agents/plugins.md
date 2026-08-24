# Plugins

Two unrelated things share the name "plugin" in this repo. Don't conflate them.

## `plugins/` — Hyprland gesture plugin (real, built)

`plugins/koompi-swipe-progress/` is a C++ Hyprland plugin (`main.cpp`, a `Makefile`,
a `rebuild` script) — native Hyprland plugin API, unrelated to the Quickshell shell
or to any shell-widget concept. If you're asked to add a Hyprland-level gesture or
compositor behavior that can't be expressed in the `hl.*` Lua bridge
(see `docs/agents/hyprland.md`), this is the precedent to follow.

## Shell-widget plugin ("clone-to-fork") — planned, not landed

**Not yet implemented.** No `PluginSlot.qml` and no `koompi-plugin` command exist in
the tree today — confirmed by grep. `BarContent.qml` still statically imports and
inline-instantiates every bar widget; there's no registry or indirection layer to
fork one widget into user space without editing the package file directly.

The planned shape (Stream G, PoC scoped to one widget):

- `PluginSlot.qml` under `modules/common/` wraps a widget call site (the `ClockWidget`
  instantiation in `BarContent.qml`) so a user can redirect it to a forked copy in
  user space without editing the package file.
- `koompi-plugin clone <id>` performs the fork.
- IPC to the forked widget is rerouted transparently through the slot.

This is explicitly a proof of concept for one widget, not a general plugin system —
don't extrapolate a wider API surface from it once it lands. Until it lands, a user
or agent wanting to customize a bar widget has to edit `BarContent.qml` directly and
accept that an update will overwrite the change (see `docs/agents/SKILL.md`'s
ownership table).
