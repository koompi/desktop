# KOOMPI Wallpaper Style Guide

## Direction

KOOMPI wallpapers should feel like desktop backgrounds first: calm, spacious, readable behind panels/widgets, and visually premium.

The inspiration is the design logic behind polished desktop wallpapers such as macOS abstract and space/universe wallpapers, but KOOMPI must not copy Apple assets, compositions, trademarks, or exact visual identity.

## What macOS-style abstract/universe wallpapers do well

### 1. They preserve icon/text readability

Good desktop wallpapers usually have:

- broad smooth gradients
- low-to-medium detail in the center
- no noisy text or tiny repeated patterns
- enough dark/light contrast for panels and widgets
- clean negative space

### 2. They feel dimensional but not busy

They often use:

- soft depth
- blurred organic shapes
- light bloom
- atmospheric haze
- large-scale forms instead of small details
- subtle texture instead of sharp clutter

### 3. They support system theming

A good wallpaper should produce useful theme colors:

- one clear dominant hue
- one or two accent hues
- not too many saturated competing colors
- dark and light variants when possible

### 4. Universe wallpapers use scale and atmosphere

Space images work well when they have:

- large dark regions for readability
- nebula/cloud structure as a soft focal point
- star fields that are present but not noisy
- high resolution
- cinematic color balance

### 5. They avoid literal UI conflict

Avoid wallpapers with:

- text/logos/watermarks
- faces as the main focal point
- hard high-contrast edges behind panels
- busy detail across the whole frame
- extremely saturated colors everywhere

## KOOMPI wallpaper categories

Use these folders:

```text
~/.config/koompi/wallpapers/library/desktop-abstract
~/.config/koompi/wallpapers/library/universe
~/.config/koompi/wallpapers/library/static
```

`abstract/` can remain as a raw/free-art source folder, but preferred desktop-ready images should go into `desktop-abstract/` and `universe/`.

## Desktop abstract criteria

A desktop-grade abstract wallpaper should be:

- 1920px wide minimum, preferably 2560px or 3840px
- no text or obvious watermark
- smooth enough for widgets and panels
- not too painterly/noisy unless cropped well
- visually calm at the center/top where shell UI appears
- usable with both dark and translucent shell elements

## Universe criteria

A universe wallpaper should be:

- public domain or clearly permissive
- high resolution
- mostly dark or with large calm regions
- not overloaded with tiny stars across every pixel
- cinematic but not distracting
- suitable for random-hourly workspace use

## KOOMPI-specific rules

- Do not copy Apple wallpaper files.
- Do not clone exact Apple compositions.
- Use public-domain or permissively licensed sources such as NASA/JPL/ESA where license permits.
- Keep source metadata with downloaded images.
- Workspace wallpaper changes must not trigger global theme regeneration by default.
- Current UI/UX should stay as-is unless a change clearly improves desktop usability.
