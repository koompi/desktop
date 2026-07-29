# Debian and Ubuntu recipe

One recipe for both; Ubuntu and its derivatives arrive here through `ID_LIKE=debian`.

```
install-deps.sh         the recipe, sourced by sdata/install/deps.sh
packages.list           common to both
packages-debian.list    Debian-only names
packages-ubuntu.list    Ubuntu-only names
```

## Supported releases

| Release | Status |
|---|---|
| Debian 13 (trixie) | Supported. **Requires `trixie-backports`**, which the recipe enables. |
| Debian 14 (forky) / sid | Supported. Everything is in main. |
| Ubuntu 26.04 (resolute) | Supported. Needs universe, multiverse and one PPA. |
| Ubuntu 25.10 (questing) | **Refused.** Hyprland 0.41, below what this config needs, and EOL since July 2026. |
| Ubuntu 24.04 (noble) | **Refused.** No Hyprland at all, Qt 6.4.2 against quickshell's 6.6 floor, libwayland 1.22.0 against Hyprland's 1.22.90. Installing here means rebuilding the Wayland stack. |
| Derivatives (Mint, Pop!\_OS, ...) | Judged on package versions, not on the release number. |

Debian 13 keeping the whole stack in backports rather than main is the single most surprising fact here.
`trixie` has **zero** `hypr*` packages; `trixie-backports` has hyprland 0.55, hyprlock, hypridle, hyprsunset, hyprpicker, xdg-desktop-portal-hyprland, hyprpolkitagent, quickshell 0.3.0 and yq-go.

## How releases are actually gated

`VERSION_ID` is only trustworthy on Debian and Ubuntu themselves.
A derivative numbers its own releases - Linux Mint 22 is Ubuntu 24.04 - so refusing on the number gives derivatives the wrong answer in both directions.

So the version check only handles exact `ID=debian` and `ID=ubuntu`, and the real gate for everyone is `debian_require_hyprland()`: after the repositories are enabled, it reads `apt-cache policy hyprland` and refuses anything below 0.45.
Every way of being too old - wrong release, missing backports, a fork that predates the stack - ends at that one check.

## Repositories enabled

Debian 13:

```
deb http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware
```

Ubuntu:

```sh
sudo add-apt-repository universe     # the compositor and most of the desktop
sudo add-apt-repository multiverse   # translate-shell
sudo add-apt-repository ppa:avengemedia/danklinux   # quickshell, matugen, libcpptrace
```

`translate-shell` is in **contrib** on Debian and **multiverse** on Ubuntu, neither enabled by default.

## The `yq` trap

`apt install yq` gives you a **Python wrapper around jq** with different syntax.
The shell scripts want mikefarah's Go implementation and its `-o=j` flag.
The correct package name is `yq-go`, which exists in Debian forky/sid and trixie-backports and **does not exist on Ubuntu at all**.
`install_go_yq()` fetches the static binary where the package is missing, and checks `yq --version` rather than just `command -v yq` so it does not mistake the wrong tool for the right one.

## Not from a package

| Item | Where it comes from | Why |
|---|---|---|
| the KOOMPI font set | upstream releases, `sdata/lib/from-source.sh` | none of the six are packaged. **Mandatory** - without Material Symbols every icon in the bar is a tofu box |
| `uv` | `astral.sh/uv/install.sh` | not apt-installable on any Debian or Ubuntu release |
| `matugen` | upstream release binary (Debian); PPA (Ubuntu) | no Debian package on any suite |
| `adw-gtk3` | upstream release tarball | not packaged; GTK apps stay unthemed without it |
| `bibata-cursor-theme` | upstream release tarball | not packaged |
| `hyprshot` | a single upstream bash script | not packaged |
| `hyprsunset` | source build, Ubuntu only | in Debian backports; in no Ubuntu archive or PPA. Its build deps are all in resolute universe, so this is minutes, not a Wayland rebuild |

## Deliberately not installed

`darkly`, `breeze-plus`, `songrec` and `microtex` are all buildable and none is on the critical path, but each pulls a KDE or Rust toolchain.
The recipe names them and what breaks without them rather than building them behind the user's back.

## The quickshell hold

Same reason as Fedora: quickshell links private Qt APIs and breaks on an ABI bump.
The recipe runs `apt-mark hold quickshell`.
Before a Qt upgrade, `sudo apt-mark unhold quickshell`, upgrade, then `./setup install --only-deps` to re-hold.

## Missing package names

`apt-get install` fails the whole transaction on one unknown name, which on a derivative is close to guaranteed.
`debian_install()` asks `apt-cache` what exists first, installs that, and reports the rest.
