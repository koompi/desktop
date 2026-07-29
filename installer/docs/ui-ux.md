# KOOMPI installer — UI/UX & universality spec

> **Status: design spec, not yet built.** This is the durable design for the
> installer's *face* (the TUI). The Zig binary under `installer/src/` is a
> deferred scaffold (see `installer/README.md`) — nothing here is wired to a
> real disk operation yet. This document is the contract the face is built
> against.

The KOOMPI installer is a **beautiful terminal-UI installer** that runs on a
bare console, collects a distro-neutral set of answers, and hands them to a
pluggable engine that does the dangerous work. Two decisions anchor the whole
design:

1. **Beautiful TUI first.** A Zig + [libvaxis](https://github.com/rockorager/libvaxis)
   text UI that is gorgeous on truecolor terminals and still fully usable on a
   bare 80×24 framebuffer console — the most universal target there is. No GUI
   stack, no browser, no display server required to install.
2. **KOOMPI-first, themeable.** Built for KOOMPI OS — Naga today, but every
   KOOMPI-specific byte (brand, palette, glyphs, default locale/timezone, the
   desktop "editions") lives in a single `theme.toml`, and every distro-specific
   *mechanism* lives behind an `Engine` interface. Another distro rebrands by
   dropping in a theme + logo + engine adapter, touching **zero** face code.

That combination is the thesis: **one face, many distros.** The face knows how
to ask questions beautifully and nothing else; branding is config, and the
install mechanism is a plugin.

## How this document is organized

- **§1 Screens** — the authoritative 10-screen flow, per-screen mockups,
  fields, validation, auto-fill, error states, and the single destructive gate.
- **§2 Visual & theme system** — chrome, the 12 color tokens, the `theme.toml`
  presentation schema, glyph/Nerd-Font fallback, motion, and accessibility tiers.
- **§3 Architecture** — the face / engine / spec seams (`InstallSpec`, the
  `Engine` interface, `Profile`, the progress channel) that make it universal.
- **§4 Lessons from existing installers** — what we adopted from Subiquity,
  archinstall 4.0, Calamares, and Charm, and the anti-patterns we avoid.
- **The theme file, reconciled** + **Roadmap** close the document.

The shipped KOOMPI theme is [`installer/themes/koompi.toml`](../themes/koompi.toml)
(parse-verified). Where this doc shows a `theme.toml` fragment, that file is the
source of truth.

---
## Screens — detailed spec

Ten screens, linear and back-navigable. The forward order here is the
**authoritative** one: Language → Welcome → Keyboard & region → Disk →
Encryption → Account → Desktop → Review → Install → Done. (The current
`installer/src/main.zig` `Step` enum folds locale/timezone/keymap into
one step and orders `disk → identity → edition → encrypt`; it needs
reordering to match this spec — Encryption moves before Account/Desktop,
and Language/Keyboard split with Welcome between them.)

### Shared chrome (drawn once, omitted from per-screen mockups)

Every screen has the same frame: a brand header, a left vertical
stepper rail (done `●` / current `▶` / upcoming `○`), the screen body,
and a per-screen keybind footer. The mockups below show the **body
only**; the footer is listed per screen. This is the reference frame:

```
┌────────────────────────────────────────────────────────────────────┐
│  KOOMPI · Naga                                  koompi-installer    │
├──────────────────┬─────────────────────────────────────────────────┤
│  ● Language      │                                                  │
│  ● Welcome       │                                                  │
│  ▶ Keyboard      │                  SCREEN BODY                     │
│  ○ Disk          │              (mockups below show                 │
│  ○ Encryption    │               this region only)                  │
│  ○ Account       │                                                  │
│  ○ Desktop       │                                                  │
│  ○ Review        │                                                  │
│  ○ Install       │                                                  │
│  ○ Done          │                                                  │
├──────────────────┴─────────────────────────────────────────────────┤
│  ↑↓ move   Enter next   Esc back   F1 help   Ctrl-C quit            │
└────────────────────────────────────────────────────────────────────┘
```

Footer conventions: `Enter` advances, `Esc` goes back (disabled on
screen 1), `Ctrl-C` quits with confirm. Per-screen footers below list
only the screen-specific keys plus the always-present nav keys.

---

### 1 · Language

**Purpose:** pick the install/UI language; seeds locale and is the only
screen with no Back.

```
  Choose your language / ជ្រើសរើសភាសា

  > English                       (en_US.UTF-8)
    ភាសាខ្មែរ  Khmer              (km_KH.UTF-8)
    Français                      (fr_FR.UTF-8)
    简体中文  Chinese (Simplified) (zh_CN.UTF-8)
    Tiếng Việt  Vietnamese        (vi_VN.UTF-8)

  Type to filter:  ____
```

**Fields:** single-select list of languages.
- **Default / auto-fill:** highlight defaults to **English
  (`en_US.UTF-8`)**. Selection sets `cfg.locale` and pre-selects a
  matching keymap on screen 3 (e.g. `fr` → `fr`).
- **Validation:** always valid — exactly one row is always selected.
**Empty/error:** none possible (list is non-empty, one row selected).
Type-to-filter with no match shows `(no match — clearing filter)` and
keeps the prior selection.
**Footer:** `↑↓ select   type filter   Enter continue   Ctrl-C quit`

---

### 2 · Welcome

**Purpose:** greet, name the product, and show the detected hardware
summary so the user trusts the machine was probed.

```
  Welcome to KOOMPI OS — Naga

  This installer sets up KOOMPI on this computer. It is fast,
  guided, and you can step back at any time.

  Detected hardware
    CPU      AMD Ryzen 5 7530U  (12 threads)
    Memory   16 GiB
    Disks    nvme0n1  476.9 GiB  WD SN770
             sda      931.5 GiB  Samsung 870 EVO
    Firmware UEFI        Network  Ethernet (up)

  Press Enter to begin.
```

**Fields:** none (informational).
- **Auto-fill:** hardware lines from `lsblk` / `/proc` / `/sys`. The
  disk list previews exactly what screen 4 will offer.
**Empty/error:** if probing fails, show `Hardware probe unavailable —
continuing` rather than blocking; disks are re-probed on screen 4. If
**no disks at all** are found, show a warning here: `No fixed disks
detected — installation will not be possible.`
**Footer:** `Enter continue   Esc back`

---

### 3 · Keyboard & region

**Purpose:** keyboard layout plus timezone (auto from network, editable).

```
  Keyboard layout
  > us        English (US)            preview: asdf 1234
    us-intl   English (US, intl)
    km         Khmer
    fr         French (AZERTY)

  Region / timezone
    Detected:  Asia/Phnom_Penh   (from network)   [✓ use this]
    Change…    [ Asia / ____________ ]

  Time will sync automatically after install.
```

**Fields:** `keymap` (single-select) and `timezone` (detected +
override).
- **Auto-fill:** `keymap` pre-selected from the screen-1 language
  (default **`us`**). `timezone` from geoIP lookup over the live
  network.
- **geoIP offline fallback (no extra screen):** if the lookup fails or
  there is no network, fall back to **`Asia/Phnom_Penh`** and label it
  `Default (no network)` instead of `from network`. The user can still
  override.
- **Validation:** `keymap` must be a known layout (list-constrained);
  `timezone` must match a `zoneinfo` path (`Area/Location`) — the
  override is a filtered picker, not free text, so it can't be invalid.
**Empty/error:** override picker with no match shows `(no such zone)`
and keeps the detected value. Keymap preview field echoes keystrokes so
the user can verify the layout before committing.
**Footer:** `↑↓ select   Tab switch field   Enter next   Esc back`

---

### 4 · Disk — guided (default)

**Purpose:** choose the target disk and layout; **warns** and names the
OS to be erased but is **not** the destructive gate (nothing is written
until Review).

```
  Install location

  ( ) Guided — erase entire disk & auto btrfs   ← recommended
  ( ) Manual partitioning

  Target disk
  > nvme0n1   476.9 GiB  WD SN770    ⚠ contains: Windows 11
    sda       931.5 GiB  Samsung 870 EVO   (empty)

  ⚠ The selected disk will be ERASED, removing Windows 11.
    Nothing is changed until the final Review step.

  Resulting layout (btrfs)
    /boot  ESP  512 MiB  fat32
    /      @          @home      @var_log
           @var_cache @snapshots
```

**Fields:** mode radio (Guided / Manual), `disk_path` (single-select
from `lsblk`), filesystem (fixed **btrfs** in guided).
- **Columns:** NAME, SIZE, MODEL from `lsblk -d -o NAME,SIZE,MODEL`;
  plus a probed `contains:` tag naming any existing OS/partition table.
- **Default:** mode = **Guided**; no disk pre-selected (the user must
  consciously pick — `Next` stays disabled until one is chosen). fs =
  **btrfs**, the KOOMPI default. The five subvolumes are fixed: **`@`,
  `@home`, `@var_log`, `@var_cache`, `@snapshots`** (matches
  `archinstall.zig`).
- **Validation:** a disk must be selected; it must be large enough
  (≥ ~20 GiB) for the layout.
**Empty/error:**
- *No disk selected* → `Next` disabled, hint `Select a disk to
  continue.` (soft — back-navigable, non-destructive).
- *No disks found* → **hard stop**: `No installable disks detected.
  Connect a disk and restart the installer.` `Next` unavailable.
- *Disk too small* → row marked `(too small for KOOMPI)` and
  unselectable.
**Safety design (Disk):** Disk only **warns** and **names** the OS it
will erase. It performs no writes and sets no irreversible state — the
single destructive confirmation lives on Review (screen 8).
**Footer:** `↑↓ select disk   Space pick mode   Enter next   Esc back`

---

### 4 · Disk — manual partitioning (variant)

**Purpose:** for users who want explicit partitions — kept as a
**constrained table**, not a free-form editor, so it can't produce a
layout archinstall can't express.

```
  Manual partitioning — nvme0n1  (476.9 GiB)   [switch to guided]

  #  PART      SIZE      FS      MOUNT     FLAGS
  > 1 (new)    512 MiB   fat32   /boot     boot, esp
    2 (new)    rest      btrfs   /         —
         └ subvols: @ @home @var_log @var_cache @snapshots
    ·  free     2.0 GiB   —       —         —

  Required:  ✓ ESP (fat32, /boot)   ✗ root mountpoint (/)
  → Add a partition mounted at / to continue.
```

**Fields per row:** size, `fs_type`, `mountpoint`, `flags`. The root
partition exposes the same fixed five btrfs subvolumes (nested under the
root partition, mirroring archinstall's `device_modifications` →
`partitions[].btrfs`). No knobs beyond what KOOMPI uses (no LVM, no RAID,
no arbitrary mount options).
- **Actions:** `n` new · `e` edit · `d` delete · highlight `free` to
  allocate it. `[switch to guided]` returns to the guided variant
  without losing the disk choice.
- **Validation (inline, live):**
  - Exactly one **ESP**: `fat32` + `esp` flag, mounted `/boot` (or
    `/efi`). Missing → red `✗ ESP`.
  - Exactly one **root** mountpoint `/`. Missing → red `✗ root`.
  - No overlapping ranges; sizes must fit; free space shown as a row.
  - `Next` disabled until both required checks are `✓`.
**Empty/error:** an empty table shows `No partitions yet — press n to
add one` and both requirement checks red. An invalid edit (e.g. size >
free) is rejected inline with `(exceeds free space)` and the prior value
restored.
**Safety design:** same as guided — **still no writes here**. Manual
layout is only serialized at Review→Install.
**Footer:** `n new  e edit  d delete  g guided   Enter next  Esc back`

---

### 5 · Encryption

**Purpose:** optional full-disk LUKS toggle.

```
  Disk encryption (LUKS)

  [ ] Encrypt this disk with a password

  When ON, the whole disk is locked with LUKS. You'll enter a
  passphrase at every boot. If you forget it, the data cannot
  be recovered.

  Passphrase        ••••••••••          [ show ]
  Confirm           ••••••••            ✗ doesn't match yet
  Strength          ▓▓▓▓░░░░  fair
```

**Fields:** `encrypt` toggle; passphrase + confirm (shown only when ON).
- **Default:** **OFF** (`cfg.encrypt = false`). When OFF, the passphrase
  fields are hidden and the screen is a single toggle.
- **Validation (when ON):** passphrase ≥ 8 chars; confirm must match;
  strength meter (length + variety) shown but non-blocking below
  "weak". `show` reveals/masks both fields.
**Empty/error:**
- *ON but passphrase empty* → `Next` disabled, `Enter a passphrase.`
- *Mismatch* → `✗ doesn't match yet` under Confirm, `Next` disabled.
- *Too short* → `At least 8 characters.`
This passphrase is the **disk** secret; it is distinct from the account
password (screen 6) and is handed to archinstall's `disk_encryption`
block, never logged.
**Footer:** `Space toggle   Tab switch field   Enter next   Esc back`

---

### 6 · Account

**Purpose:** create the primary user. **There is no root-password
screen** — root is left **LOCKED** by design (`archinstall.zig`); this
user is the sudoer and the only login.

```
  Your account

  Full name   [ S␣Pisey________________ ]
  Username    [ pisey______ ]   auto from full name · editable
  Hostname    [ koompi-pc__ ]   default: koompi
  Password    [ •••••••••• ]   [ show ]   strength ▓▓▓▓▓▓░░ good
  Confirm     [ •••••••••• ]   ✓ matches

  [✓] This user can administer the system (sudo)
```

**Fields:** `full_name`, `username`, `hostname`, `password`, confirm,
sudo toggle.
- **Auto-fill / derivation:**
  - `username` derived live from `full_name`: lowercase, strip
    accents/spaces, keep `[a-z0-9_-]` — `"Sok Pisey"` → `pisey` (first
    token) or `sokpisey`; editable, and stops auto-deriving once the
    user types in it manually.
  - `hostname` default **`koompi`**; if the user edits username,
    suggest `koompi-<username>` but keep `koompi` as the fallback.
  - sudo toggle **ON** by default (this user must be able to administer,
    since root is locked) — if the user turns it OFF, warn
    `⚠ With root locked, no one could gain admin. Keep sudo on?`
- **Validation:**
  - `username`: `^[a-z_][a-z0-9_-]*$`, length ≤ 32, not a reserved name
    (`root`, `daemon`, …). Maps to creds key **`!password`**.
  - `hostname`: `^[a-z0-9][a-z0-9-]*$`, ≤ 63, no leading/trailing `-`.
  - `password`: non-empty; confirm must match; strength meter shown.
**Empty/error:**
- *Empty full name* → username can't derive: placeholder `username` is
  empty and shows `Enter a name, or type a username.`
- *Invalid username* → `Only a–z, 0–9, _ and -; must start with a
  letter.`
- *Invalid hostname* → `Letters, numbers and - only.`
- *Password mismatch* → `✗ doesn't match` under Confirm; `Next`
  disabled until name, username, hostname, and a matching password are
  all valid.
**Footer:** `Tab next field   ^U clear   F2 show/hide pw   Enter next`

---

### 7 · Desktop

**Purpose:** pick the edition (the one mutually-exclusive
`koompi-desktop-*` metapackage).

```
  Choose your desktop

  ┌──────────────────────┐   ┌──────────────────────┐
  │  ▶ KOOMPI Hyprland   │   │    KOOMPI KDE        │
  │  [ preview thumb ]   │   │  [ preview thumb ]   │
  │  Fast, keyboard-     │   │  Familiar, mouse-    │
  │  driven, animated    │   │  friendly Plasma     │
  │  Quickshell bar      │   │  Single top panel    │
  └──────────────────────┘   └──────────────────────┘

  Both: top panel · no dock · no global menu.
  Selected: KOOMPI Hyprland  →  koompi-desktop-hyprland
```

**Fields:** `edition` — radio between two cards.
- **Default:** **KOOMPI Hyprland** (`cfg.edition = .hyprland`).
- **Auto-fill:** selection maps to the package via
  `archinstall.targetPackage()` — Hyprland →
  `koompi-desktop-hyprland`, KDE → `koompi-desktop-kde`. The screen
  only sets the enum; the package name is shown for transparency.
- **Validation:** always exactly one card selected (radio).
**Empty/error:** none possible. Preview thumbnails that fail to load
fall back to an ASCII placeholder box; the choice remains valid.
**Footer:** `←→ choose edition   Enter next   Esc back`

---

### 8 · Review

**Purpose:** the **single destructive confirmation** — the only screen
that authorizes any write. Hold-to-install, escalating to type-to-confirm
when an existing OS will be destroyed.

```
  Review — nothing has been changed yet

  Edition    KOOMPI Hyprland   (koompi-desktop-hyprland)
  Disk       nvme0n1  476.9 GiB     ⚠ ERASES Windows 11
  Layout     btrfs  @ @home @var_log @var_cache @snapshots
  Encryption ON (LUKS)
  Account    pisey   (sudo)     Hostname  koompi-pc
  Language   English   Region  Asia/Phnom_Penh   Keys  us

  This will ERASE nvme0n1 and everything on it (Windows 11).

  To install, type the disk name to confirm:
    [ nvme0n1_ ]   then hold Enter
    Installing in ███████░░░  hold to continue…
```

**Fields:** a confirmation gate (no editable settings — every row links
back to its screen with `Esc`/selection).
- **Safety design (the destructive gate):**
  - **Hold-to-confirm:** hold `Enter` ~3 s; a progress bar fills.
    Releasing early cancels. This prevents an accidental single
    keystroke from wiping a disk.
  - **Escalation — type-to-confirm:** if an **existing OS** was detected
    on the target (Disk screen), require typing the disk node (e.g.
    `nvme0n1`) *before* the hold is accepted. On an empty disk, the hold
    alone suffices. (Generic fallback word `ERASE` if the node string is
    ambiguous.)
  - The OS to be erased is **named on both Disk and Review**.
- **Validation:** the typed string must equal the target node exactly
  (case-sensitive) before the hold arms.
**Empty/error:** if `cfg.isComplete()` is false (missing disk, username,
password, or hostname), Review shows the incomplete rows in red with
`Fix this before installing →` jumping back to the screen, and the
confirm gate is disabled. A wrong type-to-confirm string shows `Name
doesn't match — type "nvme0n1".`
**Footer:** `Hold Enter to INSTALL   Esc back   (type to confirm)`

---

### 9 · Install

**Purpose:** run the install — phased progress, live scrollable log, ETA.
No back/cancel once writes begin.

```
  Installing KOOMPI — Naga

  [1] Partition & format        ✓ done
  [2] Encrypt (LUKS)            ✓ done
  [3] Install base + edition    ▶ 62%   ~4m left
  [4] Bootloader (GRUB)         · pending
  [5] Snapshots & finishing     · pending

  Overall  ████████████░░░░░░░░  58%      ETA ~6m

  Log  (↑↓ scroll, End to follow)
   ┌──────────────────────────────────────────────────┐
   │ installing koompi-desktop-hyprland (142/418)…     │
   │ downloading quickshell-git…                        │
   │ ▒ tail follows newest line                         │
   └──────────────────────────────────────────────────┘
```

**Fields:** none — read-only progress. Phases map to the orchestration
in `archinstall.zig` (`runArchinstall` then `runPostInstallHook`):
partition/format, LUKS, pacstrap+edition, GRUB, then the chroot hook
(snapper/`@baseline`, snap-pac, grub-btrfs, sddm, os-release).
- **Behavior:** per-phase status + a follow-the-tail scrollable log;
  ETA from package count/bytes. `Esc`/Back are **disabled** here.
**Empty/error (install failure):** on a non-zero exit, **do not
reboot**. Switch the failed phase to `✗ failed`, auto-scroll the log to
the error, and show:
```
  ✗ Install failed at [3] Install base + edition.
    The disk may be in a partial state. Nothing will reboot.
    [ View full log ]   [ Copy log path ]   [ Quit ]
```
The credentials file is shredded (`cleanupCredentials`) even on this
path.
**Footer:** `↑↓ scroll log   End follow   (install in progress…)`

---

### 10 · Done

**Purpose:** confirm success and reboot; note the factory-reset snapshot.

```
  KOOMPI is installed 🎉

  KOOMPI Hyprland (Naga) is ready on nvme0n1.

  • Log in as  pisey  with your password.
  • A read-only @baseline snapshot was pinned — your factory
    reset point. Restore it any time to return to a fresh
    install.

  Remove the installation media, then reboot.

       [ Reboot now ]        [ Stay in live session ]
```

**Fields:** two actions — reboot, or stay in the live session.
- **Default:** `Reboot now` focused.
- **Auto-fill:** summarizes the chosen edition, target disk, and login
  username; states the pinned read-only **`@baseline`** snapshot from
  the post-install hook as the factory-reset point.
**Empty/error:** none — this screen is only reached on success. Choosing
`Reboot now` issues the reboot; `Stay` drops to the live shell with a
hint to `reboot` manually.
**Footer:** `←→ choose   Enter confirm   (installation complete)`

---

> **Glyph note.** The mockups above use `●  ▶  ○` for the stepper rail for
> legibility. Those glyphs are **themeable** — the canonical values live in the
> `[glyphs]` table of §2 (`✓  ▶  ·`) and ship in `installer/themes/koompi.toml`.
> Where a mockup and the `[glyphs]` table disagree, the table wins.

---
## Visual & theme system

The installer's look is **owned entirely by a single `theme.toml`**. The
Zig binary ships zero hard-coded colors, glyphs, or logo paths — every
visible byte routes through the active theme. This is the rebranding
seam: another distro forks KOOMPI OS by dropping in one `theme.toml`,
one logo, and an engine adapter. Nothing else changes.

### Persistent chrome

Every screen draws the same three regions: a full-width **brand header**,
a left **stepper rail**, and a full-width **keybind footer**. The content
panel fills the space between rail and right edge.

Layout is budgeted to survive a real **80×24** console and never exceeds
**72 columns** of drawn width. Column budget: rail = 20 cols (incl. its
right border), content panel = the remainder. Row budget: header = 3,
footer = 2, leaving ≥19 rows for the rail's 10-step list + content.

```
┌──────────────────────────────────────────────────────────────────┐
│  ◆ KOOMPI OS · Naga          Install                    en · UTC+7 │
├────────────────────┬───────────────────────────────────────────────
│  ✓ Language        │                                              │
│  ✓ Welcome         │   Choose your edition                        │
│  ▶ Keyboard        │                                              │
│  · Disk            │   ▸ KOOMPI Hyprland                           │
│  · Encryption      │     KOOMPI KDE                                │
│  · Account         │                                              │
│  · Desktop         │                                              │
│  · Review          │                                              │
│  · Install         │                                              │
│  · Done            │                                              │
├────────────────────┴───────────────────────────────────────────────
│  ↑↓ move   ⏎ continue   esc back   ^C quit                        │
└──────────────────────────────────────────────────────────────────┘
```

Rail state glyphs: **done `✓`**, **current `▶`**, **upcoming `·`**.
The selected-row marker in the content panel is **`▸`** — the same glyph
used as the colorblind-safe selection affordance (see Accessibility); it
is one affordance, not two. Header carries the **logo glyph + product +
era**; footer is the per-screen keybind list. All four glyphs come from
`[glyphs]` and have ASCII fallbacks (see Typography).

### Color tokens

Twelve named tokens. The binary references tokens **only by name** —
never a literal hex value. Anchored on the KOOMPI brand blue
**`#1793D1`** = `rgb(23, 147, 209)`, which is exactly the `ANSI_COLOR`
in `os-release` and `post_install.sh`: **`38;2;23;147;209`**.

| Token         | Truecolor  | Role                                   |
|---------------|------------|----------------------------------------|
| `bg`          | `#0B0E14`  | Screen background                      |
| `surface`     | `#161B22`  | Panels, rail, input fields             |
| `brand`       | `#1793D1`  | Logo, header, primary emphasis         |
| `brandAlt`    | `#0F6FA8`  | Brand gradient/borders, hover          |
| `text`        | `#E6EDF3`  | Primary foreground                     |
| `textDim`     | `#8B98A5`  | Upcoming steps, hints, disabled        |
| `accent`      | `#56C2E6`  | Focus rings, links, spinner            |
| `success`     | `#3FB950`  | Done steps, completed phases           |
| `warn`        | `#D6A015`  | Cautions, password-strength medium     |
| `danger`      | `#E5534B`  | Destructive ("WILL BE ERASED"), errors |
| `selectionBg` | `#1793D1`  | Selected-row background                |
| `selectionFg` | `#06121A`  | Selected-row foreground                |

`brand`/`selectionBg` are intentionally the same blue; selection is also
marked by glyph so it never relies on color alone.

### `theme.toml` schema

Every key is required unless marked optional; the binary fails closed
with a named error if a token is missing (no silent default). Order of
sections is free. Colors are `#RRGGBB`. Glyphs are single grapheme
clusters (may be Nerd-Font private-use codepoints).

```
[meta]
name            = string   # human label, shown nowhere user-facing
brand_ansi      = string   # SGR params for os-release parity, e.g.
                           # "38;2;23;147;209" — must match colors.brand

[logo]
path            = string   # absolute path to a logo asset (banner art)
fallback_glyph  = string   # 1 glyph for header when art can't render

[font]
nerd_fallback   = bool     # true = Nerd-Font icon set is available;
                           # false = force the ASCII column everywhere.
                           # THIS FLAG selects which column of the
                           # icon/glyph fallback table is used.

[colors]                   # all 12 tokens, each "#RRGGBB"
bg = … ; surface = … ; brand = … ; brandAlt = … ; text = … ;
textDim = … ; accent = … ; success = … ; warn = … ; danger = … ;
selectionBg = … ; selectionFg = …

[glyphs]                   # box-drawing + stepper + selection + motion,
                           # all themeable so a rebrand edits the FILE,
                           # not the binary.
# box drawing
tl = ; tr = ; bl = ; br = ; h = ; v = ;
tee_l = ; tee_r = ; cross = ;
# stepper rail
step_done = ; step_current = ; step_upcoming = ;
# selection (content panel) — same glyph as accessibility marker
select = ;
# icons (Nerd-Font column; ASCII when font.nerd_fallback=false)
icon_lang = ; icon_disk = ; icon_lock = ; icon_user = ;
icon_desktop = ; icon_warn = ; icon_ok = ;
# motion
spinner = [ string, … ]    # ordered frames, cycled
progress_full = ; progress_empty = ;
check_pop = [ string, … ]  # ordered frames for the checkmark animation
```

### Sample KOOMPI `theme.toml`

```toml
[meta]
name       = "KOOMPI OS — Naga"
brand_ansi = "38;2;23;147;209"

[logo]
path           = "/usr/share/koompi/installer/logo.txt"
fallback_glyph = "◆"

[font]
nerd_fallback  = true

[colors]
bg          = "#0B0E14"
surface     = "#161B22"
brand       = "#1793D1"
brandAlt    = "#0F6FA8"
text        = "#E6EDF3"
textDim     = "#8B98A5"
accent      = "#56C2E6"
success     = "#3FB950"
warn        = "#D6A015"
danger      = "#E5534B"
selectionBg = "#1793D1"
selectionFg = "#06121A"

[glyphs]
tl = "┌" ; tr = "┐" ; bl = "└" ; br = "┘" ; h = "─" ; v = "│"
tee_l = "├" ; tee_r = "┤" ; cross = "┼"

step_done = "✓" ; step_current = "▶" ; step_upcoming = "·"
select = "▸"

icon_lang = "" ; icon_disk = "" ; icon_lock = ""
icon_user = "" ; icon_desktop = "" ; icon_warn = ""
icon_ok = ""

spinner       = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
progress_full = "█" ; progress_empty = "░"
check_pop     = ["·","∘","○","◉","✓"]
```

### Typography

The UI is built from three glyph classes, all sourced from `[glyphs]`:

- **Box drawing** — light single-line (`┌ ┐ └ ┘ ─ │ ├ ┤ ┼`) for all
  borders, the header/footer rules, and the rail divider.
- **Stepper + selection** — `✓ ▶ · ▸` (done / current / upcoming /
  selected).
- **Icons** — a Nerd-Font set for screen affordances.

The **`font.nerd_fallback` flag is the switch** between the two columns
below. When `true`, the Nerd-Font glyph is drawn; when `false` (plain
console with no patched font), the binary substitutes the ASCII column —
the *same single table*, two columns, selected by that one flag.

| Purpose      | Nerd-Font | ASCII fallback |
|--------------|-----------|----------------|
| Language     ``        | `@`            |
| Disk         ``        | `#`            |
| Encryption   ``        | `*`            |
| Account      ``        | `&`            |
| Desktop      ``        | `%`            |
| Warning      ``        | `!`            |
| OK / done    ``        | `+`            |
| step done    | `✓`       | `x`            |
| step current | `▶`       | `>`            |
| step upcom.  | `·`       | `-`            |
| selection    | `▸`       | `>`            |
| progress     | `█ ░`     | `# .`          |
| spinner      | braille   | `\| / - \`     |
| checkmark    | `◉ ✓`     | `( ) +`        |

### Motion

Motion is subtle, themeable (frames live in `[glyphs]`), and skipped
entirely under degraded tiers (see Accessibility).

| Effect             | Frames / behavior                  | Timing       |
|--------------------|------------------------------------|--------------|
| **Spinner**        | `spinner` frames, cycled           | ~80 ms/frame |
| **Progress fill**  | `progress_full` grows over `empty` | redraw ≤10 Hz|
| **Checkmark pop**  | `check_pop` sequence, once         | ~60 ms/frame |
| **Screen trans.**  | content panel wipe L→R; chrome     | ~120 ms total|
|                    | (header/rail/footer) stays fixed   |              |

Transitions never move the chrome — only the content panel animates, so
the brand header and stepper rail read as a stable frame. ETA on the
Install screen updates on the same ≤10 Hz redraw clock as the progress
fill.

### Accessibility

**Selection never relies on color.** A selected row is marked by the
`select` glyph (`▸`) *and* `selectionBg`/`selectionFg`. Remove all color
and the `▸` marker still identifies the selection unambiguously — the
identical affordance shown in the chrome mockup above.

**Three degradation tiers**, detected at startup and applied per
token-class:

1. **Truecolor** (default) — the `#RRGGBB` tokens and Nerd/Unicode
   glyphs render as specified.
2. **`TERM=linux` / 256-color** — truecolor and Nerd-Font glyphs are
   **not** available. Each token is mapped to its **nearest 16-color
   ANSI** index (`brand`/`selectionBg` → bright blue, `danger` → bright
   red, `success` → green, `warn` → yellow, `text` → bright white,
   `textDim` → gray), and **every glyph falls back to its ASCII column**
   regardless of `font.nerd_fallback`. The hex values do **not** apply
   here.
3. **`NO_COLOR`** (env set) — **monochrome**. No SGR color at all; the UI
   is structure + glyphs only. Selection survives by the `▸` marker
   alone; done/current/upcoming steps are distinguished by `✓ / ▶ / ·`
   (or `x / > / -`), never by color.

**High contrast** — `bg`/`text` and `selectionBg`/`selectionFg` are
chosen for ≥7:1 luminance contrast; `danger` and `warn` are each
distinguishable from `brand` by both hue and the leading icon (`!` warn,
destructive copy spelled out, e.g. "WILL BE ERASED"), so a red/green or
blue/yellow color-vision deficiency never loses meaning.

**Small consoles** — the chrome is laid out for **80×24** and clamps to
**72 columns** of drawn width. Below 80×24 the rail collapses to a
single-line "step N/10" indicator above the content panel and the footer
keybinds wrap; no screen ever requires horizontal scrolling.

---

> **Theme-file note.** The `theme.toml` shown above is the **presentation half**
> (colors, glyphs, fonts, logo). The next section's §4 sketches the
> **branding/defaults/profiles half** (`[brand]`, `[defaults]`, `[[profiles]]`).
> They are two halves of *one* file, merged and parse-verified in
> `installer/themes/koompi.toml` — see **The theme file, reconciled** below.

---
## Architecture — face / engine / spec (the universality seams)

One face, many distros. The TUI is the *face*; it knows how to ask
questions beautifully and nothing else. Everything distro-specific
lives behind four orthogonal seams, each swappable without touching
the face:

| Seam | Owns | Plugged via | Rebrander swaps |
|---|---|---|---|
| **THEME** | presentation, brand identity | `theme.toml` at boot | logo, palette, strings |
| **SPEC** | the neutral answers | `InstallSpec` struct | nothing (it is neutral) |
| **PROFILE** | the payload (package-set + skel) | neutral profile id | their own profile list |
| **ENGINE** | the mechanism (disk + base install) | `Engine` interface | their backend (arch/deb) |

A distro that is not KOOMPI rebrands the installer by dropping in a
`theme.toml` + logo, a set of profiles, and an engine backend. The
face binary is identical. That independence is the whole design.

```
            ┌──────────────────────────────────────────┐
   theme.toml ─▶│              FACE (TUI)             │
  (brand, palette│  libvaxis screens 1..10            │
   default locale)│  fills ↓ ; renders ↑ ; guards once │
            └──────┬──────────────────────────▲────────┘
                   │ InstallSpec (neutral)     │ Progress
                   │  + chosen profile id      │ {phase,pct,log}
                   ▼                           │
            ┌──────────────────────────────────┴────────┐
            │            ENGINE  (plugin)               │
            │  probe_disks · plan_layout ·              │
            │  partition_and_format · install_base ·    │
            │  install_profile · configure_bootloader · │
            │  run_post_install · report_progress       │
            ├───────────────────────┬───────────────────┤
            │ ARCHINSTALL backend   │ PACSTRAP / DEB     │
            │ (collapses ops into   │ backend (expands   │
            │  one --silent exec)   │  each op, future)  │
            └───────────────────────┴───────────────────┘
                            │
                profile id ─┘ resolves to a package-set
                            (koompi-desktop-hyprland | -kde | …)
```

The face fills a spec, hands it to an engine, renders the progress the
engine streams back, and owns exactly one destructive confirmation.
Nothing in the face mentions pacman, JSON, or archinstall.

### 1. `InstallSpec` — the neutral struct the TUI fills

`InstallSpec` is the single source of truth the screens accumulate. It
is **distro-neutral**: no package names, no JSON, no archinstall keys,
no KOOMPI defaults baked in (those arrive from `theme.toml`). It is the
neutral generalization of today's `installer/src/config.zig`
`InstallConfig` — which is *not yet* neutral (it hardcodes
`Asia/Phnom_Penh`, hostname `"koompi"`, and a two-value `Edition`).

```
InstallSpec {
  # ── locale / region (screens 1,3) ───────────────────────
  locale        : string        # e.g. "en_US.UTF-8"
  keymap        : string        # e.g. "us"
  timezone      : string        # auto from network; overridable

  # ── disk (screens 4,5) ──────────────────────────────────
  disk_target   : DiskId        # opaque device id from probe
  disk_mode     : enum { erase_auto_btrfs, manual }
  encryption    : Encryption?   # null = off; else { passphrase }

  # ── account (screen 6) ──────────────────────────────────
  full_name     : string        # username is DERIVED from this
  username      : string        # auto, editable
  hostname      : string        # auto, editable
  password      : Secret        # wiped buffer; never logged
  sudo          : bool

  # ── profile (screen 7) ──────────────────────────────────
  profile       : ProfileId     # neutral id, NOT a package name
}
```

Field-type notes that the scaffold is missing today, reconciled with
the agreed screen flow: `disk_mode` (the guided-vs-manual choice on
screen 4) and `full_name` (screen 6 derives `username`/`hostname` from
it) are **new** fields `config.zig` lacks. `Edition` becomes the neutral
`ProfileId`. `password` is a `Secret` (a zeroed/locked buffer), not the
plain `[]const u8` the scaffold flags as a placeholder. The KOOMPI
default timezone/hostname move out of the struct and into `theme.toml`.

The spec knows the *answers*, never the *mechanism*. Translation into
anything pacman-shaped is the engine's job.

### 2. `Engine` — the backend plugin interface

A backend implements eight operations with a fixed lifecycle. The face
calls them in order; the engine does the dangerous work.

```
interface Engine {
  probe_disks()                 -> [DiskInfo]   # read-only
  plan_layout(spec)             -> Layout       # no writes yet
  partition_and_format(layout)  -> ()           # ⚠ FIRST irreversible op
  install_base(spec)            -> ()
  install_profile(spec.profile) -> ()
  configure_bootloader(spec)    -> ()
  run_post_install(spec)        -> ()
  report_progress(cb)                           # registered up-front
}
```

Ordering / lifecycle: `probe_disks` and `plan_layout` are **pure /
read-only** and run during the wizard (screen 4 needs the disk list
*before* the user chooses). `partition_and_format` is the first
irreversible op and must not be reachable until after Review (§6).
`install_base` → `install_profile` → `configure_bootloader` →
`run_post_install` run strictly in sequence; `report_progress`'s
callback is registered before the destructive phase so every later op
can stream events (§5).

**ARCHINSTALL backend (today) — collapses the interface.** archinstall
absorbs `partition_and_format` + `install_base` + `install_profile` +
`configure_bootloader` into a *single* `archinstall --silent` exec
driven entirely by emitted JSON. The op→file mapping, tied to
`installer/src/archinstall.zig`:

| Engine op | archinstall backend realizes it as |
|---|---|
| `probe_disks` | `enumerateDisks()` — **today lives in `main.zig` (the face) as a stub; the spec moves it into the engine**, where probing belongs |
| `plan_layout` | the `disk_config.device_modifications[]` shape in `writeUserConfiguration()` — **generated from the pinned archinstall's `--dry-run`/save-config**, never hand-fabricated (the `obj_id` UUIDs only archinstall can mint) |
| `partition_and_format` `install_base` `configure_bootloader` | all encoded into `user_configuration.json` (`disk_config`, `kernels`, `bootloader_config`, `disk_encryption`) then `runArchinstall()` |
| `install_profile` | the `packages: ["koompi-desktop-X"]` field of that same JSON |
| (credentials) | `writeUserCredentials()` → `/dev/shm` (tmpfs), `cleanupCredentials()` shreds it |
| `run_post_install` | `runPostInstallHook()` → `arch-chroot` runs `post_install.sh` (snapper, snap-pac, grub-btrfs, `@baseline`, sddm, os-release) |

So the archinstall path is: **emit `user_configuration.json` +
`user_credentials.json` → `archinstall --silent` → `post_install.sh`.**
Five interface ops fold into one exec; that folding is an
implementation detail invisible to the face.

**PACSTRAP / DEBOOTSTRAP backend (future) — expands the interface.**
The same eight ops, opposite granularity: each becomes a discrete
shell step instead of one JSON-driven exec.

| Engine op | pacstrap/debootstrap backend |
|---|---|
| `probe_disks` | parse `lsblk -J` |
| `plan_layout` | compute a GPT + btrfs subvolume plan in-process |
| `partition_and_format` | `sgdisk` + `mkfs.fat`/`mkfs.btrfs` (+ `cryptsetup luksFormat` if encrypted) |
| `install_base` | `pacstrap /mnt base …` **or** `debootstrap stable /mnt` |
| `install_profile` | install the profile's package-set into the target |
| `configure_bootloader` | `grub-install` + `grub-mkconfig` in chroot |
| `run_post_install` | the same `post_install.sh`, run in the target chroot |

Same interface, same `InstallSpec`, same face — only the backend
differs. That is the universality proof.

### 3. `Profile` — generalizing "edition"

A **Profile** is a neutral identifier the face carries; the engine
resolves it to a concrete payload (a package-set + an `/etc/skel`
seed). The face never names a package — it only knows there are *N*
profiles with display metadata (label, preview, glyph) supplied by the
theme.

Today this seam is already half-built: `config.zig`'s `Edition` enum
→ `archinstall.targetPackage()` `switch` is exactly the profile→package
resolution, and `config.zig` already documents *why* it lives there
("the enum→package mapping lives in archinstall.zig as a `switch` so it
cannot drift"). Generalized:

```
ProfileId   = opaque string        # "koompi-desktop-hyprland" today
Profile {
  id          : ProfileId
  label       : string             # "KOOMPI Hyprland" (from theme)
  package_set : [string]           # engine-side; e.g. one metapackage
  skel        : path?              # /etc/skel seed for the profile
}
```

Today: two profiles, `koompi-desktop-hyprland` and `koompi-desktop-kde`,
each a single metapackage (the §2.4 `conflicts=` mechanism enforces one
per machine). Later: a distro ships its own profile list; the face
renders whatever cards the profiles + theme describe. The face holds
the neutral `ProfileId`; package resolution stays in the engine.

### 4. Where THEME and BRANDING plug — `theme.toml` at boot

The face reads `theme.toml` **once at startup, before the first draw**.
It supplies everything that is KOOMPI-specific today and hardcoded in
the scaffold:

```
[brand]
name      = "KOOMPI OS"          # header on every screen
edition   = "Naga"
logo      = "naga.ansi"          # truecolor/Unicode glyph art

[palette]
accent    = "#…"  fg = "#…"  bg = "#…"  ...

[defaults]                       # seed values, user-overridable
timezone  = "Asia/Phnom_Penh"    # moved OUT of InstallSpec
hostname  = "koompi"
locale    = "en_US.UTF-8"

[[profiles]]                     # the cards on screen 7
id = "koompi-desktop-hyprland"  label = "KOOMPI Hyprland"  ...
[[profiles]]
id = "koompi-desktop-kde"        label = "KOOMPI KDE"       ...
```

This is the "branded now, rebrandable later" lever: the brand header,
left stepper rail styling, the logo, the palette, the default
locale/timezone/hostname, and the profile cards all come from
`theme.toml`. Swap the file → reskin the whole installer with zero face
changes. The engine never reads it.

### 5. The progress channel — engine → face

Screen 9 needs **phased progress + a live scrollable log + an ETA**.
The scaffold's `runArchinstall()` / `runPostInstallHook()` use
`.Inherit` stdio (the child writes raw bytes straight to the terminal),
which cannot drive that screen. The spec replaces it with a structured
callback the engine emits and the face renders:

```
Progress =
  | Phase  { id: PhaseId, label: string }      # entering a phase
  | Pct    { phase: PhaseId, value: 0..100 }   # within a phase
  | Log    { line: string }                    # one line for the pane
  | Eta    { seconds_remaining: int? }
  | Done   { ok: bool, error: string? }
```

`report_progress(cb)` registers the callback before the destructive
phase; the engine emits `Phase`/`Pct`/`Log`/`Eta` as it runs and a
terminal `Done`. The archinstall backend gets these by capturing
archinstall's stdout (not inheriting it) and parsing phase markers; the
pacstrap backend emits them directly around each shell step. The face
maps `Phase` to the stepper, `Pct`/`Eta` to the bar, and streams `Log`
into the scrollable pane.

### 6. Where the single destructive guard lives

There is **exactly one** human confirmation, it lives **in the face**,
on the **Review screen (8)**, and it gates the call into the engine —
specifically it must complete before `partition_and_format`, the
engine's first irreversible op. The engine is dumb: it executes
whatever an armed spec tells it, with no second prompt.

```
# screen 8 (Review), in the FACE:
if spec.is_complete()             # all required answers present
   and user_held_to_confirm():    # the one destructive gate
       engine.run(spec)           # → partition_and_format → …
```

This corresponds to `main.zig`'s `isComplete()` check plus its standing
TODO — *"gate this behind the actual Review keypress, not just flow"* —
and `config.zig`'s `isComplete()` completeness gate. The fix the spec
mandates: the engine's destructive ops are unreachable except through
the face's Review confirmation. One spec, one guard, one engine call —
no destructive action anywhere else in the system.

---

## Lessons from existing installers

We are not the first to build an installer; we are the first
to build *this* one. Before locking our own screens we mined the
best in three lineages — beautiful server TUIs (Subiquity), Arch's
own engine-facing flow (archinstall 4.0), and the GUI branding
standard (Calamares) — plus the modern terminal-aesthetic
movement (Charm). The lessons below are concrete and tied to the
screens in our flow (§ screen flow above).

### Lessons we adopt

1. **The UI never blocks; anything over ~0.1s goes to the
   background with a spinner.** Subiquity's first principle is "if
   something takes more than about 0.1s, it is done in the
   background," with a spinner held for a *minimum* of 1s to avoid
   flicker.[^subiquity-design] Our **Install** screen (9) execs
   `archinstall --silent` — minutes of work. The Zig draw loop
   must keep redrawing (animated phase spinner, live log tail, ETA)
   while the engine runs in a child process; never freeze the TTY
   waiting on `waitpid`. The same rule applies to **Welcome** (2)
   hardware probing and **Disk** (4) `lsblk` enumeration: probe
   async, show a spinner, never a frozen screen.

2. **One standardized screen scaffold: brand header / excerpt /
   scrollable body / action stack.** Subiquity routes every view
   through a single `screen()` helper so all screens share a
   header (summary on a brand-color band), an excerpt explaining
   the screen, a scrollable content area, and a fixed button
   stack.[^subiquity-design] This is exactly our agreed chrome
   (brand header + stepper rail + keybind footer). Make it *one*
   Zig function that takes (title, excerpt, body-widget,
   footer-binds) — every one of our 10 screens calls it, so
   consistency is structural, not a per-screen discipline.

3. **Be flawless at 80x24, then enhance upward.** Subiquity
   treats 80x24 as the minimum viable terminal and stays fully
   keyboard-usable there.[^subiquity-design] A bare live console
   may give us no more. Design every screen — especially **Disk**
   (4) layout preview and **Review** (8) — to fit 80x24, and treat
   truecolor, wide Naga art, and side-by-side **Desktop** (7)
   preview cards as progressive enhancements that gracefully
   collapse on a small or color-poor TTY.

4. **Prevent invalid input at the keystroke, don't reject it
   after.** Subiquity blocks spaces in Unix usernames *as you
   type* rather than erroring on submit, and explains the valid
   character set inline.[^subiquity-design] Our **Account** screen
   (6) auto-derives username from full name and edits hostname —
   filter illegal chars live (lowercase, no spaces, `[a-z0-9_-]`),
   show the derived value updating in real time, and show password
   strength + confirm-match continuously, not on a failed submit.

5. **Cross-link fields and skip screens that don't apply.**
   Subiquity forms enable/disable fields based on other fields and
   raise `Skip` to omit whole screens dynamically.[^subiquity-design]
   For us: when **Encryption** (5) LUKS is off, don't show a
   passphrase field; if guided "erase & auto btrfs" is chosen on
   **Disk** (4), skip the manual-partition sub-screen entirely. A
   skipped screen should still appear on the stepper rail as
   "auto / skipped," not silently vanish — the user must trust the
   step count.

6. **A menu/landing model where every answer is visible and
   re-editable before commit.** archinstall's flow (now a Textual
   TUI in 4.0) centers on a menu of configurable items you revisit
   in any order before triggering the install.[^archinstall4]
   Our flow is linear, but **Review** (8) should be that menu: each
   collected answer (locale, disk, account, edition, encryption)
   shown as a row that jumps *back to its own screen* on Enter,
   then returns to Review. Back-navigation must preserve every
   prior answer (Subiquity records screen state in
   `/run/subiquity/` for resume[^subiquity-design]) — our `App.cfg`
   already accumulates this; never reset a field on back.

7. **Async, responsive menus even while the backend is busy.**
   archinstall 4.0's headline win from moving to Textual is
   *asynchronous menus that stay responsive even when the app is
   busy in the background*.[^archinstall4][^ostechnix] Confirms our
   #1: the libvaxis event loop and the install subprocess must be
   decoupled so input (scroll the log, expand a phase) stays live
   during the install.

8. **Split the install into show-phases and exec-phases, and
   surface the phases.** Calamares structures its sequence into
   *show* (user-visible) and *exec* (work) sections, and modules
   are either views or jobs.[^calamares-modules] Our **Install**
   screen (9) should render named phases — *Partitioning → LUKS →
   pacstrap → bootloader → post-install hook (snapper, @baseline,
   os-release)* — matching the engine/face split in
   `docs/os-build.md §6`. The user sees *which* phase is running
   and that destructive ones (partition/LUKS) come first, so a
   failure has an obvious locus.

9. **Branding is a config layer dropped on top, never a fork of
   the core.** Calamares's whole reason to exist is that
   distributions customize it "without the need for cumbersome
   patching," via a separate *branding* component (product
   description, logo, slideshow, stylesheet) and external
   modules.[^calamares-branding][^calamares-config] This is our
   locked decision #3 made real: a `theme.zig`/theme-config holds
   colors, logo/Naga ASCII art, product strings, and the slideshow
   shown during **Install** (9); the engine adapter
   (`archinstall.zig`) and screen logic stay distro-neutral.
   Another distro rebrands by dropping in a theme + logo + engine —
   touching zero state-machine code.

