# R&D Plan — KOOMPI bar as a Rust Wayland binary

**Status:** proposal / spike. Not committed product work.

## Why this exists

Today the whole KOOMPI shell (bar, lock, notifications, OSD, sidebars) is QML
run by **quickshell** (C++/Qt). That's the right base for the rebrand. This
spike answers one question and nothing more:

> If KOOMPI ever wants to drop the Qt/quickshell dependency and own the shell
> stack, what does that actually cost — in effort, features lost, and risk?

The bar is the smallest self-contained widget that still touches every hard
part of a Wayland shell: layer-shell positioning, a compositor IPC feed,
system data sources (battery/audio/tray), and theming. Build *only* the bar,
measure the cost, then decide. Do **not** expand scope until M4 is judged.

## Non-goals

- Not replacing quickshell. The QML shell stays the product during and after this spike.
- Not lockscreen / notifications / sidebars / OSD. Bar only.
- Not multi-compositor. Hyprland only (uses its IPC).
- Not "feature complete." Parity target is the **Hug-style top bar**, nothing more.

## Stack decision

Two viable Rust paths. Pick **one** for the spike; recommendation first.

### A. gtk4-rs + gtk4-layer-shell  *(recommended for the spike)*
- `gtk4` + `gtk4-layer-shell` crates give layer-shell anchoring + a mature,
  CSS-themeable widget tree out of the box. Fastest path to something that
  *looks* like the Hug bar (rounded corners, pills, fonts) without writing a
  renderer.
- Theming via GTK CSS — maps cleanly onto a KOOMPI palette and is hot-reloadable.
- Cost: pulls GTK at runtime. So this proves "can we rebuild the bar in Rust",
  not "can we be dependency-light." Honest about that.

### B. iced + iced-layershell (or raw smithay-client-toolkit + wgpu/femtovg)
- Pure-Rust, GPU-drawn, no GTK/Qt. This is the real "engine independence" answer.
- Cost: you draw and lay out everything yourself — rounded corners, text
  shaping (cosmic-text), hit-testing, animations. Weeks more than path A for
  the same visual result.

**Plan:** spike on **A** to get a working bar fast and validate the data/IPC
plumbing (the genuinely hard, reusable part). If the data layer proves out and
leadership still wants Qt-free, port the *view* layer to **B** — the IPC and
system-source crates from A carry over unchanged.

## Architecture

```
+-----------------------------------------------------------+
|  koompi-bar (Rust binary, one per monitor via layer-shell)|
|                                                           |
|  view/        gtk4 widgets  (Hug container, pills)        |
|  theme/       palette + CSS, hot-reload                   |
|  sources/                                                 |
|    hypr_ipc   Hyprland socket2 event stream (workspaces,  |
|               active window) — UDS in $HYPRLAND_INSTANCE  |
|    battery    upower over zbus (dbus)                     |
|    audio      pipewire / wireplumber volume               |
|    tray       StatusNotifierItem over zbus                |
|    clock      tokio interval                              |
|    sysres     /proc + sysinfo crate (cpu/ram)             |
+-----------------------------------------------------------+
```

- Async runtime: `tokio`. Each source is a task pushing updates over an
  `mpsc`/`watch` channel into the GTK main loop (`glib::MainContext::spawn_local`).
- One process, one layer-shell surface per output; re-create surfaces on
  monitor hotplug.

## Feature parity checklist (Hug top bar only)

- [ ] Layer-shell top anchor, exclusive zone, per-monitor
- [ ] Hug corner style (rounded screen-corner decorators, matches current look)
- [ ] KOOMPI distro logo (left), click → opens left sidebar (`hyprctl dispatch`/IPC)
- [ ] Workspaces: live from Hyprland socket2, click to switch
- [ ] Active-window title
- [ ] Clock / date
- [ ] Battery (upower) with charging state
- [ ] Audio volume indicator + scroll-to-change
- [ ] System tray (SNI)
- [ ] CPU/RAM resources
- [ ] KOOMPI palette applied, hot-reload on theme change

## Milestones

| # | Deliverable | Rough effort |
|---|---|---|
| M0 | Cargo workspace, layer-shell window pinned top, solid bar, exclusive zone | 1–2 days |
| M1 | Hyprland socket2 client → live workspaces + active window | 2–3 days |
| M2 | Clock + battery + audio + sysres sources wired to widgets | 3–4 days |
| M3 | Hug styling + KOOMPI palette + logo + sidebar-toggle action | 2–3 days |
| M4 | System tray (SNI) — the hardest source | 3–5 days |
| **Gate** | **Side-by-side vs ii bar; decide go / no-go on full shell** | — |

Single dev, ~**3 weeks** to M4 on path A. Path B view rewrite adds ~2–4 weeks.

## Key risks / unknowns

- **System tray (SNI):** most painful Wayland surface; budget the most slack here.
- **Hyprland IPC churn:** socket2 event names shift across releases; pin a version.
- **Per-monitor + hotplug:** layer-shell surface lifecycle is fiddly.
- **Path A doesn't prove dependency-independence** — only path B does. Don't let
  a slick gtk4 demo be mistaken for "we no longer need Qt."

## Decision gate (after M4)

Go to full-shell rewrite **only if** all hold:
1. M4 bar reaches visual + behavioral parity with the Hug ii bar.
2. Per-widget effort × remaining surfaces (lock, notif, OSD, 2 sidebars, settings)
   is acceptable — these are individually **larger** than the bar (lock has PAM,
   settings has dozens of panels).
3. There's a concrete product reason (KOOMPI OS footprint, licensing, control)
   that the QML fork can't satisfy.

Otherwise: keep the quickshell fork, archive the spike, reuse the Rust source
crates (`hypr_ipc`, `tray`) as standalone tools if useful.

## Repo layout if greenlit

```
rust/koompi-bar/
  Cargo.toml          # workspace
  crates/
    bar/              # binary, gtk4 view
    hypr-ipc/         # reusable Hyprland event client
    sources/          # battery/audio/tray/sysres
```
Kept under `rust/` so it never entangles the QML config install path.
