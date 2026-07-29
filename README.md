# KOOMPI Desktop

The KOOMPI desktop: Hyprland plus a Quickshell shell.
Based on [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) (illogical-impulse).

Install it on Arch, Fedora, Debian or Ubuntu:

```sh
curl -fsSL https://raw.githubusercontent.com/rithythul/koompi-desktop/main/install.sh | bash
```

That clones the repository to `~/.local/share/koompi-desktop` and hands over to `./setup install`.
It asks before each stage, and refuses to run as root.
Prefer to read it first? Clone and run the same thing by hand:

```sh
git clone --recursive https://github.com/rithythul/koompi-desktop.git
cd koompi-desktop
./setup install
```

Then log out and pick **KOOMPI** at your display manager. It is installed as
an additional Hyprland-based session; existing KDE Plasma and GNOME sessions
stay installed and selectable.

## What `./setup` does

Four steps, each skippable:

1. **Dependencies** - installs the packages the session cannot start without,
   using the recipe for your distro (`sdata/dist-arch`, `sdata/dist-fedora`,
   `sdata/dist-debian`).
2. **Applications** - the opinionated set the shipped config is written around:
   WezTerm, Konsole, Zed, Chrome, Brave, Dolphin's viewers and thumbnailers,
   LibreOffice, btop, KDE Connect, Neovim, a modern CLI toolkit, and the
   KOOMPI Workbench with Claude Code, Codex, Pi and Herdr. Asked for
   separately; `--no-apps` skips it.
   See [Applications](#applications).
3. **Setups** - creates the Python virtualenv the colour pipeline runs in,
   builds the global-menu daemon, adds you to `video`/`input`/`i2c`, loads the
   `uinput` and `i2c-dev` modules, enables `ydotool`, and registers the KOOMPI
   session system-wide so GDM and SDDM can show it before login.
4. **Files** - copies `dots/` into `$HOME`, backing up anything it overwrites to
   `~/.koompi-dots-backup/<timestamp>/`.

Every file it writes is recorded in `~/.local/state/koompi/installed-files`, so
`./setup uninstall` removes exactly that set and leaves your own files alone.

```sh
./setup install --dry-run     # show what would happen, change nothing
./setup install --no-deps     # you manage packages yourself
./setup install --no-apps     # keep the applications you already have
./setup install --only-apps   # add the application set to an existing install
./setup install --only-files  # just refresh the config after a git pull
./setup update                # already running KOOMPI? pull and re-apply
./setup doctor                # what is detected, what is missing
./setup uninstall             # undo an install
```

The one-liner passes its arguments straight through, so this works too:

```sh
curl -fsSL https://raw.githubusercontent.com/rithythul/koompi-desktop/main/install.sh | bash -s -- --no-apps
```

## Updating

On a machine that already runs KOOMPI, one command, from anywhere:

```sh
koompi-update
```

It works out how this machine got its desktop.
On KOOMPI OS, where the desktop comes from packages, that is a `pacman -Syu`.
On an install from a checkout it is a `git pull` followed by `./setup update`,
which re-applies the config, leaves your `~/.config/hypr/custom/` overrides
alone, and reloads the running session so you do not have to log out.
See [Updating](docs/install.md#updating).

## Applications

Each role is dispatched through `launch_first_available.sh`, which runs the
first program on `PATH` from a preference list in
`dots/.config/hypr/hyprland/variables.lua`.
The application step installs what makes those lists resolve the way KOOMPI
intends:

| Role | KOOMPI's choice |
|---|---|
| Terminal | WezTerm, with Konsole for the KDE apps that ask KIO for one |
| File manager | Dolphin, plus `ark`, `kio-admin` and the KDE thumbnailers |
| Browser | Google Chrome, then Brave |
| Editor | Zed |
| Documents | Okular for PDFs, Loupe for images, mpv for video |
| Office | LibreOffice |
| System | btop, GNOME System Monitor, `nm-connection-editor` |
| Phone | KDE Connect |
| Agent workbench | Herdr orchestrating Claude Code, Codex and Pi; Neovim available directly |
| CLI toolkit | Git/GitHub CLI, ripgrep, fd, fzf, jq, bat, eza, zoxide, direnv, ShellCheck, shfmt and just |

Press `Super+Shift+Return` (or launch **KOOMPI Workbench**) to open Herdr in
the preferred terminal. The agent installers are user-local and authentication
is deliberately left to each user; KOOMPI does not copy or manage credentials.

None of it is load-bearing.
Install something else and it wins as soon as it is earlier in the list, or set your own order in `~/.config/hypr/custom/variables.lua`.

Kitty is a *dependency* rather than an application here.
The terminal scratchpad, the system-monitor scratchpad and the shell's own terminal actions name it directly instead of dispatching, and the colour pipeline generates a theme for it.
WezTerm is what the terminal keybind opens.

On Arch this set is the `koompi-apps` metapackage, so KOOMPI OS images get the same programs through `koompi-desktop-experience`.
Chrome and Brave come from the AUR there, and from Google's and Brave's own signed repositories on Fedora, Debian and Ubuntu.
Zed is packaged only on Arch; elsewhere the installer runs Zed's own script, which installs into `~/.local`.

Your personal overrides live in `~/.config/hypr/custom/*.lua`.
Those files are written once and never overwritten again, so an update cannot lose them.

## Distro support

| Distro | Status |
|---|---|
| Arch and derivatives | Primary. This is what KOOMPI OS itself is built on. |
| Fedora | Supported. Needs a COPR for Hyprland and Quickshell. |
| Debian / Ubuntu | Supported. Some components are built from source. |

Anything else can still run `./setup install --no-deps` and install the
packages in [`docs/dependencies.md`](docs/dependencies.md) by hand.

## KOOMPI OS

KOOMPI OS itself does not use `./setup`.
The desktop is packaged into `/etc/skel` (`sdata/dist-arch/koompi-hyprland-config/`) so a freshly installed user inherits it on first login.
For the OS build chain - signed `[koompi]` repo, archiso profile, installer - see [`docs/os-build.md`](docs/os-build.md).

## Documentation

- [`docs/install.md`](docs/install.md) - installing, updating, per-distro notes
- [`docs/dependencies.md`](docs/dependencies.md) - what the desktop needs and why
- [`docs/os-build.md`](docs/os-build.md) - the KOOMPI OS build architecture
