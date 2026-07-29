# The KOOMPI Subsystem is a two-axis, trust-driven isolation model — three sanctioned modes, not one engine

The Subsystem is **not** a single containment engine. It is the product of **two orthogonal
axes** — *presentation* and *isolation engine* — with **three sanctioned combinations** (named
**modes**), and the engine is **selected by the trust level of the code being run**, never fixed.
This supersedes the implicit "the Subsystem is bwrap+netns" reading of
[[0002-subsystem-containment-bwrap-netns]] (whose analysis is now scoped to one mode) and
promotes Windows-app RemoteApp from a fidelity rung to a first-class App Window engine in
[[0003-foreign-os-apps-macos-out-windows-fidelity-ladder]].

## The two axes (orthogonal)

1. **Presentation** — how the contained app reaches the user:
   - **Seamless** — the app appears as a native-feeling window on the KOOMPI desktop; the user
     sees only the app, never the guest's shell/desktop. Requires *transparent channels*:
     display/pixel buffer, GPU, clipboard, drag-and-drop, input.
   - **Hermetic** — no display, no GPU, no shared filesystem, no clipboard. Headless. The only
     channel out is the network, and the network is fully mediated.
2. **Isolation engine** — what enforces host integrity:
   - **bwrap** — bubblewrap + a root-prepared netns + nftables. Reuses the host kernel and
     rootfs. Native speed, lowest RAM/disk. Shared host kernel = the trust boundary is the
     host kernel's syscall surface.
   - **microVM** — a separate guest kernel under a minimal VMM (crosvm / Cloud-Hypervisor),
     with virtio-gpu + Venus for an *isolated host renderer* (never VFIO/DMA passthrough — see
     reject-list). Near-native; VM-grade host-integrity boundary; supports seamless via
     waypipe/Sommelier (Linux) or QEMU+FreeRDP-RemoteApp/RAIL (Windows).
   - **VM (hermetic)** — Firecracker / Cloud-Hypervisor, headless, no display/GPU/shared-FS.
     Firecracker's headlessness is a *feature* here, not a limitation.

These axes are independent. A point on the engine axis does not dictate a presentation, and
vice-versa — which is why a single linear "tier ladder" is the wrong mental model and was
rejected during grilling.

## The three sanctioned modes (combinations)

| Mode | Presentation | Engine | Trust | Egress default | Ledger |
|------|--------------|--------|-------|----------------|--------|
| **Light** | seamless or CLI | **bwrap** | **trusted** code/app | LOCKED | complete *for network*; non-network channels open by trust |
| **App Window** (default) | **seamless** | **trust-selected**: trusted-Linux → bwrap; semi-trusted/foreign → microVM (Linux: virtio-gpu+waypipe/Sommelier; Windows: QEMU+RemoteApp/RAIL) | trusted → semi-trusted | LOCKED | **incomplete by construction** (see honesty clause) |
| **Detonation Chamber** (opt-in) | **hermetic** | **VM** (Firecracker/Cloud-Hypervisor, headless) | **untrusted** | LOCKED | **complete** — every egress is ledgered |

App Window's engine cell is deliberately **trust-conditional, not a fixed VM**: a *trusted*
Linux GUI app runs seamlessly under bwrap (Wayland-socket passthrough) at native speed; a
*semi-trusted or foreign* app gets a separate-kernel microVM. This is the confirmed
"engine-by-trust" decision (grill sub-fork A). The mode is the user-facing concept; the engine
underneath is chosen by trust.

## The hard invariant (the forced split — the decisive finding)

**Seamless presentation and detonate-safe isolation cannot coexist in one context.**

Seamless requires transparent channels (clipboard, drag-and-drop, GPU command stream,
display/pixel buffer). Those channels are **invisible to nftables** — they are not network
egress, so the Moat's "every egress is ledgered" guarantee **does not cover them**. Therefore:

> **Seamless ⇒ ledger-incomplete (for non-network channels) ⇒ barred for untrusted code.**
> **Untrusted code ⇒ hermetic + separate-kernel, always — no exceptions.**

This is why **App Window's ledger is incomplete by construction** and must be *labelled as
such* in the UI and audit surface — claiming a complete ledger for a seamless context would
repeat the spoofable-`includes("localhost")` honesty failure that ADR-0002 exists to prevent.
The complete-ledger guarantee lives **only** in the Detonation Chamber, whose hermeticism is
the price of completeness.

## Egress posture: a per-context dial, default LOCKED

