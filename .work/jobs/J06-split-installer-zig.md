# J06 — split installer/src/main.zig

## Files you own
- `installer/src/**`

## Do
1. (D6) Read `installer/src/main.zig` and `installer/build.zig`. Clusters: theme/TOML 23-277 (tests 894-931), ANSI 278-362, glyphs 363-405, model 406-484, input 486-530, handlers 531-568, frame render 569-817, driver 818-892.
2. (D6) Create `theme.zig` (cluster 1 + its tests; pub: `Theme`, `Rgb`, `Profile`, `Glyphs`, `ThemeError`, `loadTheme`, `loadThemeRaw`, `parseTheme`, `parseHexColor`, `validateTheme`), `term.zig` (ANSI + glyphs; pub: `ColorTier`, `ColorToken`, `IconPurpose`, `detectColorTier`, `fg`, `bg`, `resetSGR`, `icon`, `stepGlyph`, `selectGlyph`), `app.zig` (model + input + handlers; `Step.next/prev/title` become `pub fn`), `ui.zig` (frame render; pub only `Ctx` and `draw`). `main.zig` keeps `step` and `main`.
3. (D6) Add to `main.zig`: `test { _ = @import("theme.zig"); _ = @import("term.zig"); _ = @import("app.zig"); _ = @import("ui.zig"); }` so `zig build test` reaches the moved tests. `build.zig` needs no change (it names only `src/main.zig`).
4. `zig fmt --check src/`, `zig build`, `zig build test`.
5. Run the binary once in a terminal and confirm the first screen renders identically (compare against a capture from `main`).

## Acceptance
1. `wc -l installer/src/*.zig` (main.zig ≤ 120, none over 400).
2. `zig build test` output showing the same 4 tests passing (name them).
3. `zig fmt --check` empty.
4. Two captures (`script -q -c ./zig-out/bin/<name> /dev/null` or equivalent, first frame only) from `main` and from your branch, and `diff` of them empty.

## Out of scope
- `installer/build.zig`, `build.zig.zon` (J02 owns the .zon comment).
- Behaviour changes, new screens, archinstall integration.

## Stop conditions
- If a cross-cluster call needs something the map did not list (see `.work/AUDIT.md` D6), add the `pub` and note it in your report; if it needs a change to `build.zig`, stop and report.
- Runs after J02 is verified; if `installer/zig-pkg/` still exists on your base, stop and report.
