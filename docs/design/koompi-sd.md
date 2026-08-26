# KOOMPI SD — stacking desktop

Revised 2026-08-26, after `koompi/otto` was brought into scope.
The earlier draft assumed SD's compositor had to be written; it does not — see [the Smithay study](smithay-study.md).

> **Parked 2026-08-26. KOOMPI HD is the active work.**
> Design is finished and committed; nothing is in flight. See [Picking this back up](#picking-this-back-up) before touching anything.

## Picking this back up

Everything SD lives on branch `koompi-sd` in this repo — five commits, **not pushed** — plus one archive outside it.

**The compositor tree is not on disk.** It was removed on 2026-08-26 and archived whole:

```sh
tar -xzf ~/workspace/otto-archive-20260826.tar.gz -C ~/workspace
```

That restores the clone with its history, all nine tags and the untracked files. `github.com/koompi/otto` still holds everything on `origin/koompi` **except** commit `72e9dbc` (the session audit, since copied here as [`sd-audit-2026-08-03.md`](sd-audit-2026-08-03.md)) and the tag `koompi-sd-0.16.0`, which exist only in that archive.

**Do this first, before any code.** The `layers` licence ask, and the Smithay patch offer, are one conversation with one maintainer — and the hard fork removes the standing to have it. It gates cutting `koompi/layers` at all. See [Licence](sd-hardfork.md#licence).

**Then, in order:** the session smoke test, the `/etc/skel` package split, the session identity move. Those three improve HD too, and none of them needs the compositor tree restored. Full sequence in [the hard fork plan](sd-hardfork.md#order-of-operations).

**Known state:**

- `sdata/dist-arch/koompi-sd/PKGBUILD` is correct but unbuildable — it sources tag `koompi-sd-0.16.0`, which is only inside the archive. That resolves when the repo restart creates `koompi/koompi-sd`.
- The branch is behind `main` (11 commits at the time of parking) and was left that way, because the working tree held unrelated HD changes. It touches only `docs/design/` and `sdata/dist-arch/koompi-sd/`, so a rebase cannot conflict — do it on resume.
- `main` is checked out in the herdr worktree `lead-verify`, so this clone stays on `koompi-sd`. HD work happens in the worktrees.

## Scope

**SD is** a stacking desktop for KOOMPI OS: **Otto** as its Wayland compositor, Otto's Rust components as its shell, KOOMPI's Zig daemons behind them, running GTK and Qt applications natively.

Otto is a Smithay-based stacking compositor written in Rust on LayersEngine and Skia.
KOOMPI has forked it (`koompi/otto`, branch `koompi`), packaged it, and run it live on this hardware.
As of 2026-08-26 it is being **hard forked** — no further upstream tracking; see [the hard fork plan](sd-hardfork.md).
SD is the *flavour*; Otto is the compositor it runs on, exactly as Hyprland is the compositor HD runs on.

**SD is not** a fork of GNOME or Plasma, a reskin of HD, or a second QML shell.
It shares no UI code with HD.

**HD stays.** HD is the Hyprland tiling desktop that ships today.
SD does not replace it; the two are selectable sessions on one install.

The names are keyed to behaviour, not implementation: hd is tiling, sd is stacking.
HD runs on Hyprland *now*; the name survives a compositor swap, and so does SD's if it ever needs one.

## The two-flavour model

### Session identity

Today `koompi-session` exports `XDG_CURRENT_DESKTOP="KOOMPI:Hyprland"`.
Proposed: three tokens, most specific first.

- HD — `KOOMPI-hd:KOOMPI:Hyprland`
- SD — `KOOMPI-sd:KOOMPI`

`xdg-desktop-portal` walks those tokens in order and takes the first `<token>-portals.conf` it finds, so a flavour can override the shared `koompi-portals.conf` without duplicating it.
The same ordering gives `.desktop` `OnlyShowIn` a flavour-precise value.
The compositor token stays last, and is the only part that moves when a compositor is swapped.

### Greeter

`sdata/dist-arch/koompi-session/sddm-sessiondir.conf` already pins SDDM to `/usr/share/koompi/wayland-sessions`.
Adding SD is a second entry in that directory.
This is the smallest part of the whole design and needs no change to the mechanism.

### Package layout

The two current editions cannot coexist: `koompi-hyprland-config` declares `conflicts=('koompi-kde-config')` because both write `/etc/skel`.
Flavours must coexist, so config packages have to own disjoint paths.

Proposed split — names provisional:

| package | owns |
| --- | --- |
| `koompi-desktop-config` | shared: theming, branding, GTK/Qt settings, fonts, cursor. Conflicts with nothing. |
| `koompi-hd-config` | `~/.config/hypr`, `~/.config/quickshell/koompi` |
| `koompi-sd-config` | `~/.config/otto` |
| `koompi-desktop-hyprland`, `koompi-desktop-sd` | edition metapackages, both installable at once |
| `koompi-hyprland`, `koompi-sd` | the compositor and its components |

`koompi-desktop-kde` and `koompi-kde-config` are retired rather than kept as a third flavour — see [KDE](#kde).

## Layers

| layer | component | language |
| --- | --- | --- |
| L0 | Otto compositor | Rust, Smithay (forked) |
| L1 | `koompi-sd-bar`, `-islands`, `-lock`, `-greeter`, dock | Rust, Skia |
| L2 | services | Zig daemons where KOOMPI adds one |
| — | theming, `koompi` CLI, branding, session/packaging | shared with HD |

The rule that makes this work: nothing above L0 reaches the compositor except through a Wayland protocol or a documented IPC.

### Where the Zig daemons fit now

The earlier draft had SD and HD sharing one Zig service layer as the main economy.
Otto changes that: it already carries its own notification daemon (`otto-islands`), its own lock and greeter, and its own portal backend, all in Rust.
Rewriting those in Zig would be destruction, not reuse.

The honest rule: **Otto's components stay Otto's; the Zig daemons cover what KOOMPI adds and HD already depends on.**
`audiod` is the model — it binds `libpipewire` and speaks NDJSON, and an Otto component can be a client of it as easily as a QML one.
Where Otto has no answer and KOOMPI needs one, write it once in Zig and let both flavours drive it.
Where Otto already answers, use Otto's.

## The daemon contract

This already exists, and it is the strongest asset SD inherits.
`audiod` is Zig linking `libpipewire` and speaking NDJSON over stdio; `audiod/PROTOCOL.md` is the contract rather than the Zig source, and `test_daemon.py` is the conformance test.

SD's rule: every service is a Zig daemon with a `PROTOCOL.md` and a conformance test, and both HD's QML and SD's Rust are clients of it.
A service only one flavour can drive is a design error.

| daemon | status | talks to |
| --- | --- | --- |
| `audiod` | exists | libpipewire (C) |
| `globalmenu` | exists | AppMenu D-Bus |
| notifications | new | `org.freedesktop.Notifications` |
| network | new | NetworkManager D-Bus |
| power | new | logind + UPower D-Bus |
| input | new | compositor IPC |

**D-Bus in Zig is the one unsolved piece.**
`audiod` avoided it by binding PipeWire's C API directly; three of the four new daemons cannot.
Zig has no mature D-Bus binding, so the practical route is `sd-bus` from libsystemd through C interop, which Zig handles well.
Decide it once in a shared module rather than four times.

## Application compatibility

Compatibility is protocol work in L0, and Otto carries it — xdg-shell, xdg-decoration with real server-side title bars, XWayland, clipboard and drag-and-drop, `ext-session-lock`, `text-input-v3` and `input-method-v2` for fcitx5 and Khmer, `wlr-layer-shell`, and its own `wlr-screencopy` and `wlr-foreign-toplevel-management`.
The full scoring is in [the Smithay study](smithay-study.md#scored-against-otto).

Two protocol gaps remain and both have a visible consequence:

- **`wlr-output-management`** — Otto has `xdg-output` only and configures displays from `config.toml`. No `wlr-randr`, no `wdisplays`, and no standard path for a display-settings panel.
- **`ext-workspace-v1`** — Otto's workspaces are internal and exposed to no client, so nothing outside the compositor can show or switch them.

Neither blocks a login. Both block a settings UI.

### Theming GTK and Qt

Free, if SD joins the pipeline that exists.
`dots/.config/matugen/config.toml` already fans out to `gtk-3.0`, `gtk-4.0`, `qt6ct` and `kdeglobals`.
SD adds one `[templates.*]` entry for its own colours and inherits the rest.
A second theming path would be a defect, not a variant.

### Portals

SD's backend is `xdg-desktop-portal-koompi-sd` — the renamed `xdg-desktop-portal-otto`, which already exists in the tree.
`FileChooser` stays with the GTK portal until SD has a file manager of its own.

Its `Settings` implementation is incomplete — it answers `color-scheme` and `icon-theme` and nothing else, so GTK4 applications get no cursor theme, cursor size or accent colour from it.
That matters more than it looks: `Settings` is how a toolkit-native or sandboxed application learns the colour scheme, and it is the other half of theming GTK and Qt.
Finishing it is small and upstreamable.

Two traps the live audit already paid for, recorded so this repo does not re-create them:

- A curated `XDG_DESKTOP_PORTAL_DIR` — HD ships one, listing `gtk`, `hyprland`, `koompi`, `kwallet`, `gnome-keyring` — makes `otto.portal` invisible, and the Settings request falls through to GTK, which answers *light*. A whitelisted portal directory silently breaks every session whose backend is not in it. This is why the session identity work is not cosmetic.
- HD's own `koompi-portals.conf` names a `koompi` backend for `RemoteDesktop` that nothing in this tree builds and nothing installs, so RemoteDesktop is unimplemented on HD today.

## Shared and separate

| | HD | SD | shared |
| --- | --- | --- | --- |
| compositor | Hyprland | Otto (Smithay) | no |
| shell UI | Quickshell (QML) | Otto components (`otto-kit`/Skia) | no |
| services | Zig daemons | Otto's own, plus the shared Zig ones | partly |
| theming | matugen pipeline | same | yes |
| CLI | `koompi` (Zig) | same | yes |
| branding, wallpapers | | | yes |
| portal backend | hyprland + gtk | `xdg-desktop-portal-otto` + gtk | no |
| user config | `~/.config/hypr`, quickshell | `~/.config/otto` | no |
| session entry | `koompi-hd.desktop` | `koompi-sd.desktop` | no |
| compositor package | `koompi-hyprland` | `koompi-sd` | no |

The shared column is the entire economic argument for SD being a flavour.
If it shrinks, SD has become a second distribution that happens to share a name.

## Library choices

All three are settled by adopting Otto, and none of them is now KOOMPI's to make:

- **Compositor toolkit** — Smithay, via Otto's fork `nongio/smithay` on `feat/dmabuf-scanout`.
- **Shell UI** — `otto-kit`, Skia-based, on LayersEngine. This closes what the earlier draft called the decision that shapes L1; iced, gpui and slint are moot.
- **Services** — Zig for what KOOMPI adds, as `audiod`, `cli`, `globalmenu` and `installer` already do.

The cost of that settlement is named in the study: two upstreams to track, a one-maintainer project above KOOMPI, and a rendering stack no other desktop uses.

## Staging

[`sd-audit-2026-08-03.md`](sd-audit-2026-08-03.md) is the authority on what Otto itself needs, audited live on 2026-08-03, and it should not be restated here.
What belongs to *this* repo is the flavour work:

1. ~~**Land the packaging as `koompi-sd`.**~~ **Done** — `sdata/dist-arch/koompi-sd/PKGBUILD`, sourcing a tag rather than a pinned SHA. The tag still needs pushing to `koompi/otto` before anyone else can build it.
2. **Package split.** Break the `/etc/skel` conflict into shared plus per-flavour config packages, so HD and SD can sit on one disk.
3. **Session identity.** Move HD to `KOOMPI-hd:KOOMPI:Hyprland` and add `KOOMPI-sd:KOOMPI`, with the SD entry in `/usr/share/koompi/wayland-sessions`. Fixes the portal-directory trap the Otto audit hit, where a curated `XDG_DESKTOP_PORTAL_DIR` from the Hyprland era made `otto.portal` invisible.
4. **Shared theming.** Add SD's colours as a `[templates.*]` entry in `dots/.config/matugen/config.toml` so one `koompi theme` call moves both flavours, and SD's `theme_scheme` follows the same source as HD.
5. **A session smoke test** in `tests/`: portal colour scheme, bar count against output count, SNI count, and that the bar, the notification daemon and the polkit agent are alive. The Otto audit notes this would have caught three of its four blockers.

Steps 2, 3 and 4 improve HD too.
Step 1 is the one that is currently blocking, and it is small.
## KDE

`koompi-base` depends on `koompi-kde` — dolphin, kdialog, gnome-keyring, NetworkManager — and *both* editions inherit it.
"Not KDE" needs that dependency split first: the genuine services (gnome-keyring as the Secret Service, NetworkManager) belong in the base, the KDE application layer belongs to whichever flavour still wants it.

Note what the name hides.
SD runs Qt applications and has to theme them.
Not being KDE is about not depending on Plasma's shell, its services or its frameworks — not about keeping Qt off the machine.

## Open decisions

1. **Design language.** Otto is explicitly macOS-inspired, and `otto-plan.md` records that as a deliberate brief. SD inherits it or diverges permanently — decide, rather than drift.
2. **The hard fork's own decisions** — the compositor's name, whether Smithay's patches are rebased onto upstream or forked, whether the Wayland protocol interfaces are renamed, and whether the tree is relicensed GPL-3.0. All four are in [the hard fork plan](sd-hardfork.md).
3. **`/etc/skel` model.** Does every user get both flavours' dotfiles, or does first login of a flavour seed its own config?
4. **Installer.** Does `koompi-desktop-experience` pull both flavours, or does the installer ask?
5. **Support window.** Does HD's Quickshell shell stay supported on Otto — a third combination to test — or is SD Otto-components-only?

## Risks

- **The fork inherits a renderer nobody has read.** LayersEngine — 22k lines of Skia scene graph, one project wide — is now KOOMPI's, and every pixel goes through it.
- **Two dependency branches still point at an account KOOMPI does not control** (`nongio/smithay`, `nongio/layers`). Until they are forked or rebased, a force-push upstream can stop the build. This is the fork's first real task, not a cleanup.
- **The audit's blockers are real.** A bar on one output only, and no application publishing a global menu, are both "this is not a finished desktop" faults, not polish.
- **Testing doubles.** Every shared change — theming, packaging, session, the Zig daemons — needs verifying on two flavours, and `otto --winit` is useless for the parts that actually break (portal routing, D-Bus names, KMS planes, multi-output).
