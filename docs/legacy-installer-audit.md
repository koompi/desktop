# Legacy installer layer — security & correctness audit

> **Date:** 2026-06-06 · **Method:** 4-lens adversarial sweep (security / correctness /
> robustness / supply-chain), each finding independently verified by a second pass.
> 45 raw findings → see the breakdown below. This file is the durable record; a
> follow-up decision (retire / harden / mark-unsupported) is **pending**.

## What was audited

The **inherited dots-hyprland installer layer** — *not* the live KOOMPI OS build
scaffold (`sdata/dist-arch/` + `installer/`, audited separately). Scope:

```
setup, bootstrap.sh
sdata/lib/{dist-determine,environment-variables,functions,package-installers}.sh
sdata/subcmd-install/*  sdata/subcmd-{checkdeps,exp-merge,exp-update,resetfirstrun,uninstall,virtmon}/*
sdata/dist-fedora/*  sdata/dist-gentoo/*  sdata/dist-nix/*  sdata/uv/*
```

## Liveness verdict: ORPHANED (with one live edge)

The layer originates from the `end-4/dots-hyprland` fork and is **not wired into the
live KOOMPI OS build**. The live OS path is entirely separate:

```
signed [koompi] repo (sdata/dist-arch/repo/) → archiso profile (sdata/dist-arch/iso/koompi/)
  → mkarchiso → live ISO → Zig/libvaxis TUI (installer/) → archinstall → post_install.sh chroot hook
```

Zero references run from that path into `setup` / `bootstrap.sh` / `sdata/lib`.

**The one live edge:** `bootstrap.sh` is the README's public one-liner
(`bash <(curl … bootstrap.sh)`), and it still runs `./setup install`. So a handful
of files are **reachable if a user runs the dotfiles one-liner on an existing
system** — that path is live-but-untested-since-the-fork. This is the crux of the
pending decision: *do we still support installing KOOMPI dotfiles onto an existing
machine?* If no, everything below is moot.

## Findings that matter if the layer is kept

### A. Reachable shell-quoting defects (real, trivial to fix)

| File:line | Issue |
|---|---|
| `sdata/subcmd-install/3.files.sh:97,106,125,134,143,154,168` | `[ -f $t ]` / `[ -d $t ]` — unquoted test operands |
| `sdata/subcmd-install/3.files.sh:110` | `mv $t $t.old` — unquoted src/dest |
| `sdata/subcmd-uninstall/0.run.sh:31` | `command -v $ed` and `x $ed "$listfile"` — unquoted `$ed` |
| `sdata/subcmd-install/3.files-legacy.sh:72` | unquoted var inside a `bash -c "…"` redirect (drop the nested shell; use direct `>>`) |

These manifest only if a path contains spaces/globs (rare for XDG paths), hence low
severity — but they're genuine and on the live one-liner path.

### B. Latent supply-chain holes (critical-looking, "safe" only because orphaned)

Every one of these was downgraded to **note-only by the verifier specifically because
the code is dead** — they become **real** the moment the dotfiles path is used:

| File:line | Issue |
|---|---|
| `sdata/lib/package-installers.sh:66` | `bash <(curl -LJs https://astral.sh/uv/install.sh)` — unpinned remote code exec, no checksum |
| `sdata/lib/package-installers.sh:12,26,53` | font repos (`rubik`, `gabarito`, `MicroTeX`) `git pull` of `main`/`master`, unpinned |
| `sdata/lib/package-installers.sh:42-43` | Bibata cursor from `releases/latest`, extracted with no checksum |
| `sdata/lib/package-installers.sh:69-80` | `uv pip install` without `--require-hashes` (versions pinned, hashes absent) |
| `sdata/dist-nix/install-deps.sh:19-20` | NixOS **experimental** installer downloaded + `sh`-executed, no checksum |
| `sdata/dist-fedora/install-deps.sh:34-37,88` | RPMs pulled from GH release assets, then installed with `--nogpgcheck` |
| `sdata/subcmd-install/3.files.sh:183-184` | `end-4/google-sans-flex` font `git pull main`, unpinned |

Note: the **live** OS build already does these correctly (e.g.
`sdata/dist-arch/koompi-bibata-modern-classic-bin/PKGBUILD` pins v2.0.6 + sha256;
fonts come from versioned Arch packages). The flaws are confined to the legacy copy.

### C. Correctness nits (note-only)

- `sdata/subcmd-install/options.sh:48-52` and `sdata/subcmd-exp-update/options.sh:39-43`
  — `para=$(getopt …)` under `set -e`: a getopt failure exits before the friendly
  `[ $? != 0 ]` message can print (user still gets a non-zero exit, just no hint).
- `setup:2` — `cd "$(dirname "$0")"` before `set -e`, unchecked.

## Two auditor findings corrected (do **not** act on these)

- **`sdata/lib/functions.sh:11` "missing `set -euo pipefail`" → false positive.** The
  file's own header (line 1) states it is *sourced, not executed*; a library must not
  impose shell options on its callers. Correctly omitted.
- **`bootstrap.sh:35` "unpinned `git clone`" → not a defect.** `bootstrap.sh` is a
  *rolling* one-liner installer (the script itself is curl'd from `main` HEAD; there is
  no release tag to pin to). Pinning the clone but not the fetch would be incoherent and
  would defeat the "install latest" purpose. The verifier pattern-matched
  "unpinned clone = bad" without the rolling-installer context.

Also dismissed as false positives by the sweep: `package-installers.sh:72` eval (locally
shadowed var), `2.setups.sh:119` (unquoted inside `[[ ]]`, where splitting is suppressed),
`dist-gentoo/install-deps.sh` globs (intentional), `dist-fedora` `$package_list`
word-splitting (intentional — `dnf` needs separate args), `bootstrap.sh:38` cd
(guarded by `set -e`).

## Pending decision

1. **Retire** — delete the legacy layer, drop the one-liner from the README.
   Cleanest given the OS-ISO trajectory; **drops** the "install KOOMPI dotfiles onto an
   existing system" and multi-distro (fedora/gentoo/nix) use cases.
2. **Keep + harden** — quote §A, pin/checksum the §B downloads, drop `--nogpgcheck`.
3. **Keep but mark unsupported** — add an "inherited, unmaintained" notice; no code changes.
