# The Subsystem credential boundary is the engine, not the store: hybrid-by-trust, VM-tier-only hard isolation, deputy-first egress auth

Per-context credential isolation (the prerequisite named in
[[0010-subsystem-two-axis-trust-driven-isolation]], parked Q6) is resolved as **hybrid by
trust**, on one decisive finding: **the credential boundary is the *engine* boundary, not the
store.** No same-kernel/same-UID store can contain a malicious context — so hard credential
isolation is a **VM-tier-only** guarantee; a **bwrap** context holds at most a **short-TTL,
scoped token** (never a raw long-lived secret); an **untrusted** context holds **nothing** and
is served by a host-side **deputy**. A host-side **broker** (`koompi-brokerd`) owns every secret
and is the only component that mints tokens, deputizes egress, and (separately — see Q5) runs
interactive auth flows.

This finding was earned: of 20 isolation claims put to an adversarial refutation pass, **15
fell.** The survivors below are the design.

## The decisive finding: boundary = engine, not store

A "per-context private store" sounds like the answer to Q6. It is not. Against an **active
same-UID adversary** — a context that `ptrace`s or `process_vm_readv`s a sibling, or reads
`/proc/<pid>/{environ,mem,root}` — **no store isolates anything**: the attacker scrapes the
plaintext from the app's own memory *after* the app fetches the key, regardless of where it was
stored. Therefore the credential boundary can only be a boundary the kernel enforces between
*processes*, which on a shared host kernel + shared UID does not exist. The Subsystem already
solves this structurally: hybrid-by-trust routes untrusted code to a **separate-kernel VM**
*precisely because* the store cannot contain it. The store choice is downstream of the engine,
and the engine is downstream of trust.

## D1 — Hard credential isolation is VM-tier-only

- **VM modes (semi-trusted App Window microVM; Detonation Chamber):** isolation is **enforced by
  the guest-kernel boundary** — each guest has its own kernel keyring and its own Secret-Service
  daemon in its own VMM-process RAM; there is no shared `keyctl(2)`, no shared session bus, no
  shared `/proc`. Context-vs-context credential isolation is a property the VMM *gives* you. This
  was the one positive isolation claim that survived adversarial review.
- **bwrap modes (Light; trusted-Linux App Window):** a bwrap context **never stores a raw
  long-lived secret.** Its credential hygiene (per-context tmpfs `XDG_RUNTIME_DIR`, private
  pathname-socket D-Bus session, fresh joined `@s` session keyring) blocks *accidental*
  cross-reads but is **not a boundary against active same-UID code.** It is honest **only because
  hybrid-by-trust structurally bars untrusted code from bwrap** — untrusted code goes to a VM.

## D2 — Deputy-first egress authentication

A trusted bwrap app's outbound traffic routes through the **broker as an authenticating proxy**
by default; the broker injects auth at the network boundary and **the app holds no credential at
all.** An in-context short-TTL token is handed over **only** when deputization is impossible:
the app pins certificates, speaks a non-HTTP/opaque protocol, or uses an SDK that must read a
token itself. This reuses the deputy machinery already mandatory for untrusted contexts (one
egress-auth path, not two), minimizes secrets-in-context, and extends the Moat's host-side
ledger to trusted-app traffic — the **network slice only**: a *seamless* App Window context's
clipboard/GPU/display channels remain unledgered per ADR-0010's incomplete-ledger clause.

**Stated posture (a deliberate trade-off, not a side effect):** deputy-first means KOOMPI
installs a **local CA** and **terminates trusted-app TLS** by default to inject auth and ledger
egress. This is defensible — it is the user's own machine and the user's own broker making the
real upstream connection — but for a privacy-positioned OS it is a posture we **state**, not one
a user should discover from a packet capture. The deputy must mitigate the **confused-deputy /
reflection** risk (the real failure mode, not the TLS mechanics): pin leg-2 destination to a
broker-fixed origin the guest cannot redirect, enforce the same origin in the nftables allowlist,
mint **short-TTL audience/destination-scoped** tokens (never the static host bearer), and treat
the relayed response as hostile for credential-bearing requests.

