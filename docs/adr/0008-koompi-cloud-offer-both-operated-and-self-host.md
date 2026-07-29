# KOOMPI.Cloud: offer BOTH a KOOMPI-operated zero-knowledge tier and the same server self-hostable

KOOMPI ships **one** sync/backup server — **zero-knowledge by construction** (it stores
E2EE content-addressed ciphertext blobs + encrypted CRDT op-log + version-vector metadata;
it sees ciphertext, sizes, and timing, never plaintext, never keys) — and offers it **two
ways**: a **KOOMPI-operated** instance for users who just want it to work, and the **identical
binary self-hostable** for schools, orgs, and power users.

The two deployments are **cryptographically symmetric**: because the server only ever holds
ciphertext, "who runs the box" is an **operational/trust** choice, **not an architectural**
one. The same client, protocol, and key model work against either. **Default for
non-technical users = KOOMPI-operated; self-host is a first-class, documented path, not a
second-class fallback.**

## Why both (the trade-off)

- **Operate-only** would contradict the moat: a privacy OS whose only sync path is a vendor
  cloud is not credibly user-owned.
- **Self-host-only** would exclude exactly the non-technical users KOOMPI targets (a school
  teacher will not stand up a server) and would mean the headline "your data syncs" demo has no
  zero-setup path.
- **Both** costs KOOMPI real ops (running a service, becoming a target). We accept it because
  zero-knowledge makes the **marginal trust cost of operating it near zero** (a breach leaks
  ciphertext, not data), and self-host keeps the ownership story honest. The architecture must
  not make operated-vs-self-host asymmetric — if a feature only works on KOOMPI-operated, that
  is a design smell.

## Consequences

- This is **Track O / O-2 (1.x)** — sync ships after on-device at-rest (O-1, v1). No sync code
  ships without a written protocol + encryption-in-transit spec
  ([[0001-degrade-local-never-silent-cloud]] keeps the privacy default; this never becomes a
  silent cloud path).
- The egress to KOOMPI.Cloud is a **policy-gated, ledgered** destination like any other — the
  `koompi-syncd` host is in the allowlist only when sync is opted in
  ([[0002-subsystem-containment-bwrap-netns]] for the per-app egress model).
- `--full` factory reset is local-only; cloud ciphertext is deleted by a SEPARATE explicit
  "Delete cloud account" action (see `data-ownership.md`).