10. **Separate the look from the layout — declarative styles, not
    inline escape codes.** Calamares splits QML look from logic so
    "designers produce a unique experience" independently of the
    flow,[^calamares-branding] and Charm's Lip Gloss makes this the
    norm in TUIs: declarative styles with borders, padding,
    adaptive colors, and layout primitives defined separately from
    content.[^lipgloss] Build a small Zig style layer (named
    styles: `header`, `railDone`, `railCurrent`, `danger`,
    `keyhint`) so the theme-config can restyle the whole installer
    without editing any draw call.

11. **Earn "beautiful" with truecolor, Unicode borders, and
    deliberate motion — sparingly.** Charm's aesthetic — smooth
    animation, box-drawing borders, hex/adaptive color, attention
    to detail[^charm][^lipgloss] — is the bar implied by our
    decision #1 (a *beautiful* TUI). Apply it where it carries
    meaning: the phase spinner and progress bar on **Install** (9),
    the selected **Desktop** (7) card border, the stepper rail's
    done/current/upcoming glyphs. Animation is seasoning, not the
    meal — see anti-patterns.

12. **Name the destructive act in plain words, then gate it
    behind a deliberate gesture.** Subiquity categorizes errors and
    blocks progress on destructive/validation failures rather than
    letting them slide.[^subiquity-design] Our **Disk** (4) must
    *name the OS it will erase* and show the resulting
    `@/@home/@var_log/@snapshots` layout, and **Review** (8) is the
    single destructive confirm with hold-to-install. This matches
    the scaffold's note that the wipe must be gated behind the
    Review keypress, not merely the flow reaching it
    (`installer/src/main.zig`). One unmissable confirm, no
    double-nagging dialogs.

