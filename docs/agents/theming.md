# Theming

Entry point for a user or agent: `koompi theme {regenerate,mode,scheme,color}`
(`dots/.local/bin/koompi-theme`). Don't call `matugen` or `switchwall.sh` directly —
`koompi-theme` is the stable interface; the pipeline underneath is not.

## Pipeline

`koompi-theme` → `switchwall.sh --noswitch [...]` → `matugen` → `switchwall.sh`'s
`post_process()` (`applycolor.sh`'s sibling steps: `handle_qt_app_colors`,
`code/material-code-set-color.sh`, run in parallel).

- `koompi theme regenerate` — re-derive colors from the current wallpaper.
- `koompi theme mode <dark|light>` — switch light/dark, same wallpaper.
- `koompi theme scheme <name>` — switch Material scheme (`scheme-tonal-spot`, `auto`, …).
- `koompi theme color <hex|clear>` — set or clear the accent color.

`matugen` is optional: `koompi-theme` checks for it and exits 0 with a warning if
absent, leaving whatever colors are already applied.

## Templates

`dots/.config/matugen/config.toml` lists every fan-out target under `[templates.*]`.
Each entry maps a template under `dots/.config/matugen/templates/<app>/` to a
generated output path — currently: shell (`m3colors`), Hyprland (`hyprland`,
`hyprlock`), `fuzzel`, `gtk-3.0`, `gtk-4.0`, KDE (`kde_colors`, `kde_scheme` →
`~/.local/share/color-schemes/KoompiMaterial.colors`), `qt6ct_scheme`, and the raw
`wallpaper` path. Adding a new themed app means adding a `[templates.*]` entry plus
a template file — not a new script outside this pipeline.

## Fan-out beyond matugen templates

Some targets aren't matugen templates and are separate steps in
`switchwall.sh`'s `post_process()`:

- `handle_qt_app_colors` — merges the generated KDE scheme into `kdeglobals` (no KDE
  tool is on PATH to do it for us) and writes `qt6ct.conf`. Gated on
  `.appearance.wallpaperTheming.enableQtApps` in the shell config.
- `code/material-code-set-color.sh` — VSCode-family editors (not Zed — KOOMPI's
  chosen editor has no theme sync yet).

If you're adding a new fan-out target, follow this pattern: a template under
`matugen/templates/` if matugen can drive it directly, otherwise a `post_process()`
step in `switchwall.sh` if it needs scripting matugen can't do alone.
