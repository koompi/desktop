# The signed `[koompi]` pacman repository

This directory builds the **signed `[koompi]` pacman repo** — the foundation of
the KOOMPI OS ISO chain. Everything downstream depends on it:

```
signed [koompi] repo   (this dir: build-repo.sh + GPG)
        │
        ▼
archiso profile        (sdata/dist-arch/iso/koompi/: profiledef.sh,
   pacman.conf injects   packages.x86_64, pacman.conf, airootfs)
   [koompi]
        │
        ▼
mkarchiso  ──►  the live ISO  ──►  the KOOMPI installer pacstraps
                                    a KOOMPI edition from [koompi]
```

> **Status: SKELETON.** `build-repo.sh` is a commented scaffold. The GPG key id
> and the publish target are `TODO` placeholders. Nothing here is wired to a
> production key or a live mirror yet.

## What `build-repo.sh` does

1. **Builds** every `sdata/dist-arch/koompi-*/PKGBUILD` into `packages/`.
2. **GPG-signs each package** (a detached `.sig` per `.pkg.tar.zst`).
3. **Builds the signed database** with `repo-add --sign` (signs `koompi.db`).
4. **Prints** the `pacman.conf` `[koompi]` snippet to publish.

```sh
# from this directory, as a NON-root user (makepkg refuses root):
GPG_KEY_ID=<your-key> PUBLISH_URL=https://repo.koompi.org/koompi/os/x86_64 \
  ./build-repo.sh
```

## Two signatures, not one (the thing people get wrong)

A repo set to `SigLevel = Required` verifies **two independent** signatures:

| What            | File                       | Signed by         |
|-----------------|----------------------------|-------------------|
| each package    | `*.pkg.tar.zst` → `*.sig`  | `makepkg --sign` / `gpg --detach-sign` (step 2) |
| the database    | `koompi.db.tar.gz` → `.sig`| `repo-add --sign` (step 3) |

`repo-add --sign` signs **only the database**. It does **not** sign the packages.
If the packages are unsigned, `SigLevel = Required` rejects the entire repo. That
is why package-signing and DB-signing are separate steps in the script — do not
collapse them.

## Key management

- **One packaging signing key** (RSA 4096 recommended). Generate it once.
- The **private key never lives in this repo.** Locally it stays in your GPG
  keyring; in CI it is injected as the `GPG_KEY` secret (see
  `.github/workflows/build-packages.yml`).
- The **public key is published** (e.g. `koompi-signing.pub.asc`) so clients and
  the ISO can import it.

```sh
gpg --full-generate-key                                    # RSA 4096
gpg --armor --export "$GPG_KEY_ID" > koompi-signing.pub.asc
```

### Clients must trust the key in pacman's OWN keyring

`pacman-key` maintains a keyring **separate** from your user GPG keyring. Until
the signing key is imported AND locally signed there, `SigLevel = Required` trusts
nothing:

```sh
sudo pacman-key --recv-keys  <GPG_KEY_ID>     # or: --add koompi-signing.pub.asc
sudo pacman-key --lsign-key  <GPG_KEY_ID>     # locally sign = trust
```

## How this feeds the archiso profile's `pacman.conf`

The archiso profile (`sdata/dist-arch/iso/koompi/`, in this scaffold) must use a
**custom `pacman.conf`** that injects `[koompi]` so `mkarchiso` can pull KOOMPI
packages into the live image — and so the live system can install an edition:

```ini
[koompi]
SigLevel = Required
Server = <PUBLISH_URL>          # e.g. https://repo.koompi.org/koompi/os/x86_64
```

On the ISO, also:

- ship `koompi-signing.pub.asc` in `airootfs`, and
- run `pacman-key --add` + `--lsign-key` in the archiso profile hook,

so the live environment trusts `[koompi]` out of the box and the installer can
pacstrap `koompi-desktop-hyprland` or `koompi-desktop-kde` from a signed source.

> The two `*-config` packages (`koompi-hyprland-config`, `koompi-kde-config`)
> `conflicts=` each other on shared `/etc/skel` theming paths. Both editions can
> live in one signed repo precisely because pacman refuses to install both
> configs together — "one edition per machine, chosen at install" falls out of
> the package metadata, not out of having two repos.

## Production note: clean-chroot builds

In-tree `makepkg` works locally because the `*-config` packages reach
`../../../dots` via `$startdir`. The production path is a **clean chroot**
(devtools / `makechrootpkg`), where that relative tree is absent. Before building
under devtools, switch the `source` of `koompi-hyprland-config` and
`koompi-kde-config` to a **pinned git tag** of this repo and copy from
`$srcdir/koompi-desktop/dots` — see the `BUILD NOTE` headers in those PKGBUILDs.