13. **Tab/arrow navigation must cycle and wrap predictably.**
    Subiquity found stock urwid containers insufficient and
    reimplemented tab cycling so Tab advances and wraps from the
    last element to the first.[^subiquity-design] In libvaxis we
    own focus management explicitly: Tab/Shift-Tab and arrows move
    focus, wrap at the ends, and the per-screen keybind footer
    states exactly which keys are live — no dead-end focus traps on
    the **Account** (6) multi-field form.

14. **Validate the whole config before the point of no return.**
    Subiquity gates progression on model readiness via
    `asyncio.Event`,[^subiquity-design] and our own audit
    (`docs/os-build.md §6`) shows a malformed config makes
    `--silent` "silently produce a broken system." **Review** (8)
    must run `cfg.isComplete()` *and* schema-validate the generated
    `user_configuration.json` against the pinned archinstall before
    enabling the hold-to-install gesture — better a blocked button
    with a clear reason than a passwordless-root install.

### Anti-patterns to avoid

- **A1 — Animation that fights the console.** Charm demos lean on
  fast repaints and gradients;[^charm] on a bare framebuffer TTY
  over possibly serial/slow links, heavy per-frame redraws flicker
  and lag. Cap animation to low-frequency spinners/progress,
  diff-render (redraw only changed cells), and make all motion
  degrade to a static frame when truecolor or a fast terminal isn't
  detected. Never make comprehension *depend* on motion.

