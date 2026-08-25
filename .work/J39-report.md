# J39 report: one text-size knob (O18)

Branch `j39-text-size-knob`, worktree only. Rithy's live config, GTK factor and text-size file were never written (see "show" below: still defaults, and `~/.config/koompi/text-size` does not exist).

## What shipped

- `Config.options.appearance.fonts.baseSize` (int, default 16). Config.qml stays at 827 lines: the new key cost one line, paid for by folding the three-line `waffles` comment ("Some spots are kinda janky...") into two lines, no meaning lost.
- `Appearance.font.pixelSize`: `normal` now reads `baseSize`; the other eight steps are `Math.round(normal * k)`; `title: huge` unchanged. Appearance.qml stays at 467 lines (ten ladder lines in, ten out; the opening line carries the one-knob comment).
- `koompi-theme text-size [N|reset|show]`, 9..24 px. The color subcommands are untouched in behaviour; their engine guards (switchwall present, matugen present → exit 0 otherwise) moved from the top of the script into `need_engine` so `text-size` runs without matugen. Also fixed on the way: every branch used to end in `command -v koompi-hook && koompi-hook ...`, which made the script exit 1 after a successful theme change on a machine without koompi-hook; `fire_hook` returns 0 in that case.
- `wezterm.lua`: `font_size` comes from `~/.config/koompi/text-size` through `pcall(io.open)`, falling back to 11.5 on a missing file, an unreadable one, or a non-number; the file is added to wezterm's config-reload watch list so a running terminal reflows.
- `FontsSection.qml`: "Text size" slider (9–24, step 1, snap) at the top of Settings › Interface › Fonts. It does not write the key or duplicate the gsettings logic: `onMoved` restarts a 300 ms timer (`Appearance.animationDuration.normal`) that runs `koompi-theme text-size N`; the tool writes config.json, the shell's file watch reloads, and a `Binding on value` keeps the knob in sync with the key even after a drag (so a CLI `reset` moves the slider too).
- `tests/test_text_size.sh` (new).

## Ladder table (Do 1)

`Math.round(16 * k)` reproduces every shipped value exactly; all products are integers, so the rounding is a no-op at the default and only matters at other sizes.

| step     | k      | 16·k  | shipped |
|----------|--------|-------|---------|
| smallest | 0.625  | 10    | 10 |
| smaller  | 0.75   | 12    | 12 |
| smallie  | 0.8125 | 13    | 13 |
| small    | 0.9375 | 15    | 15 |
| normal   | 1 (is baseSize) | 16 | 16 |
| large    | 1.0625 | 17    | 17 |
| larger   | 1.1875 | 19    | 19 |
| huge     | 1.375  | 22    | 22 |
| hugeass  | 1.4375 | 23    | 23 |
| title    | = huge | 22    | 22 |

## Write path and quantisation rules (Do 2)

- Config write: neither `koompi-theme` nor `update`'s `cmd_merge_config` (`dots/.local/share/koompi/libexec/update:293`, a three-way defaults merge, not a key setter) had a single-key write, so `config_set_text_size` copies `koompi-wallpaper`'s `json_update`/`commit_config` path (`dots/.local/bin/koompi-wallpaper:64-78`): `jq '.appearance.fonts.baseSize = $px'` over the existing file into a `mktemp` beside it, `jq -e 'type == "object"'` on the result, then `mv`. Plus `chmod --reference` so the shell's 0644 file does not become 0600. Missing or non-JSON config → refuse with exit 1, nothing written.
- GTK: anchor 16 px == factor 1.0 (omarchy anchors 12 px; ours is the shipped `normal`, so 16 must be a no-op). Same quantisation as `omarchy-display-text-size`: `factor = round(pt * px / 16) / pt` where `pt` is the interface font's point size from `gsettings get org.gnome.desktop.interface font-name`, so the GTK font lands on a whole point. On this machine `font-name` is `'Google Sans Flex Medium 11 @opsz=11,wght=500'`; omarchy's parser would take `@opsz=11,wght=500` as the size and fall back to 11 by luck, ours strips the ` @...` variation suffix first. At 11 pt: 9→0.5455, 12→0.7273, 18→1.0909, 20→1.2727, 24→1.5455. `text-size 16` and `reset` run `gsettings reset` rather than setting 1.0. `gsettings` missing → GTK step skipped, the other two still apply.
- Terminal: `pt = round_half(px * 11.5 / 16)` (16→11.5, 18→13.0, 20→14.5, 24→17.5, 9→6.5), written as one number to `~/.config/koompi/text-size` via tmp+mv because wezterm watches it.
- Hook: `KOOMPI_HOOK_TEXT_SIZE=N koompi-hook theme-set`, same event as the other subcommands.

