# Package signing & [koompi] repo trust model

The `[koompi]` pacman repo ships **signed** — `SigLevel = Required`, with **every package and
the DB detach-signed** (`repo-add --sign` covers only the DB) — never `TrustAll`. Trust is
distributed by shipping `koompi-signing.pub.asc` on the ISO and running
`pacman-key --add` + `--lsign` at install.

**Publish target = `repo.koompi.org`** (`$repo/os/$arch`), the canonical home the code already
assumes. A GitHub Pages mirror is an acceptable *interim* if the mirror is not ready when CI is,
because the `Server=` URL is a one-line swap — **low lock-in**.

**Signing key = a dedicated RSA-4096 GPG key.** The custody model is the real decision (package
signing is **high lock-in**: rotating a key requires re-trusting it on every existing install).
For **v1 (pre-GA)** the private key lives as a CI secret enabling automated sign/publish, gated
by four guardrails:

1. **Dedicated key** — not reused for any other purpose.
2. **Revocation certificate generated at key-gen and stored offline.**
3. **Written rotation/rollover procedure** (ship the new key alongside the old for a transition
   window; revoke the old).
4. **Committed migration to hardware-token/offline signing before GA-at-scale** (when real
   schools deploy).

We chose CI-secret-with-guardrails over hardware/offline-from-day-one because v1 is pre-GA (the
installer does not yet execute — G1), so the risk surface is small and full CI automation is
worth more than air-gapped signing friction at this stage; the guardrails plus the pre-GA
hardening deadline bound the risk.

## Open (owner assignment — KOOMPI-internal, blocks key generation)

The **named key custodian** and the **revocation-cert storage location** must be assigned before
the key is generated. A signing key with no named owner is how distributions get compromised.

## Consequences

- Unblocks G-8 (flip the commented-out sign/publish steps in `build-packages.yml`) → G-2
  (installer + every `koompi-*` package on the ISO) → shipping the Rust daemons
  ([[0004-rust-daemons-zig-installer-dual-toolchain]]).