- **A2 — Mouse-dependence or off-screen content with no scroll
  affordance.** Calamares is a pointer-first GUI;[^calamares-modules]
  porting its density naively to a TTY hides content below the fold.
  Subiquity's answer is keyboard-only operation and a `ListBox`
  whose scrollbar appears *only when needed*.[^subiquity-design]
  Every scrollable area (the **Install** log, a long disk list)
  must show a scroll indicator and be fully arrow/PageUp-navigable;
  assume no mouse.

- **A3 — Hand-writing engine config / faking progress.** Do not
  hand-author `user_configuration.json` (schema drifts; `obj_id`
  UUIDs can only be minted by archinstall — `docs/os-build.md §6`),
  and do not show a progress bar that interpolates a guessed
  percentage. Subiquity drives progress from *real* backend state
  transitions (`meta.status.GET`, long-poll
  `refresh.GET(wait=True)`).[^subiquity-design] Our **Install** (9)
  ETA and phase progress must come from parsing archinstall's
  actual output, never a timer pretending to be progress.

[^subiquity-design]: Subiquity DESIGN.md — non-blocking UI, the
`screen()` scaffold, 80x24 minimum, input prevention, form
cross-linking, `Skip`, tab cycling, error categories, state resume.
<https://github.com/canonical/subiquity/blob/main/DESIGN.md>
[^archinstall4]: archinstall 4.0 release notes (Textual UI,
async/responsive menus). <https://github.com/archlinux/archinstall/releases/tag/4.0>
[^ostechnix]: "Archinstall 4.0 is Released with New Textual UI and
Faster Menus," OSTechNix. <https://ostechnix.com/archinstall-4-0-textual-tui-release/>
[^calamares-modules]: Calamares modules README — show/exec split,
views vs jobs. <https://github.com/calamares/calamares/blob/calamares/src/modules/README.md>
[^calamares-branding]: Calamares branding README — branding
component, QML vs QWidgets, stylesheets.
<https://github.com/calamares/calamares/blob/calamares/src/branding/README.md>
[^calamares-config]: Calamares Deploy Configuration — customizing
without patching. <https://calamares.euroquis.nl/docs/deploy-configuration>
[^lipgloss]: charmbracelet/lipgloss — declarative styles, borders,
adaptive color, layout. <https://github.com/charmbracelet/lipgloss>
[^charm]: Charm — "we make the command line glamorous"; animation
and styling aesthetic. <https://github.com/charmbracelet>