**What the deputy cannot do (honest limits):** it cannot deputize an app that **pins
certificates** (leg-1 handshake against the local-CA leaf is rejected below the injection layer),
an app using **E2E encryption above TLS** (no plaintext field to inject), or a **non-HTTP/opaque
protocol** (no Authorization header to act on). Those fall back to an in-context short-TTL token.
*(Correction to a common assumption: upstream **mTLS** does **not** break the deputy — the broker
is the sole leg-2 client and presents the client cert it holds. Only **guest-originated** binding
— DPoP/token-binding, which require a guest-held key — is excluded, by the "secret never enters
the context" premise.)*

## D3 — Snapshot constraint (forward-looking)

microVM snapshotting is **not built**. If/when it is, **secret-bearing guests are
non-snapshottable**: a snapshot serializes full guest RAM (secret included) to a host file, and
restoring it into N guests replicates the secret across siblings (VMGenID reseeds only the PRNG,
not arbitrary secrets). The forward-looking contract: warm-start uses a **secret-free snapshot**
plus a **fresh per-restore secret re-injected over vsock**. Recorded as a constraint on a future
feature, not a co-equal v1 decision.

## Context identity + broker control channel (per engine — NOT uniform)

How a context reaches the broker, and how the broker attests *which* context is calling, is
**engine-conditional** — there is no single mechanism:

- **bwrap contexts (Light, trusted-Linux App Window):** control channel is a **pathname
  `AF_UNIX` socket** (never an abstract `@`-socket — those are netns-scoped). Identity is
  **`SO_PEERCRED`** on that socket — the host kernel attests the peer's pid/uid; the context
  cannot spoof it.
- **VM contexts (semi-trusted microVM App Window):** control channel is **vsock** (`AF_VSOCK`).
  `SO_PEERCRED` does **not** apply across the VM boundary (no shared kernel; a guest-reported
  pid/uid is meaningless to the host). Identity is the **host-assigned vsock CID**, which the
  host (not the guest) controls — that is the attestation.
- **Detonation Chamber (untrusted, hermetic):** **no broker control channel at all.** By the
  ADR-0010 definition it is network-only; its sole broker interaction is the network-layer
  **Deputy**. It never calls the broker for a token (it holds none) and never runs a brokered
  auth flow that yields an in-context credential.

The invariant is therefore **host-attested identity** (SO_PEERCRED for bwrap, host-assigned CID
for VM), never a name the context asserts — the *mechanism* varies by engine, the *property*
does not.

## Settled prerequisite — the per-context *source* store

Independent of D1–D3: the broker must read each secret from a **per-context** store, **not**
today's single shared collection (`secret-tool store … application koompi`, one JSON blob —
`KeyringStorage.qml:24,80,86`), which any same-UID process drains in one `secret-tool lookup`.
Until that source store exists, every mode leaks host-side *before* any per-mode mechanism
applies. This is the floor of Q6 and is not optional.

## Load-bearing rules (the corrections the refutation pass forced)

- **Never write a context secret to the kernel `@u` (user) or persistent keyring** — both are
  per-UID and readable from any fresh same-UID session (`keyctl get_persistent` confirms it
  live). Only the **joined anonymous `@s`** (`KEYCTL_JOIN_SESSION_KEYRING(NULL)` before exec) is
  per-context. *(And bwrap alone / `--unshare-user` / `--new-session` give zero keyring
  isolation — the host session tree stays readable via `@s` unless explicitly rejoined.)*
- **Pin the per-context D-Bus to a `unix:path=` socket and disable abstract fallback** — abstract
  sockets are keyed to the **network** namespace, not the mount namespace, so they ignore the
  per-context tmpfs entirely.
- **Per-context private `$HOME` (or keyring store dir)** — gnome-keyring's on-disk store under
  `~/.local/share/keyrings/` is readable with zero D-Bus from a shared `$HOME`.
- **Provisioning into a microVM uses virtio-vsock early-boot pull** (broker → host CID 2 →
  guest RAM), never the kernel cmdline (`/proc/cmdline`, host argv), `fw_cfg`
  (`/sys/firmware/qemu_fw_cfg`, QEMU-only), or a CIDATA seed disk (persists on disk). The kernel
  cmdline must be **secret-free** for every guest.

## Honest residual risks (the credential analogue of ADR-0010's incomplete-ledger clause)

1. **bwrap is hygiene, not containment.** Any cross-context isolation claim for Light /
   trusted-Linux App Window is accidental-leak hygiene; an active same-UID adversary (including
   an RCE'd *trusted* app) reads siblings' secrets via ptrace/proc-mem regardless of the store.
   Honest **only** while untrusted code is structurally barred from bwrap.
2. **microVM swap/hibernation** can persist guest RAM to plaintext disk (Firecracker does not
   `mlock`; LUKS is off by default) — and snapshot/restore replicates secrets (D3).
3. **Host compromise** (a virtio-gpu/Venus renderer or VMM RCE) defeats every guest at once: the
   VM boundary protects guests from each other, not from a compromised host.
4. **Deputy confused-deputy/reflection** can exfiltrate the host credential despite correct TLS
   mechanics; pinned/E2E/non-HTTP guests cannot be deputized at all.

## Relationships

- **Resolves Q6 of [[0010-subsystem-two-axis-trust-driven-isolation]]** — its "per-context
  credential isolation is aspirational, not enforced" caveat is now answered: enforced at the VM
  tier, hygiene-only at the bwrap tier, nothing-to-steal at the untrusted tier.
- **Builds on the egress plane of [[0002-subsystem-containment-bwrap-netns]]** — the deputy
  routes through the same root-owned P-2 chokepoint; the broker reads from the per-context store
  the egress authority already keys by `context_id`.
- **Interactive auth (parked Q5) is a separate, forthcoming ADR.** The broker defined here is the
  same daemon that will run OAuth callback-relay / device-code flows, but that contract has not
  yet been re-examined in the two-mode frame and is **not** settled by this ADR.

## Consequences

- The **broker (`koompi-brokerd`) is a hard dependency** for any authenticated Subsystem app —
  it is on the critical path for trusted-app egress (latency + a single point of failure),
  accepted for the one-egress-authority and ledger benefits.
- The user-facing promise must say **bwrap credential isolation is hygiene, hard isolation is the
  VM tier** — never claim a bwrap context "safely holds your key."
- Token minting must be **short-TTL + audience/destination-scoped**; a static long-lived bearer
  must never be injected or stored in any context.
