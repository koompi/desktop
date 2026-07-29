# KOOMPI OS — Data-Ownership-Sync Plane (L-DOS)

Design for the local-first/private-by-default data ownership plane with opt-in sync.
Grounded in the live tree (Quickshell QML services, Zig installer/restore, btrfs subvol layout)
and the settled product decisions (Fork A). Three-way split: on-device (everything by default),
KOOMPI.Cloud (zero-knowledge ciphertext sync, self-hosted), Selendra (identity/ownership anchor only).

> **Role:** the canonical tiering table + dependency licenses live in `architecture.md` §13;
> this is the design-depth companion (subvol co-design, reconciliation ordering, phasing).
> On any conflict, §13 wins.

## Honest split (the load-bearing decision)

- ON-DEVICE: master key (FDO keyring + PAM, TPM2 optional), per-object DEKs, ALL plaintext,
  sqlite-vec index, Automerge CRDT working state. Nothing leaves unless explicitly opted in.
- KOOMPI.Cloud (self-hosted, zero-knowledge): E2EE content-addressed ciphertext blobs +
  encrypted CRDT op-log + version-vector metadata + optional wrapped key-escrow blob.
  Server sees ciphertext, sizes, timing — never plaintext, never keys.
- Selendra (public ledger, tiny + RARE writes only): DID doc, device public keys,
  key-rotation/revocation events, and a PERIODIC signed Merkle root over the object manifest
  ("these object-IDs are mine at time T"). Optionally capability/sharing grants. NOTHING else.
  Never per-operation. Never hash(plaintext) — only salted commitments / hash(ciphertext) / Merkle roots.

## Subvol co-design with L0 restore (extends the audit's L0/L1 demand)

v1 keeps the installer's **five SYSTEM subvolumes** (@ @home @var_log @var_cache @snapshots) —
no 6th *system* subvolume. The two stores layer on without changing that:
  index (v1)  -> a per-user NESTED subvol under @home: ~/.local/state/koompi  (chattr +C).
                Rebuildable, never synced, WIPED by `--full`, survives System Restore, and
                EXCLUDED from @home snapshots (a nested subvol is not captured in the parent
                snapshot — keeps a GB-scale rebuildable cache out of rollback points). Per-user,
                created at account setup — NOT a system subvol.
  @data (1.x) -> /var/lib/koompi/data  (canonical ENCRYPTED store, CRDT log, manifest), own
                snapper config. Ownership-plane (O-1+), NOT a v1 layout change, and distinct
                from the derived index above.
  master key in keyring (lives in @home) — `--full` wipes it (correct for hand-off)

Reconciliation: `--full` is LOCAL-ONLY (destroys local keys+data+index). Cloud ciphertext is
NOT auto-deleted by `--full` (keeps the PRD non-goal "reset is not a sync/backup product" honest).
Cloud delete is a SEPARATE explicit "Delete cloud account" action. Migration to a new device must
happen BEFORE `--full` or data is unrecoverable — the UX enforces this ordering.

## Phasing (= roadmap Track O — O-1..O-4; NOT prd.md §7's product phases P0–P3, which mean something different)
O-1 (v1): on-device encryption-at-rest (no cloud, no Selendra) — the privacy default, the v1 floor.
O-2 (1.x): single-device encrypted backup/restore to KOOMPI.Cloud (blob push/pull, LWW); DID at onboarding.
O-3 (1.x): multi-device Automerge CRDT sync + QR device pairing.
O-4 (1.x): Selendra anchoring (Merkle roots, rotation/revocation) + egress-audit UI + selective-sync UI.
