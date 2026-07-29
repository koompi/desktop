# Ai.qml → koompi-assistantd is an ATOMIC v1 extraction; briefing logic is edition-agnostic

The agent brain currently living in `Ai.qml` is extracted into `koompi-assistantd` as a
**single atomic v1 block, not an incremental migration.** Four responsibilities are coupled and
**must land together**: per-conversation **state isolation**, **two-tier memory**, **native
`/api/chat` tool-calling**, and **prompt-injection mitigation**. Shipping any one without the
others is unsafe (tool-calling without injection mitigation is a remote-code path; memory
without state isolation lets headless automation clobber live chat), so they are one unit.

**Internal A/B phasing within the block** (sequencing, not separate ships):
- **A — safe substrate:** lift conversation state out of the shell into the daemon; wire it to
  the fail-closed `org.koompi.Policy` stub; uniform approval gate on every tool path. No new
  capability — just the safe shell-to-daemon boundary.
- **B — capability layer:** RAG with untrusted-tagging, two-tier memory, native tool-calling —
  **and injection mitigation in the SAME commit as tool-calling**, never after
  ([[0001-degrade-local-never-silent-cloud]] for the local-first default this runs under).

**Injection-gates-tool-calling is a hard ordering, not a phase** (roadmap §2.3): the egress
boundary (P-2) + sandbox (P-3) + uniform gate (P-4) land BEFORE local tool-calling (L2-2).

**Briefing logic is edition-agnostic.** The morning-briefing / headless flow is a daemon
capability (`koompi-assistantd` headless `Ask()`), **not** a property of any shell edition. It
runs the same on Hyprland/Quickshell and KDE, so **the KDE edition gets the briefing in v1** —
this closes the prd §7 "named scope decision" (KDE briefing was the open question; answer: in,
because it is not edition-specific work).

## Why atomic (the trade-off)

The alternative was incremental extraction (ship state isolation, then memory, then
tool-calling over several releases). We rejected it because the safety properties are
**emergent across the four pieces** — an incremental path necessarily passes through states
that are individually shippable but jointly unsafe (e.g. tool-calling live while injection
mitigation is "next sprint"). Atomic costs more up-front and delays the first agentic demo, but
there is no safe partial ordering. The A/B split recovers *some* incrementality WITHOUT crossing
an unsafe boundary: A adds no capability, so it can land and bake before B.

## Consequences

- This block is the **v1 L2 deliverable** (roadmap Track L2); it cannot start until the Track P
  safety floor (P-2/P-3/P-4) exists ([[0002-subsystem-containment-bwrap-netns]] generalizes that
  same boundary later).
- The KDE edition is a first-class v1 briefing target, not a follow-on — plan KDE consent-agent
  parity into v1, not 1.x.
