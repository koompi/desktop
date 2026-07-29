# `sdata/` - setup data

Everything `./setup` reads.

```
lib/            shared bash: logging, run/confirm, manifest, distro detection
install/        the four install steps, plus uninstall
uv/             the Python requirements the shell's helper scripts import
dist-arch/      Arch recipes + the koompi-* PKGBUILDs + the ISO/repo scaffolds
dist-fedora/    Fedora recipes
dist-debian/    Debian and Ubuntu recipes
deps-info.md    per-package notes on why each Arch dependency is there
```

Each distro directory holds two recipes, and the split matters:

- `install-deps.sh` - what the session cannot start without.
  Break it and the desktop does not come up.
- `install-apps.sh` - the programs KOOMPI has an opinion about, the set
  `variables.lua` is written around.
  Skip it and you keep whatever you already had.

`lib/arch.sh` exists only because both Arch recipes need `arch_install_yay` and
`arch_install_pkgbuild`, and neither can source the other: a recipe does its
work at the top level, so sourcing one to borrow a function would run it.

## Adding a distro

1. Create `dist-<group>/install-deps.sh` and `dist-<group>/install-apps.sh`.
   They are **sourced** by `sdata/install/deps.sh` and `sdata/install/apps.sh`,
   not executed, so they can use `run`, `step`, `info`, `warn`, `err`, `die`,
   `have` and `confirm` from `lib/common.sh`, and can read `REPO_ROOT` and the
   `OS_*` variables.
2. Add the distro's `ID` (or `ID_LIKE`) to the `case` in `lib/distro.sh`.
3. Add a row to the matrix in `.github/workflows/installer.yml` so the mapping
   stays covered.

`install-apps.sh` has to work under `--only-apps`, which means the dependency
recipe never ran. Anything it needs from that file it must set up itself; see
the top of `dist-debian/install-apps.sh`.

A recipe must be safe to run twice, and must leave the machine usable if it
gives up half way. `run` already offers retry/skip/abort on a failed command,
so prefer letting a command fail loudly over swallowing its error.

`dist-arch/` also holds the OS-image side of the repo (PKGBUILDs, the archiso
profile, the signed-repo scaffold). That is a separate product from `./setup`;
see [`../docs/os-build.md`](../docs/os-build.md).