Egress remains the [[0002-subsystem-containment-bwrap-netns]] plane (P-2 chokepoint, root-owned),
now per-context and — under the VM modes — **strengthened**: each context gets a host-owned TAP
device + an nftables chain that is *immune to a guest-kernel exploit* (the filter lives on the
host side of the vNIC, not in a guest-controlled netns). The ledger is host-side
(`org.koompi.Policy`) and survives context disposal.

What is **confirmed now**: **default LOCKED** — drop + allowlist + `nflog` audit — for every
mode. What is **available opt-in**: **OPEN** (accept + full audit) for contexts that legitimately
need broad reach. What is **deferred and separately gated** (NOT v1, NOT a default to be quietly
flipped): an **offensive-caps** posture (raw sockets / promisc / tun inside the guest), safe in
principle *only because* it is confined to a guest vNIC behind the host TAP — but it is recorded
here as a future possibility, not a shipped capability.

## Engine reject-list (grounded, with reasons)

- **gVisor** — out. A false middle: ~79% syscall coverage, no seamless GPU path, not a VM-grade
  host-integrity boundary. It neither satisfies seamless App Window nor matches the Detonation
  Chamber's VM guarantee.
- **Kata Containers** — out. Its OCI/image machinery contradicts the "one egress authority"
  principle of ADR-0002 and adds a parallel control plane.
- **VFIO / GPU passthrough** — **banned from any untrusted context.** Passthrough gives the guest
  DMA to host RAM, which breaks the VM boundary entirely. The seamless GPU path is
  **virtio-gpu + Venus** (an isolated *host* renderer), never passthrough.
- **distrobox / toolbx / podman** — out (per ADR-0002): ergonomics tools that share host netns
  and bind-mount `$HOME` → zero containment.

## The compositor lever

KOOMPI ships its own compositor (Hyprland/Quickshell), so it can **withhold capability protocols
from guest clients by design** — `wlr-screencopy`, `ext-data-control` (clipboard), and global
input are *not* exposed to a contained client unless the mode warrants it. This is a structural
advantage a generic desktop does not have, and it is what makes "seamless but not a free-for-all"
enforceable at the display layer.

## Prerequisite: per-context credential isolation (Q6) — RESOLVED

All three modes' isolation claims **silently assume** that a secret bound to one context is not
readable from another. **Today that assumption is false:** the host uses a single shared session
keyring (`secret-tool`, `KeyringStorage.qml:80-82`), so any same-UID process can read any
context's tokens.

**Resolved by [[0011-subsystem-credential-broker]] (Q6).** The credential boundary is the
*engine* boundary, not the store: **enforced** at the VM tier (guest-kernel keyring),
**hygiene-only** at the bwrap tier (which therefore holds at most short-TTL scoped tokens, never
a raw long-lived secret), and **nothing-to-steal** at the untrusted tier (deputy-only). The
single-shared-keyring leak above is the prerequisite that ADR fixes first.

## Relationship to prior ADRs

- **[[0002-subsystem-containment-bwrap-netns]] — scope narrowed, not reversed.** Its decision
  (bwrap + root netns + nftables, one egress authority, "convenience tier is not a security
  boundary") is **still in force for the Light tier** and its egress analysis holds for every
  mode's network plane. What changes is scope: bwrap+netns is **one engine of three**, not the
  whole Subsystem.
- **[[0003-foreign-os-apps-macos-out-windows-fidelity-ladder]] — extended.** Windows
  VM+FreeRDP-RemoteApp moves from "rung 3 of a fidelity ladder" to a **first-class App Window
  engine** for semi-trusted/foreign Windows apps. The macOS-out and Wine-last-resort decisions
  are unchanged.

## Consequences

- The user-facing surface speaks in **modes** (Light / App Window / Detonation Chamber); the
  engine is an implementation detail chosen by trust level.
- **App Window is the default** for foreign/semi-trusted apps; the **Detonation Chamber is
  opt-in** for "run this risky experiment without touching the host."
- Every VM mode is gated by **The Floor** ([[0001-degrade-local-never-silent-cloud]]): the
  microVM/VM tiers are 16 GB+ features, never promised on the floor; Light (bwrap) is the
  floor-friendly tier.
- The audit/UI must **label App Window's ledger as incomplete-for-non-network-channels** — the
  complete-ledger promise is Detonation-Chamber-only.
- **Q6 (per-context credential isolation) is a hard prerequisite**, not a nice-to-have; the
  brokered-auth contract (parked Q5) will land as a separate ADR (next free number) once resumed.
