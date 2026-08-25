# Hooks

`koompi-hook <event> [-- NAME=value ...]` (`dots/.local/bin/koompi-hook`) runs every
executable file in `~/.config/koompi/hooks/<event>/` in sorted order. It is also
reachable as `koompi hook ...` (`cli/src/main.zig:26`). KOOMPI's own tools call it
after the thing already happened, so a user or a script can react to a theme change
or an update without editing package files. Don't invent new events casually — there
are four, and each has exactly one call site.

## Events fired today

- `theme-set` — from `dots/.local/bin/koompi-theme:51-69`, after `switchwall.sh`
  returned 0. What changed rides along as environment: `KOOMPI_HOOK_MODE` (`dark` or
  `light`), `KOOMPI_HOOK_SCHEME`, or `KOOMPI_HOOK_COLOR`, one per subcommand;
  `regenerate` sets none of them.
- `post-update` — from `dots/.local/share/koompi/libexec/update:236`, once per run
  after either the packaged or the from-git branch completed. Carries
  `KOOMPI_HOOK_UPDATE_METHOD=packaged` or `=from-git`.
- `battery-low` — from the shell, `services/Battery.qml` (`fireHook`), once when the
  battery falls to `battery.low` (config) while not charging, beside the "Low battery"
  toast. Carries `KOOMPI_HOOK_BATTERY_PERCENT=<0..100>`.
- `battery-critical` — same file, same shape, at `battery.critical`. Neither fires on
  the way back up, nor again while the level stays under the line.

The two shell-script call sites are guarded with `command -v koompi-hook`, so a machine
that doesn't have the tool on `PATH` skips hooks silently. That was every KOOMPI OS
install until `koompi-shell` 1.1-2 packaged it (`sdata/dist-arch/koompi-shell/PKGBUILD`,
`_tools`). The shell's `Quickshell.execDetached` has no such guard: a missing tool is
one warning in the shell log.

## Script contract

- Directory: `${XDG_CONFIG_HOME:-~/.config}/koompi/hooks/<event>/`. Any executable
  regular file counts; non-executables and subdirectories are skipped
  (`koompi-hook:74-75`). A missing directory is a silent no-op.
- Order: glob order, so name hooks `10-foo`, `20-bar` if it matters.
- Environment: the caller's, plus `KOOMPI_HOOK_EVENT=<event>`, plus any `NAME=value`
  given after `--` (validated as shell identifiers, `koompi-hook:54`). The shipped call
  sites pass their extras as exported prefixes instead (`KOOMPI_HOOK_MODE="$m"
  koompi-hook theme-set`); either form reaches the hook the same way.
- Failure: a hook that exits non-zero is appended to
  `~/.local/state/koompi/logs/hooks.log` as `<iso-date> event=… hook=… exit=N` and the
  next hook still runs (`koompi-hook:76-82`). `koompi-hook` itself exits 0 unless its
  own arguments are wrong: no event, an event name outside
  `^[A-Za-z0-9][A-Za-z0-9_-]*$`, or an extra argument that isn't `NAME=value`.
- Output: nothing on success. A hook's own stdout/stderr goes wherever the caller's
  goes.

## Adding a call site

Fire after the change is durable, never before; guard with `command -v koompi-hook`;
pass what changed as environment rather than making the hook rediscover it; and add the
event to the `Events KOOMPI fires today` block in `koompi-hook`'s usage text
(`koompi-hook:28-30`) and to this file.

## Not implemented

- Only the four events above exist. Wallpaper changes (`koompi-wallpaper`), login, lock,
  and display changes fire nothing — grep `koompi-hook` in `dots/` returns only
  `koompi-theme`, `libexec/update` and `services/Battery.qml`.
- No timeout: hooks run synchronously (`koompi-hook:77`), so a hanging hook hangs
  `koompi theme` or `koompi update` with it.
- No listing or dry-run subcommand; `ls ~/.config/koompi/hooks/*/` is the inventory.