---

## The theme file, reconciled

§2 and §3·4 each describe a *part* of `theme.toml` at different fidelity. The
single source of truth is the shipped, parse-verified
[`installer/themes/koompi.toml`](../themes/koompi.toml), which merges them:

| Concern | Described in | Owner in `koompi.toml` |
|---|---|---|
| Brand identity (header text) | §3·4 | `[brand]` (`name`, `edition`) |
| Internal theme label | §2 | `[meta].name` |
| Logo art + glyph fallback | §2 | `[logo]` |
| Nerd-Font availability flag | §2 | `[font]` |
| Seed defaults (overridable) | §3·4 | `[defaults]` |
| 12 color tokens | §2 | `[colors]` |
| Box / stepper / select / icon / motion glyphs | §2 | `[glyphs]` |
| Desktop "edition" cards | §3·4 | `[[profiles]]` |

Two reconciliations worth stating explicitly:

- **`[meta].name` ≠ `[brand].name`.** §2's `meta.name` is an internal label
  shown nowhere; §3·4's `brand.name` is the product string drawn on every
  header. They are different fields and keep different keys — never conflate
  them.
- **`[palette]` is superseded by `[colors]`.** §3·4 sketches a 3-value
  `[palette]` (`accent`/`fg`/`bg`); that was a placeholder. The real palette is
  §2's 12-token `[colors]`, and `koompi.toml` ships only that.

