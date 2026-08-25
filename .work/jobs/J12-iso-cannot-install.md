# J12 — the published ISO cannot install the KOOMPI desktop (blocked-on-user)

State: `blocked-on-user`. Do not start.

As far as the tree shows: release `iso-koompi-2026.08.25-x86_64` (built by
`.github/workflows/build-iso.yml`) is 100% stock Arch (`packages.x86_64` header, `pacman.conf:18-28` with
`[koompi]` commented out), while `installer/src/archinstall.zig:28-32` selects `koompi-desktop-hyprland` /
`koompi-desktop-kde`, packages that exist only in the unpublished `[koompi]` repo. So the installer's
pacstrap has nowhere to get the desktop from. Unverified on a real boot; step 1 of any job is booting the ISO
in a VM and running the installer to the end.

Options:
- A. Bake a local `[koompi]` repo into the ISO: CI builds every `sdata/dist-arch/koompi-*` package, `repo-add`,
  `Server = file:///run/archiso/...`, `SigLevel = Optional` for that repo only. No hosting, no key, works
  offline. Installed systems then need J11's git fallback for updates until B exists.
- B. Host and sign `[koompi]` at `repo.koompi.org` per `sdata/dist-arch/repo/README.md`. Needs a GPG key and a
  server; gives real `pacman -Syu` updates.

Recommendation: A now, B when hosting exists. Decision needed from Rithy: which, and whether the
`koompi-desktop-*` meta packages are the install unit or `./setup install` from a baked checkout is.
