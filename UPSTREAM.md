# Upstream & attribution

KOOMPI OS's desktop shell is **not original work**. It is a downstream
derivative of **[illogical-impulse]** — the Hyprland dotfiles by **end-4**
(<https://github.com/end-4/dots-hyprland>). The bar, sidebars, notifications,
OSD, settings, the Material You theming engine, and the QML service layer are
all end-4's design and code. We are deeply grateful for it.

[illogical-impulse]: https://github.com/end-4/dots-hyprland

## License

end-4/dots-hyprland is **GPL-3.0**, and so is this repository (`LICENSE`). A
derivative of GPL-3.0 code stays GPL-3.0 — that is by design, not an obstacle.
Nothing in KOOMPI's fork relicenses any inherited file.

If you copy code from a *third* repository into this one, follow the rule in
[`licenses/README.md`](licenses/README.md): add a license notice to the file and
drop a copy of the license under `licenses/`.

## How this repo relates to upstream

The **content** is derived from end-4's tree; the **git history is not shared**.
This repository was restarted from a single root commit, so none of end-4's
commits are present here:

- Fork point: `614f02e6` (end-4 `main`, 2026-06-03). Everything inherited in this
  tree descends from that commit.
- The directory/namespace rename `ii → koompi` (config dir, `modules/`, the
  `~/.config/illogical-impulse` state dir, keyring id, metapackages) happened
  before the restart, so inherited files now sit at `modules/koompi/...`.
- The full pre-restart history — end-4's ~6300 commits plus KOOMPI's, with the
  renames recorded as `R100` — is preserved read-only at
  <https://github.com/rithythul/koompi-desktop-history>. That archive is the
  authoritative record of what came from where.
- The only submodule is `modules/common/widgets/shapes`
  (end-4/rounded-polygon-qmljs).

## What KOOMPI actually authored

Our divergence is small and deliberate — keep it that way:

- The `hl.*` **Hyprland Lua config bridge** (`dots/.config/hypr/`) — KOOMPI's own
  config layer; the inherited shell's dispatch calls were ported onto it.
- **OS integration**: KOOMPI detection in `services/SystemInfo.qml`, the
  user-actions loader in `services/LauncherSearch.qml`, config-path rewrites.
- **Branding**: wallpapers, brand-green accent, KOOMPI bar-layout tweaks, the
  KOOMPI default theme, this attribution.
- A handful of added AI providers (DeepSeek, GLM, MiniMax, Kimi).
- The **Zig installer** (`installer/`) and the **Arch packaging tree**
  (`sdata/dist-arch/`) are KOOMPI-original, not from end-4.

## Tracking upstream

end-4 actively maintains the shell (Wayland/Quickshell breakage, fixes). Because
there is no shared history, `git merge end-4/main` no longer works — every
upstream fix has to be reviewed and ported by hand:

```sh
git remote add end-4 https://github.com/end-4/dots-hyprland.git   # once
git fetch end-4
git log --oneline 614f02e6..end-4/main                 # review what's new
git diff 614f02e6..end-4/main -- <upstream/path>       # read one change
```

Then apply the change to the corresponding `modules/koompi/...` file. When a
port is done, move the `614f02e6` marker above to the upstream commit you
reviewed up to, so the next person knows where to resume.

Porting is now manual work, so it only stays affordable if **KOOMPI changes live
on KOOMPI-owned surfaces** (the Lua bridge, branding, installer, packaging).
Every edit to an inherited file makes the next port harder to read.

## Supporting end-4

If KOOMPI's shell is useful to you, the upstream project deserves the credit and
the support: <https://github.com/sponsors/end-4>.
