# J39 — One text-size knob across shell, GTK and terminal (O18)

`.work/OMARCHY-AUDIT.md` row O18. Omarchy at `~/.tmp/omarchy`: `bin/omarchy-display-text-size` (12 px anchor; shell base-size,
GTK `text-scaling-factor` quantised to whole points, terminal pt = px·9/12; range 9-20; `reset`), `default/themed/shell.toml.tpl:101-106`.
Shell root `Q=dots/.config/quickshell/koompi`. Read first: `$Q/modules/common/Appearance.qml:263-274` (the `pixelSize` ladder is ten
literals; file is allow-listed at 467 and may not grow), `$Q/modules/common/Config.qml:215-232` (`appearance.fonts`, families only;
allow-listed at 827, may not grow), `$Q/modules/settings/interface/FontsSection.qml` (115), `$Q/scripts/colors/switchwall.sh:85-91`
(GTK settings written there; allow-listed at 526, may not grow), `dots/.local/bin/koompi-theme` (79), `dots/.config/wezterm/wezterm.lua:16`
(`font_size = 11.5`), `tests/test_cursor_theme.sh` (asserting a written toolkit setting), `tests/test_file_length.sh`.

## Files you own
- `$Q/modules/common/Appearance.qml` (≤ 467), `$Q/modules/common/Config.qml` (≤ 827: net zero — if the new key costs a line,
  say which redundant line you removed), `$Q/modules/settings/interface/FontsSection.qml`
- `dots/.local/bin/koompi-theme`, `dots/.config/wezterm/wezterm.lua`
- new `tests/test_text_size.sh`; `.work/J39-report.md`

## Do
1. `Config.options.appearance.fonts.baseSize` (default 16 = today's `normal`); the ladder becomes `Math.round(base * k)` with
   k chosen so the defaults reproduce today's ten values exactly (paste the table in the report).
2. `koompi-theme text-size [N|reset|show]` (9..24 px): writes the Config key (through the same jq-merge path `koompi-theme`
   or `update`'s `config_merge` uses — cite; never a raw overwrite of `~/.config/koompi/config.json`), `gsettings set
   org.gnome.desktop.interface text-scaling-factor <quantised>` when gsettings exists, and `~/.config/koompi/text-size` (one
   number) that `wezterm.lua` reads with a `pcall(io.open)` fallback to 11.5; fires `koompi-hook theme-set` like the other
   subcommands. `show` prints all three current values.
3. `FontsSection.qml`: a slider (9-24, step 1) bound to the key, with the same `koompi-theme text-size` side effects (call the
   tool; do not duplicate the gsettings logic in QML).
4. `tests/test_text_size.sh`: shims `gsettings`, `koompi-hook`, `jq` present; throwaway `HOME`; proves: default table, `reset`,
   quantisation (16 → 1.3636 like omarchy, or your own rule, cited), wezterm's read via `lua -e` against the file, qmllint on
   the two QML files, and `Config.qml`/`Appearance.qml` line counts unchanged.

## Acceptance
1. Paste the test output and the suite tail (baseline +1). `shellcheck -x koompi-theme`: empty. `luac -p wezterm.lua`.
2. `koompi-theme text-size show` on this machine (read-only). Do NOT change Rithy's live text size; prove `set` under the throwaway `HOME`.
3. `wc -l` of `Appearance.qml`, `Config.qml`, `switchwall.sh` unchanged from main.

## Out of scope
- `switchwall.sh` (not yours), matugen templates, Konsole/Kitty sizes, Qt scaling (`QT_SCALE_FACTOR`), the lock screen.

## Stop conditions
- If the ladder cannot reproduce today's values within ±0 px for the default, stop and report the table instead of shipping a visual change.
