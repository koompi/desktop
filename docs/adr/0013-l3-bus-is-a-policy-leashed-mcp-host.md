# L3 is a policy-leashed MCP host, not a new protocol

**`koompi-busd` implements the Model Context Protocol (host role) for app
capabilities; `org.koompi.Policy` wraps every call.** Apps integrate by exposing MCP
servers (manifest-registered, packaged in `[koompi]` where possible); `assistantd`
consumes capabilities through busd. The roadmap's "MCP-shaped manifests" instinct
becomes literal adoption.

Why now: MCP won the tool layer — donated to the Linux Foundation's Agentic AI
Foundation (2025-12, backed by Anthropic, OpenAI, Google, Microsoft, AWS), >10k public
servers, ~97M monthly SDK downloads, with 2026 roadmap work (tasks, triggers,
discovery, skills) covering exactly the primitives L3/L4 would otherwise invent.
**KOOMPI's invention budget goes to the leash — consent, capability tiers, egress
containment, audit — never the wire format.** Evidence: brainstorm §87 (verified
2026-06-11).

Containment is non-negotiable: an MCP server is third-party code, so it runs under
the Subsystem trust model ([[0010-subsystem-two-axis-trust-driven-isolation]]) —
KOOMPI-signed servers in **Light**, foreign in **App Window**, untrusted in the
**Detonation Chamber**. Transport defaults to stdio/unix-socket (local); any network
transport is egress and routes through the chokepoint (roadmap §2.2). Tool arguments
are schema-validated and enter the **one uniform gate** (architecture §6) — an MCP
tool is never more privileged than a native one, and headless (L4) contexts stay
READ-only.

Trade-offs accepted: protocol churn (mitigated by neutral governance + pinned SDK
majors) and uneven server quality (mitigated by an allowlist-first discovery:
`[koompi]`-packaged servers by default; sideloading = explicit consent + App Window).
D-Bus remains the OS control plane per [[0004-rust-daemons-zig-installer-dual-toolchain]];
MCP is the *capability* plane on top, not a replacement.
