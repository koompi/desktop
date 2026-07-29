# Fedora recipe

Fedora 43 and later, x86_64 and aarch64.

Fedora is the easiest non-Arch target: **nothing is built from source.**
Fedora proper carries `quickshell` and `matugen`, and four COPRs cover the rest.

```
install-deps.sh   the recipe, sourced by sdata/install/deps.sh
packages.list     one package per line, with the COPR noted where it is not in Fedora
```

## COPRs

| COPR | Carries |
|---|---|
| `sdegler/hyprland` | hyprland, hyprlock, hypridle, hyprsunset, hyprpicker, hyprshot, xdg-desktop-portal-hyprland, hyprpolkitagent |
| `ririko66z/dots-hyprland` | the KOOMPI font set, bibata-cursor-theme, breeze-plus, microtex, songrec |
| `deltacopy/darkly` | darkly, the Qt style |
| `atim/starship` | starship |

`solopasha/hyprland` is the better-known Hyprland COPR and is **not** used: it lags well behind `sdegler` (0.49 against 0.56 as of July 2026).
Switching back is a one-line change here if that ever inverts.

## Two things that differ from upstream

**No prebuilt-RPM repo.**
`end-4`'s Fedora installer downloads `quickshell` and `matugen` RPMs from a GitHub release into a local repo and installs them with `--nogpgcheck`.
Both are in Fedora now, so that step only bought an unsigned third-party repo.
It is gone.

**No `alternateved/eza` COPR.** `eza` is in Fedora updates.

## The quickshell pin

`quickshell` links private Qt APIs and crashes on a Qt ABI bump, so the recipe holds it with `dnf versionlock`.
Before a Qt major upgrade:

```sh
sudo dnf versionlock delete quickshell
sudo dnf upgrade
./setup install --only-deps      # re-pins
```

Want 0.3.x instead of Fedora's 0.2.1:

```sh
sudo dnf copr enable errornointernet/quickshell -y
./setup install --only-deps
```

## Failure handling

The package install runs with `--skip-unavailable`.
A COPR that has not yet rebuilt for a new Fedora release should cost one widget, not the whole install.
`./setup doctor` reports what actually landed.
