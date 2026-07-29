# Design

Visual system of the KOOMPI OS brainstorm page (`docs/brainstorm/`), mirroring the intended Quickshell shell design.

## Theme

**"Reading room over the engine"** (June 2026, inspired by anthropic.com warmth + openhands.dev dark-premium): the page chrome is warm ivory paper — the document is a *book* about the OS — while staging panels and heroes use a warm espresso dark (#242019→#171411) with a clay glow and a faint indigo whisper — dark sections share the page's warmth (cold indigo-night clashed and was retired). Desktop sims keep their own product wallpaper tokens. Editorial serif display (`Source Serif 4`) for section headings and the logo; Inter for everything else. Shadows are warm-tinted (`rgba(64,55,38,…)`), never cool slate. Desktop sims support `theme-light`/`theme-dark` with their own `--t-*` tokens — the OS's own themes are documented product decisions (§53), independent of page chrome.

Page neutrals: bg `#F0EDE5` · surface `#FBFAF6` · surface2 `#F4F0E7` · surface3 `#EAE4D7` · surface4 `#DDD5C4` · borders `#D3CCBC`/`#E5DFD2` · text `#1F1C17` / muted `#6B6457` / subtle `#9A9183`. The five semantic accents are unchanged — they are contracts, not decoration.

## Color palette

Tokens defined in `css/base.css`:

- `--bg` #070B13 (sim dark desktop), page background near-white
- `--surface` / `--surface2` / `--surface3` / `--surface4`: layered panels
- `--accent` #6366F1 indigo: AI / intelligence
- `--cyan` #22D3EE: data streams
- `--emerald` #10B981: private / safe / local
- `--amber` #F59E0B: consent needed
- `--red` #EF4444: danger / violation
- Each accent has a `-glow` translucent variant for tinted backgrounds
- `--text`, `--text-muted`, `--text-subtle` for three-step text hierarchy

Color is semantic first: never use an accent decoratively where its state meaning could mislead.

## Typography

- `--font-ui`: UI sans (system stack), `--font-mono`: JetBrains Mono for data/code/timestamps
- Display 56px / heading 22px / title 15px / body 13px / label 11px / mono 12px
- Mono is used for anything machine-true: times, sizes, hashes, file paths

## Shape & elevation

- Radii: `--radius-sm` < `--radius` < `--radius-lg` < `--radius-xl`; pills use 20px+
- Elevation via soft layered shadows, not borders alone; 1px `--border`/`--border2` hairlines
- Dark sim surfaces use translucent fills + `backdrop-filter` blur for shell glass

## Components

- Bar pills (privacy pill, AI pill, media pill), workspace dots, tray icons (`bar.css`)
- Sidebar panels, quick-settings tiles, notification items (`widgets.css`)
- Desktop sim: wallpaper layer, window chrome (tiled/floating), sidebars, popups, OSD, overview, launcher (`desktop-sim.css`)
- Brainstorm sections: `.section-header` + `.tag`, `.desc`, `.callout-group`, `.tool-code`, `.state-chip`, `.badge`

## Iconography

Font Awesome 6 (CDN), never emoji — emoji read as childish and low-value (standing rule). `fa-solid` for UI, `fa-brands` for app logos; icons inherit size/color from context; white on gradient app tiles. Typographic glyphs are fine and intentional: ✦ (the AI brand mark), ✓ ✕ ✗, arrows, ★, ☰. Inside SVG `<text>`, use FA font glyphs (`font-family:'Font Awesome 6 Free'; font-weight:900` + codepoint), since HTML `<i>` does not render in SVG.

## Motion

- 150–280ms transitions, ease-out (quart/quint/expo family); no bounce, no elastic
- Panels slide/scale from their anchor; OSD pills fade+rise; overview tiles stagger in
- AI "thinking" is non-directional (breathing); loading is directional (bars)
- All motion gated by `prefers-reduced-motion`
