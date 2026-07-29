# Publishing and signing the `[koompi]` package repository

This runbook is for KOOMPI release engineers publishing Arch packages for
installation with `pacman`. After following it, a fresh Arch client should be
able to verify the KOOMPI signing key, synchronize `[koompi]`, and install a
package without weakening pacman's signature policy.

> **Status: pre-production.** GitHub Pages is the selected initial host, but the
> production signing key, protected publishing environment, and live package
> repository are not configured yet.

## Repository layout

Publish the repository as a static directory:

```text
koompi/os/x86_64/
├── koompi.db
├── koompi.db.sig
├── koompi.files
├── koompi.files.sig
├── koompi-shell-<version>-x86_64.pkg.tar.zst
└── koompi-shell-<version>-x86_64.pkg.tar.zst.sig
```

Use a dedicated public GitHub repository, such as `koompi-packages`, rather than
committing generated packages to the desktop source repository. Publish its
static output with a custom GitHub Pages workflow.

The initial pacman endpoint is:

```ini
[koompi]
SigLevel = PackageRequired DatabaseRequired TrustedOnly
Server = https://rithythul.github.io/koompi-packages/$repo/os/$arch
```

Configure `repo.koompi.org` as the Pages custom domain before general release.
The stable client configuration then becomes:

```ini
[koompi]
SigLevel = PackageRequired DatabaseRequired TrustedOnly
Server = https://repo.koompi.org/$repo/os/$arch
```

GitHub Pages supports custom domains and HTTPS. Its published-site limit is
1 GB and its soft bandwidth limit is 100 GB per month. This is appropriate for
the initial package repository, but not for large ISO images or unlimited
distribution. Publish versioned ISO images through GitHub Releases. If the
package repository approaches the Pages limits, migrate the same static layout
to object storage without changing its trust model.

References:

