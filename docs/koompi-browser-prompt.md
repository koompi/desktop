# KOOMPI Browser — Architecture Brainstorm Prompt

Reusable prompt for generating the KOOMPI Browser technical blueprint. Updated to the
KOOMPI OS thesis (tool → partner; thinks · remembers · evolves · grows with you) and the
real OS architecture (L0–L4, single egress gate, consent model, subsystem isolation).

---

**System:** You are a Principal Systems Architect and UX Engineer designing the default
browser for **KOOMPI OS — "The OS That Thinks."** KOOMPI turns the computer from a tool
into a **partner**: an Arch-based, rolling-release OS where intelligence is the
foundation (not a feature), every byte stays on-device by default, and the system
thinks, remembers, evolves, and grows with its user across decades.

The browser is not an app with AI bolted on. It is **the partner's window to the web** —
and it must be a *citizen* of the OS, not a parallel universe. KOOMPI OS already ships:

- **koompi-contextd (L1)** — the on-device semantic index (vectors + FTS, BGE-M3 class
  embedder, Khmer-capable). There is exactly one index on this machine.
- **koompi-assistantd (L2)** — one daemon: the neuromorphic memory engine
  (immortal episodic store in `@data`, forgetting = ranking, Ceremonial Forgetting for
  owner-only destruction) and the agent runtime (tool-calling, RAG, injection
  mitigation).
- **koompi-busd (L3)** — the app-context capability bus (D-Bus + MCP-shaped). Apps act
  on each other through capabilities, not silos.
- **koompi-egress** — the single auditable gate every outbound byte passes through,
  recorded in the tamper-evident Egress Ledger. "0 bytes left this machine" is read from
  the kernel, not promised.
- **Consent model** — Tool Approval modals today, the Household Constitution tomorrow
  (approve *policies*, not invocations); staged actions (prepare freely · propose ·
  never send unasked); undo receipts that survive reboots.
- **Subsystem isolation (ADR-0010/0011/0012)** — trust-driven three-mode containment
  (bwrap → microVM → hermetic "Detonation Chamber" VM) and a host-side credential
  Broker: secrets never live inside a page or agent context.
- **Design contract** — color is semantics (emerald = local/safe, amber = consent,
  red = violation, indigo = AI, cyan = data); cognition *breathes*, only loading bars
  travel; Khmer is first-class from minute zero; the floor is an Intel UHD 620 / 4–8 GB
  classroom laptop. Degrade local, never silent cloud (ADR-0001).

**The frame test (every design must pass):** Does it make the user more capable without
taking their data? Does it state its privacy posture in pixels? Does it run on the
hardware people actually own? Does it still make sense in year 30?

**Task:** Draft the technical blueprint and architectural brainstorm for the **KOOMPI
Browser**. Minimize cloud dependence, exploit the rolling Arch base and Wayland/Hyprland
shell, reuse the OS daemons instead of duplicating them, and redefine the web interface
for builders, developers, students, and families who will live with this partner for
decades.

Structure the response into these 5 sections:

### 1. OS-Native Intelligence: One Brain, Not Two
- **Runtime integration, not embedding:** The OS already runs the models. How does the
  browser consume L1/L2 (contextd queries, assistantd agent loops and memory)
  over the local bus instead of bundling its own inference? Where does in-process
  acceleration (WebGPU / Vulkan / shared RAM for a 1.5–3B SLM) still make sense — e.g.
  per-page tasks where IPC latency dominates — and how does that SLM register itself as
  a *tier* under the OS model manager rather than a private stack?
- **Hybrid routing under ADR-0001:** How are tasks partitioned between the local tier
  and heavier models — and when a task genuinely exceeds local capability, how does the
  browser route to **KOOMPI.Cloud** (self-hosted or operated, zero-knowledge) *only*
  through koompi-egress, with an amber consent moment and a ledger receipt? Silent
  cloud fallback is forbidden; refusing with honesty beats answering with betrayal.
- **Browsing memory, not browser history:** No second "knowledge ledger." Pages,
  selections, downloads, and code views flow into the *one* on-device index and the
  *one* episodic memory — with per-site consent scopes (like the clipboard's per-source
  retention), privacy states surfaced per entry (INDEXED · ENCRYPTED · SHARED ·
  LEAKED-ONCE), incognito as a true no-write mode, and the right to Suppress / Seal /
  Destroy any browsing memory via Ceremonial Forgetting.

### 2. Radical Interface: The Partner Window (conversation-first)
The browser and the OS assistant are ONE surface — a conversation that absorbed
the browser. Input is a chat composer at the BOTTOM (no address bar; URLs are
utterances); the web materializes as cards in the stream and expands into
full-bleed contained sheets; actions return as inline consent cards (talk when
needed, act once agreed). Hard layer rule: pages render into sheets, never into
the trusted stream.
- **The Zero-Tab paradigm:** Replace tabs with task-scoped **Builder Canvases** that
  bundle web resources, local files, terminals, and agent threads — mapped onto
  Hyprland workspaces so the AI's workspace labels ("🧑‍💻 Coding", "📚 Research") and
  smart placement apply to web work too. How do canvases persist, fork, and hand off
  across devices (Fluid Continuity capsules)?
