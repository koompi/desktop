# KOOMPI Subsystem containment uses bubblewrap + netns + nftables, not distrobox/podman

> **Scope narrowed by [[0010-subsystem-two-axis-trust-driven-isolation]] (not superseded).**
> bwrap + root netns + nftables is the **Light tier** engine of a three-mode model, not the
> sole Subsystem engine. Everything below — the rejection of distrobox/podman, "one egress
> authority," and "the convenience tier is not a security boundary" — **remains in force**, and
> the egress-containment analysis holds for the network plane of every mode.

The **KOOMPI Subsystem** (per-session contained app contexts — e.g. running the same CLI
binary against different providers with isolated credentials and egress) is built from
**bubblewrap + a root-prepared network namespace + an nftables egress allowlist** — a
per-context generalization of the P-2 chokepoint (architecture.md §9) — **not** distrobox,
toolbx, or podman images.

We rejected the reflexive container-runtime path because distrobox/toolbx are *ergonomics*
tools: they bind-mount `$HOME` and share the host network namespace by design, giving **zero**
egress or credential containment. For the use case (the **same host binary** with scoped
provider env, not a foreign-distro userland), a full image buys nothing and costs RAM/disk
against **The Floor** ([[0001-degrade-local-never-silent-cloud]]). bubblewrap reuses the host
rootfs (no image) and the netns+nftables layer *is* P-2 with one allowlist per context, so the
Subsystem **reuses the existing egress plane** instead of adding a parallel one.

The trade-off: we hand-build the netns/nftables/mount plumbing rather than inheriting it from a
container runtime — accepted, because it keeps one egress authority and fits constrained
hardware. A future **foreign-userland or GUI** tier (1.x+) may revisit distrobox (Arch-native,
`distrobox-export`); it is out of scope for the CLI MVP.

## Consequences

- The convenience tier (`koompi-run --profile=…`: env + scoped key + scoped config dir) ships
  earlier as a standalone wrapper and is **explicitly NOT a security boundary** — labelling it
  as isolation would repeat the spoofable `includes("localhost")` mistake (`Ai.qml:544`).
- Containment is real only because enforcement is **root-owned** (netns + nftables), per the
  §9 finding that a session-bus daemon is not an enforcement boundary.
