# KOOMPI live UX/UI audit

Date: 2026-07-28

## Scope and method

This audit compares the running KOOMPI Hyprland session at 1920x1200 with the
Quickshell source in `dots/.config/quickshell/koompi`.

The live bar, launchpad, and control center were opened through their public IPC
surface and visually inspected. The active config was also compared with the
repository. The source matches the live shell; the only live-only Quickshell
files were build caches for the global-menu helper.

## What already works

- The shell has a consistent spatial model: application context on the left,
  workspaces in the center, status and time on the right.
- The active-window block is unusually useful. App identity, title, and global
  menu share one predictable location without consuming window content.
- The launchpad is calm, direct, keyboard-aware, and visually separate from the
  work session.
- The control center groups quick controls, notifications, and personal tools
  into one surface with generous pointer targets.
- Shape, tint, wallpaper integration, and motion form a recognizable KOOMPI
  visual language rather than a collection of upstream defaults.

## Priority findings

### P0: workspace state uses competing encodings

With both `alwaysShowNumbers` and `showAppIcons` enabled, a workspace button can
render its number and app icon in the same 26px target. Empty workspaces can
also show a number and dot together. The live result is difficult to scan:
Chinese numerals, tiny monochrome icons, occupied backgrounds, and the active
pill all compete for attention.

Decision: each workspace gets one foreground identity at a time.

1. Show labels while numbers are requested, including the temporary Super-key
   reveal.
2. Otherwise show the main app icon when one exists.
3. Otherwise show the simple dot.
4. Preserve the occupied background and active pill as state layers.

### P1: control-center toggles are too narrow for their content

The standard sidebar shows three expanded toggles per row. At its live width,
this truncates core labels such as Audio input, Audio output, and Night Light.
The status line then competes for the same small width.

Decision: keep the six-column customization model, but render at most four
logical columns below 480px. Standard size-2 toggles become two-up, providing
readable labels and larger targets without changing user configuration.

### P1: launchpad needs stronger wayfinding

The launchpad's full-screen presentation is visually clean, but its search
field and page position are quiet relative to the very large canvas. There is
no visible distinction between frequent, pinned, and remaining apps, and the
only navigation cue is a pair of small page dots.

Recommended next work:

- Make search the clear primary action and show a keyboard hint.
- Give the first page a small, explicit `Frequent` or `Pinned` section.
- Add an accessible page label such as `1 of 2` alongside the dots.
- Offer a compact list result mode after typing so long app names and
  descriptions remain readable.

### P1: control-center hierarchy flattens unrelated jobs

Quick controls, notification history, Pomodoro, stopwatch, calendar, tasks, and
timer all live in one tall panel. The current segmented navigation appears
midway down the surface, so its scope is not immediately clear.

Recommended next work:

- Treat quick controls and notifications as the `Today` surface.
- Move personal tools into a clearly labeled secondary tab set.
- Keep only the active tool mounted so keyboard focus and screen-reader order
  match what is visible.
- Add text labels or tooltips to header-only actions such as edit, refresh,
  settings, and power.

### P2: the paused Pomodoro looks active

At rest, the bar showed a focus flame, a full progress ring, and `25:00`.
Lowering the whole component opacity did not clearly communicate that pressing
it starts the timer.

Decision: use a play symbol and inactive semantic color while paused. Restore
the focus/break symbol and accent only while running.

### P2: low-contrast secondary text is overused

Notification metadata, inactive workspace labels, status lines, and secondary
actions all use similarly faint text. This makes state, metadata, and disabled
controls look equivalent.

Recommended next work:

- Reserve the faintest token for disabled content.
- Use the normal secondary token for timestamps, statuses, and inactive-but-
  available controls.
- Validate text and icon contrast against both generated light and dark themes,
  not only the current wallpaper.

## Enhancement implemented

This pass changes three focused behaviors:

- Workspace foregrounds are mutually exclusive: label, app icon, or dot.
- Android-style quick toggles adapt to two expanded tiles per row in a narrow
  sidebar and use the correct inter-column spacing calculation.
- The bar Pomodoro uses a play affordance and inactive color while paused.

These changes preserve the current visual language, configuration schema, IPC
surface, and user data.

## Suggested sequence

1. Ship and observe the bar and quick-toggle changes in daily use.
2. Improve launchpad wayfinding without changing its full-screen spatial model.
3. Reorganize the control center into a clear `Today` surface and personal-tool
   tabs.
4. Audit generated light/dark palettes for contrast and disabled-state
   semantics.
5. Run keyboard-only and screen-reader passes once the information hierarchy is
   stable.