`brand_ansi` in `[meta]` must encode the same color as `colors.brand`
(`#1793D1` → `38;2;23;147;209`) so the installer, `/etc/os-release`, and
`post_install.sh` all speak the same brand blue.

## Roadmap

The spec is ahead of the code by design — the binary is deferred on Zig 0.16's
churning `Io` API (see `installer/build.zig.zon`). When the build resumes, this
is the order the spec implies:

1. **Reorder the `Step` enum** in `installer/src/main.zig` to the authoritative
   §1 flow: `Language → Welcome → Keyboard → Disk → Encryption → Account →
   Desktop → Review → Install → Done`. Today it folds locale/keymap/timezone
   into one step and orders `disk → identity → edition → encrypt`; the README's
   data-flow list is stale the same way. (Documented here, not yet changed — the
   binary doesn't compile under 0.16 regardless.)
2. **Neutralize `config.zig`** into the §3·1 `InstallSpec`: add `disk_mode` and
   `full_name`, make `password` a `Secret`, rename `Edition` → `ProfileId`, and
   move the KOOMPI default timezone/hostname/locale out of the struct into
   `[defaults]` of `theme.toml`.
3. **Load `theme.toml` at boot**, before the first draw; fail closed on a
   missing token. Route every color/glyph/string/default through it.
4. **One reusable `screen()` scaffold** (header + stepper rail + body + footer),
   per §4 lesson 2 — every screen calls it, so chrome consistency is structural,
   not a per-screen discipline.
5. **Build the `Engine` interface** (§3·2) with the archinstall backend folding
   five ops into one `--silent` exec; keep `probe_disks`/`plan_layout` pure so
   the Disk screen can list disks before any write.
6. **Replace `.Inherit` stdio** with the §3·5 `Progress` callback so the Install
   screen gets real phased progress + a live log + an ETA, parsed from
   archinstall's captured output — never a faked timer (§4 anti-pattern A3).
7. **Gate the one destructive call** behind the Review screen's hold-to-confirm
   (§1 screen 8, §3·6), and schema-validate the generated
   `user_configuration.json` against the pinned archinstall before arming it.

## Cross-references

- `installer/README.md` — the face / engine / finish split and the
  schema-pinning risk.
- `installer/src/archinstall.zig` — the archinstall backend (JSON emit · exec ·
  chroot hook).
- `installer/src/post_install.sh` — the post-install finish (snapper
  `@baseline`, snap-pac, grub-btrfs, os-release).
- `docs/os-build.md` §6 — the OS-build architecture and the archinstall
  schema-drift blocker table.
- `installer/themes/koompi.toml` — the shipped, parse-verified KOOMPI theme.

*Sections §1–§4 were produced by a multi-track design pass; §4 draws on the
public design docs of Subiquity, archinstall, Calamares, and Charm (cited
inline) as attributions, not independently re-verified claims.*
