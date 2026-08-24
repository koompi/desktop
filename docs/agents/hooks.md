# Hooks

**Not yet implemented.** There is no `koompi-hook` command and no extension-point
mechanism in the codebase today — confirmed by grep for `koompi-hook` across
`dots/.local/bin/koompi-theme` and `dots/.local/share/koompi/libexec/update`, both
empty. If you're looking for a way to react to a theme change or an update from
outside the package, it doesn't exist yet; don't invent a call site for it.

## Planned convention (Stream B, not landed)

The plan is `koompi-hook <event>` dispatching every executable under
`~/.config/koompi/hooks/<event>/`, with two events:

- `theme-set` — fired from `dots/.local/bin/koompi-theme` after a successful
  branch, once `koompi-theme` stops tail-calling `exec "$SWITCHWALL" ...` (today it
  does, so nothing runs after — see the file itself).
- `post-update` — fired once from `dots/.local/share/koompi/libexec/update`'s
  `main()`, after either the packaged or from-git update branch completes.

Once this lands, this file documents the real command, its event list, and the
`~/.config/koompi/hooks/<event>/` script contract. Until then, treat any mention of
hooks elsewhere in this repo's docs as forward-looking, not current.
