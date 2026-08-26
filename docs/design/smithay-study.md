# Building on Smithay — what it takes, and what Otto already did

> **Parked 2026-08-26. KOOMPI HD is the active work.** Resume notes: [koompi-sd.md](koompi-sd.md#picking-this-back-up).

A gap analysis for [KOOMPI SD](koompi-sd.md), researched 2026-08-26 against upstream Smithay and against the SD tree as it stood at tag `koompi-sd-0.16.0`.

**The short version: do not write a compositor.**
KOOMPI already has a Smithay-based stacking compositor — Otto — forked, patched, packaged and run live on this hardware.
The rest of this document is the gap list Smithay leaves, scored against what Otto has already closed.

niri and cosmic-comp appear only as evidence of what Smithay leaves undone.
niri is scrollable-tiling and is not a model for SD.

## What KOOMPI already has

| | |
| --- | --- |
| Upstream | [`nongio/otto`](https://github.com/nongio/otto), MIT, 0.15.0, one maintainer |
| KOOMPI fork | `koompi/otto`, branch `koompi` — 13 commits on top of `main`, rebasable |
| Local clone | removed 2026-08-26; archived at `~/workspace/otto-archive-20260826.tar.gz` |
| Size | ~92,000 lines across `src/`, `components/`, `protocols/` |
| Base | a **fork** of Smithay — `nongio/smithay`, branch `feat/dmabuf-scanout` (dmabuf scanout plus XWM focus) |
| Rendering | LayersEngine (`nongio/layers`) with Skia — not iced, not libcosmic |
| Packaging | `sdata/dist-arch/koompi-sd/`, sourcing tag `koompi-sd-0.16.0` |

It is a stacking window manager with a dock, a topbar, workspaces per output, Exposé, an app switcher, animated minimise, half-screen snap, session lock and a greeter.
Not a prototype: it was audited live on tty1 across two 1920×1200 outputs on 2026-08-03, and the findings are written up in [`sd-audit-2026-08-03.md`](sd-audit-2026-08-03.md).

## What Smithay gives you

**Backends** — the hardware half, and the part that would otherwise cost the most:
`drm` (KMS modesetting), `udev` (device scanning), `session` (libseat/logind), `libinput`, `allocator` (gbm, dmabuf), `renderer` (GLES/Vulkan/pixman), `egl`, `vulkan`, and `winit`/`x11` for nested development.

**Protocol handlers** — around 40 modules:
`compositor`, `shell::xdg`, `shell::wlr_layer`, `shell::kde`, `seat`, `shm`, `dmabuf`, `output`, `selection` (data device, primary selection, data control), `session_lock`, `text_input`, `input_method`, `virtual_keyboard`, `tablet_manager`, `idle_inhibit`, `idle_notify`, `fractional_scale`, `viewporter`, `presentation`, `cursor_shape`, `pointer_constraints`, `pointer_gestures`, `relative_pointer`, `keyboard_shortcuts_inhibit`, `xdg_activation`, `xdg_foreign`, `xdg_system_bell`, `xdg_toplevel_icon`, `xdg_toplevel_tag`, `foreign_toplevel_list`, `security_context`, `drm_lease`, `drm_syncobj`, `alpha_modifier`, `content_type`, `commit_timing`, `fifo`, `single_pixel_buffer`, `xwayland_shell`, `xwayland_keyboard_grab`.

Plus XWayland and the `desktop` bookkeeping helpers.

Notably `text_input` and `input_method` are both there, which is what fcitx5 + fcitx5-m17n — how `koompi-toolkit` does Khmer today — needs.

### Version reality

The newest crates.io release is **0.7.0, June 2025** — fourteen months stale.
Nobody shipping a desktop uses it: niri pins `git rev = "4cf0b620…"`, cosmic-comp patches `0.7.0` over to `git rev = "5fb12b8"`.

Otto goes further and depends on a **fork**, `nongio/smithay` on `feat/dmabuf-scanout`.
That is one more upstream than niri or cosmic-comp carries, and it is the single largest maintenance fact about adopting Otto: KOOMPI would sit downstream of a fork of a library that does not cut releases.

## What Smithay does not give you

**No window management.** Smithay hands you surfaces and their commits. Everything a user calls "the window manager" is yours — and for stacking that is a long list; see below.

**No screen capture.** `wlr-screencopy` and `ext-image-copy-capture` are absent. niri wrote screencopy itself; cosmic-comp wrote ext-screencopy itself. This matters concretely: `koompi-screencapture` ships grim, slurp, swappy and wf-recorder, and all four are screencopy clients.

**No output configuration.** `wlr-output-management` is not in Smithay. Without it there is no `wlr-randr`, no `wdisplays`, and no standard path for a settings panel to configure displays.

**No window control for taskbars.** Smithay's `foreign_toplevel_list` is `ext-foreign-toplevel-list` — read-only. Activating, closing or minimising a window from a panel needs `wlr-foreign-toplevel-management` or an equivalent.

**No workspace protocol.** `ext-workspace-v1` is not provided.

**No gamma control.** Night-light needs `wlr-gamma-control`.

**No session lifecycle, no portal backend, no config, no IPC, no CLI.**

## What stacking specifically costs

The part with no comparison in niri or cosmic-comp, because neither is a stacking desktop.

A tiling compositor computes geometry from a layout function.
A stacking compositor has no layout function, so each of these becomes something it owns outright:

- **Z-order** — the stacking list as the core data structure, raise-on-click, keep-above/below, transients above their parent, and how all of that interacts with layer-shell layers.
- **Interactive move and resize** — honouring `xdg_toplevel`'s `move` and `resize`, which tiling compositors largely ignore: grabs, per-edge resize cursors, output constraint, modifier-drag from anywhere in the window.
- **Placement on map** — centre, cascade, least-overlap, remember-last-position; dialogs centred on their parent, not the screen.
- **Server-side decorations** — Qt requests them, GTK draws its own, and a stacking desktop is expected to have title bars. Drawing them means the compositor renders and hit-tests UI: title text, buttons, hover states, double-click-to-maximise, right-click window menu.
- **Minimise** — meaningless without a taskbar to restore from, so minimise and a foreign-toplevel *management* protocol are one feature, not two.
- **Maximise, restore and snap** — pre-maximise geometry, layer-shell exclusive zones so a maximised window doesn't sit under the panel, drag-to-edge snapping.
- **Window switching** — Alt-Tab with MRU order, and previews if it is to look current.
- **Popup positioning** — `xdg_positioner` decides where every Qt and GTK menu lands, including flip-and-slide at output edges. Getting it wrong breaks every application's menus at once.
- **XWayland stacking correctness** — override-redirect windows above their owner, never focused.
- **Focus policy** — click-to-focus versus follows-mouse, focus-stealing prevention, where focus lands when the focused window closes.

Otto has done all of this.
That is the argument for adopting it rather than starting again, and it is worth more than the protocol coverage below.

## Scored against Otto

| Smithay gap | Otto |
| --- | --- |
| Stacking window management | **done** — move/resize, animated minimise to dock, half-screen snap, least-overlap placement, per-output workspaces, Exposé, app switcher |
| `wlr-screencopy` | **done** (`src/state/screencopy.rs`) — but see finding D below |
| `wlr-foreign-toplevel-management` | **done** (`protocols/`) |
| `wlr-gamma-control` | **done** (`protocols/`) — night shift via `wlsunset` |
| Session lifecycle | **done** — `exec_once` plus `sd-notify` |
| Portal backend | **done** — `components/xdg-desktop-portal-otto`; incomplete, see below |
| Config, IPC, CLI | **done** — TOML config |
| `text-input-v3` / `input-method-v2` | **present** (`src/state/input_method_handler.rs`) |
| Session lock, greeter | **done** — `otto-lock` (PAM), `otto-greeter`, `otto-auth-ui` |
| Notifications, panel, tray | **done** — `otto-islands`, `otto-bar` with DBusMenu tray |
| Rust UI toolkit | **done** — `otto-kit`, Skia-based |
| `wlr-output-management` | **missing** — `xdg-output` only; displays come from `config.toml` |
| `ext-workspace-v1` | **missing** — workspaces exist internally, no protocol |
| Polkit agent | **missing** |
| Launcher | **missing** |

## What is actually left

From the live audit in [`sd-audit-2026-08-03.md`](sd-audit-2026-08-03.md), which is the authority here and should not be duplicated:

**Blockers** — the bar exists on one output only; no application publishes a global menu, because Otto implements no `org_kde_kwin_appmenu_manager`.

**High** — Qt and GTK apps render light on a dark desktop; the dock is missing from captures, which is either a drawing bug or `wlr-screencopy` compositing only the primary plane and silently losing every overlay; no polkit agent; no wallpaper set.

**Medium and below** — the Settings portal answers only `color-scheme` and `icon-theme`, so GTK4 gets no cursor theme or accent colour; compositor shortcuts ignore virtual-keyboard input, which blocks automated testing of every keybinding; icon theme lookup does not follow `Inherits=`; no screenshot, display, network or launcher UI.

Two upstream bugs found in that audit are worth naming because they are not KOOMPI's: `xdg-desktop-portal-otto` ships a D-Bus service file naming a systemd unit that does not exist in the tree, and the `.portal` file is invisible to any session using a curated `XDG_DESKTOP_PORTAL_DIR`.

## What adopting Otto costs

Rithy decided on 2026-08-26 to **hard fork** rather than track upstream; see [the hard fork plan](sd-hardfork.md).
That answers the first two items below and converts the rest into things KOOMPI owns outright.

- **Three upstreams, not one.** Otto depends on `nongio/smithay` and `nongio/layers` by *git branch*. Forking only Otto leaves two live dependencies on branches in an account KOOMPI does not control. Cutting all three is what makes the fork real.
- **A one-maintainer upstream**, roughly 26 commits in three months. After the fork, the five audit fixes that were headed upstream are KOOMPI's alone.
- **A rendering stack nobody else uses.** LayersEngine plus Skia — 22k lines — is not iced, gpui or GTK. The expertise is not transferable and the community is one project wide. This is the heaviest thing the fork inherits.
- **Licence.** Otto is MIT, © 2024 Riccardo Canalicchio; `koompi-desktop` is GPL-3.0. Combining works in that direction, and the copyright notice stays regardless of what the tree is renamed to.
- **A design language that is already opinionated.** Otto is explicitly macOS-inspired. That is either exactly what SD wants or a permanent divergence — a decision, not a detail.

## Conclusion

Smithay removes the genuinely hard part — DRM/KMS, buffer allocation, input, forty protocol implementations — and then leaves a whole desktop, most of which no existing project could be copied for because none of them stacks.

Otto did that work.
The question for SD is therefore not "what do we need to build on Smithay" but "what do we finish on Otto", and that list is short, already audited, and already written down in [`sd-audit-2026-08-03.md`](sd-audit-2026-08-03.md).

The packaging has since landed as `sdata/dist-arch/koompi-sd/`, sourcing a tag rather than a pinned SHA — step 1 of [the hard fork plan](sd-hardfork.md).

## Sources

- [Smithay crate docs](https://docs.rs/smithay/latest/smithay/) and [crates.io](https://crates.io/crates/smithay) — module inventory, release dates
- [anvil README](https://github.com/Smithay/smithay/blob/master/anvil/README.md)
- [niri](https://github.com/niri-wm/niri), [cosmic-comp](https://deepwiki.com/pop-os/cosmic-comp), [cosmic-epoch](https://github.com/pop-os/cosmic-epoch) — evidence of Smithay's gaps
- [Otto](https://github.com/nongio/otto); `koompi/otto`; [`sd-audit-2026-08-03.md`](sd-audit-2026-08-03.md) (live audit, 2026-08-03)
