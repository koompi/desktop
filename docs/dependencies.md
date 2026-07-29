# KOOMPI Desktop Experience - dependencies

What the desktop needs to run, what is optional, and which packages provide it.

The canonical list is the Arch one below, because Arch is where the desktop is developed and where KOOMPI OS ships from.
The Fedora and Debian recipes (`sdata/dist-fedora/`, `sdata/dist-debian/`) translate it; when they disagree with this document, they are the bug.

`./setup install` resolves all of this for you.
Read on only if you are on an unsupported distro, or want to know why something is here.

## Not packages

Two requirements are not satisfied by any package manager, and `./setup` handles both in its setups step:

- **A Python virtualenv** at `~/.local/state/quickshell/.venv`, built by `uv` from `sdata/uv/requirements.txt`.
  The colour generation, thumbnailing and image-analysis helpers in `dots/.config/quickshell/koompi/scripts/` run out of it, addressed through `$ILLOGICAL_IMPULSE_VIRTUAL_ENV`.
  It is created with `--system-site-packages` so PyGObject and OpenCV come from distro packages rather than being compiled.
  Without it, wallpaper colour extraction and thumbnails silently do nothing.
- **The global-menu daemon**, Zig source at `dots/.config/quickshell/koompi/scripts/global-menu/`.
  `zig-out/` is gitignored, so a fresh clone has no binary and the global menu stays empty until `zig build` runs.
  This makes `zig` a build-time dependency of the desktop, not just of the repo.
  The daemon links GLib/GDBus, so `glib2` and `pkgconf` (Debian: `libglib2.0-dev`, `pkg-config`; Fedora: `glib2-devel`, `pkgconf-pkg-config`) must be present at build time.
  It also owns `com.canonical.AppMenu.Registrar` on the session bus, which is how applications are told a global menu exists at all.
  Nothing else in the session may own that name.

## Required

The Arch package layer lives in `sdata/dist-arch/`.
Installing `koompi-desktop-experience` pulls everything in this section; `./setup install` installs only the dependency metas from it, because `./setup` supplies the shell and config itself (see [`install.md`](install.md)).

The core session, in dependency order:

| Package | Provides |
|---|---|
| `koompi-hyprland` | Hyprland compositor, hyprsunset, wl-clipboard |
| `koompi-quickshell-git` | the `qs` shell runtime (Qt6), kdialog |
| `koompi-shell` | the shell tree in `/etc/xdg/quickshell/koompi`, the `koompi-*` tools in `/usr/bin` |
| `koompi-session` | `koompi-session` launcher, SDDM session entry, portal config |
| `koompi-hyprland-config` | the full dotfiles seed in `/etc/skel` for new users |
| `koompi-base` | everything below |

`koompi-base` fans out to the domain metas:

| Meta | Pulls in | Why |
|---|---|---|
| `koompi-basic` | coreutils, curl, wget, jq, rsync, ripgrep, cliphist, bc, go-yq, xdg-user-dirs, fprintd, cmake | shell scripts and clipboard history |
| `koompi-audio` | pipewire-pulse, wireplumber, playerctl, pavucontrol-qt, cava | sound and media controls |
| `koompi-backlight` | brightnessctl, ddcutil, geoclue | brightness and night light |
| `koompi-fonts-themes` | matugen, adw-gtk-theme, breeze-plus, darkly, kitty, fish, starship, the KOOMPI font set | theming pipeline and default terminal |
| `koompi-kde` | dolphin, kdialog, gnome-keyring, networkmanager | file manager, dialogs, Secret Service, networking |
| `koompi-portal` | xdg-desktop-portal + gtk + hyprland backends | file chooser and screenshare |
| `koompi-screencapture` | hyprshot, slurp, swappy, wf-recorder, tesseract | screenshots, recording, OCR |
| `koompi-toolkit` | upower, ydotool, wtype | power reporting and input synthesis |
| `koompi-widgets` | fuzzel, hypridle, hyprlock, hyprpicker, wlogout, translate-shell, libqalculate | launcher, lock, idle, widget helpers |

## Optional

Feature packages the desktop uses when present and degrades without:

- `matugen` is technically in the required set via `koompi-fonts-themes`, but the desktop survives its absence: `koompi-theme` degrades to a warning and keeps the current colors.
- `koompi-microtex-git` renders LaTeX in the shell; without it math rendering is off.
- `easyeffects` audio effects, `wayvnc` remote desktop, `fprintd` fingerprint login.
- `plasma-browser-integration` media control from the browser.

## Opinionated application and agent layer

The application step is not required to start Hyprland, but it is part of the
intended KOOMPI experience. Alongside the graphical defaults it installs
Neovim and a terminal toolkit (`git`, `gh`, `ripgrep`, `fd`, `fzf`, `jq`,
`bat`, `eza`, `zoxide`, `direnv`, `shellcheck`, `shfmt`, `just`).