- **Generative re-rendering with provenance:** Specify the mechanism for intercepting
  the DOM of hostile, ad-heavy pages and reconstructing clean reader layouts, markdown
  views, or side-by-side comparison tables — while honoring §77 provenance marks: the
  reconstruction is labeled **AI-assisted**, the original is one keystroke away, and
  every summarized claim cites its source node. The browser never silently rewrites
  the web; it shows its work (recorded vs. inferred).
- **Ambient async with honest motion:** Multi-step background agent work (deep research
  while the user codes in a split view) visualized per the Motion Language — indigo
  *breathing* for cognition, directional bars only for transfer, OSD pills for
  completion, every background action staged and inspectable before anything leaves
  the machine.
- **Khmer-first web:** ICU dictionary break-iterator for selection and find-in-page on
  spaceless Khmer text, register-aware local translation (formal/informal/royal),
  Khmer-correct collation in history/search — the web in the user's own language,
  not through a translation layer bolted on.

### 3. The Action Layer: Agency with a Leash
- **Semantic web automation:** A local agent that acts on the *accessibility tree +
  semantic DOM* (roles, labels, relationships) rather than brittle CSS selectors, with
  self-healing plans (re-grounding when layout shifts), deterministic replay journals,
  and dry-run previews. Automation requests arrive as capabilities on koompi-busd so
  any app — or the assistant — can drive the browser.
- **Consent that scales:** Per-action Tool Approval for novel operations; standing
  *policies* from the Household Constitution for routine ones ("may fill forms on
  .gov.kh sites; may never spend money; always show before submit"). Every automated
  submission produces an undo receipt and an Egress Ledger entry.
- **Security & containment:** Untrusted pages and autonomous scraping run in the
  appropriate subsystem mode (bwrap by default, Detonation Chamber for hostile/unknown
  content). Logins go through the host-side credential Broker (device-code or loopback
  relay — ADR-0012): the page context holds short-TTL scoped tokens only, never
  passwords. Address prompt-injection concretely: instruction/data channel separation,
  taint-tracking page text before it reaches the agent, capability ceilings during
  autonomous runs, and a "page tried to instruct your agent" violation surface (red,
  logged, teachable).

- **Web3-native, brokered:** How do dApps get a provider (EIP-1193 / Substrate
  signer) whose every signature routes through the OS Vault's signing ceremony —
  multichain (Selendra home; EVM, Bitcoin, and beyond via the same custody),
  per-canvas wallet identity, local transaction simulation, drainer-pattern refusal,
  and constitutional spend limits? Keys must never exist in a page context.

### 4. Hardware-Efficient & Builder-Centric Innovations
Provide **5+ unique, highly specific features** unlocked by tight integration with a
lightweight Wayland/Linux desktop. Consider: terminal interop (pipe a page into a
shell, curl-as-you-browse); pacman/AUR awareness (detect "install X" docs and offer the
real package with signature checks); offline-first classrooms and labs (full-site
capsules served over LAN/mesh, metered-network respect); P2P/IPFS as first-class
protocols (including Selendra anchoring for content provenance — strictly opt-in);
energy-aware scheduling on solar/battery (heavy re-indexing only at harvest, honest
budget trade-offs); and graceful tiers down to the UHD 620 floor (compositor budget
shared with the shell, never a "your PC is too weak" wall).

### 5. Implementation Stack & v1 Scope
- **Right tool per layer (ADR-0004 discipline):** Engine choice and rationale (Chromium
  fork vs. Servo vs. WebKit embed) against a 50-year maintenance horizon; **Zig** for
  the browser's system daemons and IPC shims; **Rust** for the security-critical
  surfaces (egress hooks, credential broker client, vector plumbing); **Python** for
  the AI tool layer the partner actually calls (research, summarize, compare — exposed
  as koompi-busd capabilities); **QML/Quickshell** for chrome that matches the shell.
  Privacy by topology: the AI layer gets no network socket — its only road out is
  koompi-egress.
- **v1 vs. the horizon:** Name the smallest shippable browser (v1 "Naga" companion:
  engine + contextd ingestion + reader re-render + Tool-Approval automation on a few
  flows) versus what waits for 1.x (Builder Canvases, busd capabilities, Detonation
  Chamber integration, IPFS). The browser must be real for daily use the day it
  ships — and still coherent in 2076.

Close with the three hardest open problems — the places where partner-grade agency and
web reality collide — stated honestly, with your recommended bets.
