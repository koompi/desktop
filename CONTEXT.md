# KOOMPI OS

"The OS That Thinks" — an AI-first, data-aware, general-purpose Linux (Hyprland + KDE
editions) whose differentiator is data ownership in the AI era. This glossary fixes the
language the design docs, code, and team use so the same word never means two things.

## Language

**The Moat**:
KOOMPI OS's differentiator — data ownership in the AI era, on two pillars: (1) the index,
models, and data stay on-device by default; (2) **provable per-app egress containment** — an
app's network reach is enforced by the kernel (netns + nftables) and audited in a ledger,
not merely trusted.
_Avoid_: "the AI feature", "our edge", "the AI moat" (AI presence is not the moat; ownership is).

**The Thinks stack**:
Layers L1–L4 (context engine, assistant, app-bus, automation) — the "thinks" capabilities
built atop the L0 base. Today ~0% built.
_Avoid_: "the AI layer", "the smart stack".

**The Floor**:
The guaranteed-minimum hardware KOOMPI OS v1 commits to running the full local stack on —
the validation target, not a marketing surface.
_Avoid_: "minimum specs", "system requirements".

**Reduced-local mode**:
The degraded operating mode at/below The Floor where embedding + retrieval run locally but
local chat is disabled.
_Avoid_: "lite mode", "fallback" (too vague — see the anti-term below).

**Consented refusal**:
The system declining an action it cannot perform locally, via an explicit user choice,
instead of routing it elsewhere.

**Silent cloud fallback** _(anti-term — forbidden)_:
Automatically sending a request to the cloud when the local stack cannot serve it, without
explicit consent. Forbidden because it inverts The Moat.

**The Subsystem**:
KOOMPI OS's facility for running an app in a per-session **isolated context** — its own
credentials, its own egress posture, its own integrity boundary — so an app cannot affect the
host or read another context's secrets. Always realized as one of three **Modes**.
_Avoid_: "the sandbox", "the container" (overloaded; a Mode may or may not be either).

**Mode**:
One of the three sanctioned configurations of a Subsystem context, chosen by the **trust** of
the code being run: **Light**, **App Window**, or **Detonation Chamber**.
_Avoid_: "tier", "level" (implies a single ladder; the Modes differ on two independent axes —
presentation and integrity — not one).

**Light** _(Mode)_:
The trusted-code Mode: lowest overhead, runs at native speed, floor-friendly. Containment is
real but minimal — for code KOOMPI already trusts.

**App Window** _(Mode, default)_:
The **seamless** Mode for semi-trusted or foreign apps: the app appears as its own native-feeling
window on the KOOMPI desktop. Its audit ledger is **incomplete by construction** (see _Seamless_)
and must be labelled as such.

**Detonation Chamber** _(Mode, opt-in)_:
The **hermetic** Mode for **untrusted** code — "run a risky experiment without touching the
host." The only Mode whose egress ledger is **complete**; the price of that completeness is
hermeticism.

**Seamless** _(presentation)_:
The app is shown as a native-feeling window; the user never sees the guest's shell or desktop —
only the app. Requires transparent channels (display, clipboard, drag-and-drop, GPU) that are
**not network egress** and therefore **cannot be fully ledgered** — so seamless is never used for
untrusted code.
_Avoid_: "integrated", "windowed" (too weak — seamless is a security-relevant claim).

**Hermetic** _(presentation)_:
No display, no GPU, no shared filesystem, no clipboard — headless. The network is the only
channel out, and it is fully mediated, so a hermetic context's ledger is complete.
_Avoid_: "headless" alone (true but undersells the no-shared-channels guarantee).

**The Broker**:
The host-side component that owns every Subsystem credential. It is the only thing that mints
scoped tokens, authenticates a context's egress on its behalf (see _Deputy_), and runs
interactive login flows — so that a credential lives in as few places as possible. A context
proves its identity to the Broker by **host** attestation (the host kernel's `SO_PEERCRED` for
bwrap contexts, the host-assigned vsock CID for VM contexts), not by a name it can spoof.
_Avoid_: "the keyring", "the auth service" (too narrow — the Broker is the single authority, not
a passive store).

**Deputy** _(of the Broker)_:
The Broker acting as an authenticating proxy: it makes a context's network connection *for* it
and injects the credential at the boundary, so the secret never enters the context. The default
for untrusted contexts and for trusted contexts whose traffic can be proxied.
_Avoid_: "the proxy" alone (undersells that the Deputy is what keeps the secret out of the
context).

## Relationships

- At or below **The Floor**, the system enters **Reduced-local mode** or issues a
  **Consented refusal** — never a **Silent cloud fallback**.
- **The Moat** holds only while the local **Thinks stack** runs within **The Floor**.

## Example dialogue

> **Engineer:** "The 4GB machine can't hold the chat model — should we just call the cloud so the feature still works?"
> **Founder:** "No. That's a **Silent cloud fallback** — it breaks **The Moat**. Drop to **Reduced-local mode** (search still works) or give a **Consented refusal**. The user decides if anything leaves the device."

## Flagged ambiguities

- "fallback" was used to mean both graceful local degradation and silent cloud routing —
  resolved: **Reduced-local mode** (allowed) vs **Silent cloud fallback** (forbidden).