Claude Code, Codex, Pi and Herdr are installed from their upstream user-level
channels because supported distro repositories do not provide a consistent,
current set. Codex and Pi use an isolated npm prefix at
`~/.local/share/koompi/npm`; Claude Code and Herdr use their native installers.
No agent credentials are managed by KOOMPI.

Run `./setup install --only-apps` to install or repair this layer, and
`./setup doctor` to see which commands are available.

## GTK/Qt compatibility (outputs, not infrastructure)

The desktop is KDE-free and GNOME-free as infrastructure; these packages exist so apps look and behave right:

- GTK apps: gtk3/gtk4, libadwaita, adw-gtk-theme (theme applied via gsettings/dconf), xdg-desktop-portal-gtk (file chooser), appmenu-gtk-module (global menu).
- Qt apps: qt6ct (`QT_QPA_PLATFORMTHEME=qt6ct`), the Darkly style, breeze-plus icons; matugen renders the palette, `switchwall.sh` writes `qt6ct.conf` and `kdeglobals`.
- Secret Service: `gnome-keyring` stays the provider; it is PAM-integrated with the lock screen and holds existing secrets, and quickshell links qtkeychain against it.

GTK and Qt settings files are generated compatibility outputs.
`~/.config/koompi/config.json` is the only user-owned source of truth.

## Non-Arch distros

The full package name mapping lives next to each recipe: [`../sdata/dist-fedora/packages.list`](../sdata/dist-fedora/packages.list) and [`../sdata/dist-debian/packages.list`](../sdata/dist-debian/packages.list).
What follows is only what does **not** translate cleanly.

### Where each distro gets the hard parts

| | Fedora 43+ | Debian 13 | Debian 14 / sid | Ubuntu 26.04+ |
|---|---|---|---|---|
| Hyprland stack | COPR `sdegler/hyprland` | `trixie-backports` | main | universe |
| quickshell | Fedora `updates` (0.2.1), or COPR `errornointernet/quickshell` (0.3.x) | `trixie-backports` | main | `ppa:avengemedia/danklinux` |
| matugen | Fedora | **built/fetched** | **built/fetched** | the same PPA |
| uv | Fedora | **astral.sh** | **astral.sh** | **astral.sh** |
| go-yq | Fedora's `yq` is the right tool | `yq-go` in backports | `yq-go` | **static binary** |
| hyprsunset | COPR `sdegler/hyprland` | backports | main | **source build** |
| the KOOMPI fonts | COPR `ririko66z/dots-hyprland` | **fetched** | **fetched** | **fetched** |
| adw-gtk3, bibata, hyprshot | COPRs | **fetched** | **fetched** | **fetched** |
| darkly, breeze-plus, songrec, microtex | COPRs | not installed | not installed | not installed |

Bold entries are handled by [`../sdata/lib/from-source.sh`](../sdata/lib/from-source.sh) rather than a package manager.

### Traps worth knowing

- **`yq` on Debian and Ubuntu is the wrong tool.** That package is a Python wrapper around jq with incompatible syntax; the shell scripts need mikefarah's Go implementation and its `-o=j`. The right package is `yq-go`, which does not exist on Ubuntu at all. Fedora's `yq` *is* mikefarah's.
- **The fonts are not optional.** Nothing on Debian or Ubuntu packages Material Symbols, and without it every icon in the bar renders as a tofu box. Treat the font fetch as a required step, not a nicety.
- **quickshell links private Qt APIs** and crashes on a Qt ABI bump. Both non-Arch recipes pin it (`dnf versionlock` / `apt-mark hold`). Unpin before a Qt upgrade, then re-run `./setup install --only-deps`.
- **`uv` is not apt-installable on any Debian or Ubuntu release.** Without it the Python venv never gets built and the colour pipeline is dead, so the recipe installs it from `astral.sh`.
- **Ubuntu 24.04 and 25.10 are refused, not degraded.** 24.04 has no Hyprland and Qt 6.4.2 against quickshell's 6.6 floor; 25.10 ships Hyprland 0.41 and is EOL.

### Degrades gracefully off Arch

These are missing on Debian and Ubuntu and the desktop keeps working without them:

| Missing | What stops working |
|---|---|
| `darkly` | Qt apps fall back to Fusion. `switchwall.sh` still applies the palette through `qt6ct.conf`. |
| `breeze-plus` | Some icons fall back to plain Breeze, which is installed. |
| `songrec` | The music-recognition widget does nothing. |
| `microtex` | LaTeX rendering in the shell is off. |
| `matugen`, if the fetch fails | `koompi-theme` warns and keeps the current colours. |
| `hyprsunset`, if the build is declined | No night light / blue-light filter. |

## Watch items

- No polkit authentication agent is installed since the M5 plasma removal; `koompi-useradd` (pkexec) needs one for graphical auth prompts. If privileged GUI actions fail, add a lean agent (for example `hyprpolkitagent`) rather than resurrecting polkit-kde-agent.
  The Fedora and Debian recipes already install `hyprpolkitagent`, so this gap is Arch-only now.
- `kdialog` is a hard dependency of `koompi-quickshell-git` upstream; dropping it fully is a packaging change there, not here.