## Acceptance 1: test output, suite tail, shellcheck, luac

```
$ nice -n 19 ionice -c 3 bash tests/test_text_size.sh
ok   ladder: smallest=10 smaller=12 smallie=13 small=15 large=17 larger=19 huge=22 hugeass=23, title=huge
ok   set 18: baseSize=18 gtk=1.0909 terminal=13.0 hook fired
ok   quantised: 20->1.2727/14.5, 18@10pt->1.1000, 9->0.5455/6.5, 24->1.5455/17.5
ok   reset: baseSize=16 gtk reset terminal=11.5
ok   show
ok   refusals: 8, 25, abc, 1.5, empty, non-JSON config, missing config
ok   wezterm: 14.5 from the file, 11.5 without it or on garbage
ok   Appearance.qml and Config.qml are still at their allow-listed length
ok   qmllint: Appearance.qml and FontsSection.qml parse without errors
text size test passed
```

Suite (`NO_COLOR=1 nice -n 19 ionice -c 3 bash tests/run.sh`), tail:

```

86 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

Baseline on main: 88 test files → 85 passed, 3 skipped (same three: globalmenu, hypridle_logged, search_bench_parity, all environment skips). This branch: 89 files → 86 passed, 3 skipped, 0 failed. `test_file_length.sh` passed with Appearance.qml and Config.qml at their allow-listed counts.

```
$ shellcheck -x dots/.local/bin/koompi-theme
(exit 0)
$ luac -p dots/.config/wezterm/wezterm.lua
(exit 0)
```

`shellcheck -x tests/test_text_size.sh` is also empty.

## Acceptance 2: show on this machine (read-only)

```
$ bash dots/.local/bin/koompi-theme text-size show
text size: 16 (default) px
gtk text-scaling-factor: 1.0
terminal font: 11.5 (default) pt
```

`~/.config/koompi/text-size` does not exist and `~/.config/koompi/config.json` has no `baseSize` key: nothing live was touched. `set` is proven under the throwaway HOME in test sections 2–4 above (config key, gsettings call, terminal file, hook, no temp files left, mode preserved).

## Acceptance 3: line counts vs main

| file | main | branch |
|---|---|---|
| modules/common/Appearance.qml | 467 | 467 |
| modules/common/Config.qml | 827 | 827 |
| scripts/colors/switchwall.sh | 526 | 526 (not touched) |

## Not verified here

- The slider and the shell's live reflow were not exercised in a running quickshell: the live shell runs from `~/.config/quickshell/koompi`, not this worktree, and restarting it is off-limits. qmllint accepts both QML files (no errors; the warnings are the usual unresolved `qs.*` import noise the existing services test also ignores). The Config reload-on-external-write path is the same one `koompi-wallpaper` already relies on.
- wezterm's live reload via `add_to_config_reload_watch_list` was not exercised (no throwaway wezterm run); the read path itself is proven with `lua` against the real `wezterm.lua` and a stub `wezterm` module.
- Does not touch the migration/merge machinery: an existing config.json without `baseSize` reads as 16 through the JsonAdapter default, which the live `show` above demonstrates.