- [GitHub Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)
- [GitHub Pages custom domains](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)
- [GitHub Releases storage and bandwidth](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases#storage-and-bandwidth-quotas)

## Prerequisites and ownership

Assign these responsibilities before generating a production key:

- a named signing-key custodian;
- an offline backup location for the primary key;
- a separate offline location for the revocation certificate;
- an approver for the production GitHub environment; and
- an owner for signing-subkey rotation.

Never store the offline primary key in the source repository or GitHub Actions.

## Create the signing key offline

On an offline or tightly controlled machine, create a dedicated RSA-4096
certification key:

```bash
gpg --quick-generate-key \
  "KOOMPI Package Signing <packages@koompi.org>" \
  rsa4096 cert 5y
```

Record the complete primary-key fingerprint:

```bash
gpg --list-secret-keys --with-subkey-fingerprint
```

Create a renewable signing subkey:

```bash
gpg --quick-add-key PRIMARY_FINGERPRINT rsa4096 sign 1y
```

Export the public key for clients:

```bash
gpg --armor --export PRIMARY_FINGERPRINT > koompi-signing.pub.asc
```

Export only secret subkeys for the protected CI environment:

```bash
gpg --armor --export-secret-subkeys PRIMARY_FINGERPRINT \
  > koompi-ci-signing-subkeys.asc
```

Generate the revocation certificate and move it to its assigned offline
location:

```bash
gpg --output koompi-signing-revocation.asc \
  --gen-revoke PRIMARY_FINGERPRINT
```

Publish the public key and its full fingerprint through the installer, ISO, and
project documentation. Do not publish the secret-subkey export or revocation
certificate.

## Build release packages

Build from a trusted commit or annotated release tag. Production packages must
be built in a clean Arch chroot from pinned sources. Do not sign artifacts
created by pull-request workflows or from an untrusted fork.

Before republishing a package, increment `pkgver` or `pkgrel`. Keep only the
intended current package artifacts in the repository staging directory so an
old glob cannot silently reintroduce obsolete builds.

## Sign packages and repository databases

Create one detached signature for every package:

```bash
for package in ./*.pkg.tar.zst; do
  gpg --batch --yes \
    --local-user PRIMARY_FINGERPRINT \
    --detach-sign "$package"
done
```

Build the repository databases, verify the package signatures, and sign the
database:

```bash
repo-add \
  --sign \
  --verify \
  --key PRIMARY_FINGERPRINT \
  koompi.db.tar.gz \
  ./*.pkg.tar.zst
```

`repo-add --sign` signs the repository database; it does not replace the
detached signature required for each package.

Verify every staged artifact before publishing:

```bash
for package in ./*.pkg.tar.zst; do
  gpg --verify "$package.sig" "$package"
done

gpg --verify koompi.db.tar.gz.sig koompi.db.tar.gz
```

See the [repo-add manual](https://man.archlinux.org/man/repo-add.8.en) for the
database and signature behavior.

## Publish through GitHub Actions

Use two separate jobs:

1. A build job produces clean-chroot package artifacts from trusted `main` or a
   release tag.
2. A sign-and-publish job imports the signing subkey, validates its full
   fingerprint, signs the artifacts, creates the repository database, and
   deploys the complete static directory to GitHub Pages.

Protect the second job with a GitHub Environment named `koompi-production`.
Require reviewer approval and restrict it to trusted branches and release tags.
Give the workflow only the permissions it needs. Signing secrets must be
environment secrets, unavailable before approval.

Suggested environment secrets:

```text
GPG_SIGNING_SUBKEY_ASC
GPG_SIGNING_PASSPHRASE
GPG_PRIMARY_FINGERPRINT
```

Serialize repository publications:

```yaml
concurrency:
  group: koompi-repository-production
  cancel-in-progress: false
```

Never sign artifacts produced by a pull request. Never print private key
material, passphrases, or decoded secrets in a workflow log.

GitHub Pages deployments replace the published static artifact as a unit. The
deployment must contain packages, package signatures, database files, and
database signatures together. Ensure `koompi.db` and `koompi.files` are real
published files rather than broken symbolic links inside the Pages artifact.

## Bootstrap client trust

Ship `koompi-signing.pub.asc` in the installer and ISO. Pin its complete
fingerprint in the bootstrap code and check it before modifying pacman's
keyring:

```bash
actual_fingerprint="$(
  gpg --show-keys --with-colons koompi-signing.pub.asc |
    awk -F: '$1 == "fpr" { print $10; exit }'
)"

test "$actual_fingerprint" = "EXPECTED_FULL_FINGERPRINT"

sudo pacman-key --add koompi-signing.pub.asc
sudo pacman-key --lsign-key "EXPECTED_FULL_FINGERPRINT"
```

Only after that verification should installation enable `[koompi]` in
`pacman.conf`. Do not use `TrustAll`, and do not trust a downloaded key solely
by its short key ID.

See the Arch documentation for
[package signing](https://wiki.archlinux.org/title/Pacman/Package_signing) and
[`pacman.conf`](https://man.archlinux.org/man/pacman.conf.5.en).

## Release verification

After every publication, test from a fresh Arch environment using the same
public key and repository stanza shipped to users:

```bash
sudo pacman -Syy
pacman -Si koompi-shell
sudo pacman -S --needed koompi-shell
koompi --version
```

Also fetch and verify a package and the repository database independently. A
release is not complete if the Pages deployment succeeded but a clean pacman
client cannot synchronize and install it.

## Rotation and recovery

Rotate signing subkeys before they expire. The offline primary key certifies the
replacement subkey; CI then receives a new secret-subkey export.

If the primary key must change:

1. publish the new public key while the old key is still trusted;
2. ship a signed keyring or installer update that trusts the new full
   fingerprint;
3. allow a transition period in which existing systems receive the new trust;
4. switch package and database signing to the new key; and
5. revoke the old key only after the migration is available.

If signing material is suspected to be compromised, stop publishing
immediately, remove the CI secret, use the offline revocation certificate, and
publish a recovery notice through a separately controlled KOOMPI channel.
