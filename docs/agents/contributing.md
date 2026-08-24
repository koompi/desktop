# Porting upstream changes

Full detail is in `UPSTREAM.md` — this is the agent-facing summary of the workflow.

## Why there's no `git merge`

This repo's content descends from end-4/dots-hyprland (GPL-3.0, and so is this repo —
a derivative stays GPL-3.0), but the git history is not shared: the tree was restarted
from a single root commit, so `git merge end-4/main` doesn't work. Every upstream fix
has to be reviewed and ported by hand.

## Workflow

```sh
git remote add end-4 https://github.com/end-4/dots-hyprland.git   # once
git fetch end-4
git log --oneline 614f02e6..end-4/main                 # review what's new
git diff 614f02e6..end-4/main -- <upstream/path>       # read one change
```

Then apply the change to the corresponding `dots/.config/quickshell/koompi/...` file
by hand (the `ii → koompi` rename means upstream's `modules/...` maps to
`modules/koompi/...` here). When a port is done, move the marker commit
(`614f02e6` today) forward in `UPSTREAM.md` to the commit you reviewed up to, so the
next person knows where to resume.

The full pre-restart history (end-4's commits plus KOOMPI's, renames recorded as
`R100`) is preserved read-only at
<https://github.com/koompi/koompi-desktop-history> if you need to trace where a line
came from.

## KOOMPI-owned surfaces

Porting only stays affordable if KOOMPI's own changes stay off inherited files. Keep
new work on these surfaces instead:

- The `hl.*` Hyprland Lua config bridge (`dots/.config/hypr/`) — see
  `docs/agents/hyprland.md`.
- OS integration: KOOMPI detection in `services/SystemInfo.qml`, the user-actions
  loader in `services/LauncherSearch.qml`, config-path rewrites.
- Branding: wallpapers, the brand-green accent, KOOMPI bar-layout tweaks, the
  default theme, attribution.
- The added AI providers (DeepSeek, GLM, MiniMax, Kimi).
- The Zig installer (`installer/`) and the Arch packaging tree (`sdata/dist-arch/`).

Every edit to an inherited file (most of `dots/.config/quickshell/koompi/`) makes the
next port harder to read — prefer one of the surfaces above, or a `custom/*.lua` /
`koompi theme` / hook-based extension point over editing the inherited file directly.

If you copy code from a *third* repository into this one, follow
`licenses/README.md`: add a license notice to the file and drop a copy of the
license under `licenses/`.
