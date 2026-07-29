# KOOMPI OS — The Blueprint (design register)

**v1.2 · 2026-06-13 · status: binding**

This is the binding map from every design surface in the brainstorm to a build
commitment. Where the brainstorm and this register disagree, **this register wins**;
where this register and an ADR disagree, **the ADR wins**. Companions:
[`architecture.md`](architecture.md) (how), [`roadmap.md`](roadmap.md) (when — tracks
G/R/P/L1/L2/…), [`horizon.md`](horizon.md) (the vision shelf), [`CONTEXT.md`](../CONTEXT.md)
(the language), [`brainstorm/`](brainstorm/) (the §-numbered design surfaces),
brainstorm **§87 The Near Future** (the dated evidence behind these stamps).

## 0 · The stamps

| Stamp | Meaning |
|---|---|
| **v1** | Ships with Naga. Capability-gated, never event-gated (roadmap §11). |
| **1.x** | Committed; lands after v1 in track order. |
| **GATED(id)** | Ships when the named gate in §3 passes — never on a date. |
| **RULE** | Not a feature: an engineering rule enforced from now (ADR or CI). |
| **HORIZON** | Vision; lives in `horizon.md`. Only its named kernel is engineering. |
| **CUT** | Removed, reason recorded. Re-opening requires new dated evidence. |

A stamp may carry a **delta** — the part of the brainstorm section that does *not*
survive into the commitment. Deltas reference the corrections register (§6).

## 1 · The 2026-06 calibration

Five verified facts (sources in brainstorm §87) set the posture of every stamp below:

1. **The RAM crisis.** DDR5 ≈3–4× year-over-year; Gartner forecasts +130% memory/SSD
   through 2026, relief no earlier than late 2027. **T0/T1 hardware is the mainstream
   product through at least 2028.** No plan may assume cheap RAM before then.
2. **Small models now target tools.** 1–4B instruct models ship with function calling
   as a design goal; grammar-constrained decoding makes malformed tool calls
   structurally impossible. Local agency at the Floor is real — *bounded* agency.
3. **Khmer speech flipped.** A 106.5 h curated Khmer ASR corpus exists; fine-tuned
   Whisper reaches ≈8% CER; an open Khmer TTS recipe + Piper runtime exist. Voice
   moves from "research program" to **gated 1.x features**. Dialects remain out.
4. **MCP won the tool layer** (Linux Foundation, 2025-12; >10k servers). L3 adopts the
   protocol and invents only the leash ([ADR-0013](adr/0013-l3-bus-is-a-policy-leashed-mcp-host.md)).
5. **The window is open.** Recall shipped and is still distrusted; Copilot+ gates AI
   behind 40 TOPS + 16 GB. *The same memory, provably yours, on hardware you already
   own* — window ≈ 2026–2028. WWDC-2026 widened it: Apple based its next-gen models on
   Google's Gemini and moved Private Cloud Compute onto third-party infra — the
   on-device-privacy incumbent vacating the lane KOOMPI holds (§87/U7, verified 2026-06-13).

## 2 · Tiers (the floor is the product)

| Tier | Hardware | Experience |
|---|---|---|
| **T0** | 4 GB | Search & recall: FTS5/BM25 + sqlite-vec rerank; embedder quantized and loaded on demand. Local chat **off**; chat = explicit consented cloud or none (Reduced-local mode, [ADR-0001](adr/0001-degrade-local-never-silent-cloud.md)). |
| **T1** | 8 GB (the Floor, [ADR-0006](adr/0006-default-models-bge-m3-and-license-gate.md)) | + local chat, 1–3B Q4 (Khmer modest), grammar-constrained tools. |
| **T2** | 16 GB | + 8B chat (Sailor2-8B class), small multimodal, Partner sheets comfortable. |
| **T3** | NPU / dGPU | + OpenVINO/Hexagon offload via llama.cpp backends — GATED(G-NPU-1). |

RAM-crisis consequences, binding: weights preinstalled from `[koompi]`
([ADR-0014](adr/0014-weights-are-signed-packages-no-runtime-registries.md)); zram on by
default; the detected tier is printed at install and first boot; **no UI may promise
above its tier.**

## 3 · Capability gates registry

A gate names the unlock — usually external (a model, a corpus, a backend), sometimes a
named internal artifact (an eval harness, a founder decision) — and a measurable
threshold; the feature ships when the gate passes. **A post-v1 capability that waits on
an unlock and has no gate row is fiction by definition**; plain 1.x work waits on no
unlock and is sequenced by the roadmap's track order instead. A gate row needs an owner
and an eval artifact before the feature may appear in any public roadmap. Owners are
role-level (roadmap §10.1 convention) until a named human is confirmed; **UNASSIGNED ⚠
blocks public-roadmap listing.**

| Gate | Capability | Unlock | Threshold | Owner | Target |
|---|---|---|---|---|---|
| **G-KM-CHAT-1** | Per-tier Khmer chat pin | Sailor2 / SEA-LION v4 | KOOMPI-EVAL-KM chat suite thresholds + license CI pass | UNASSIGNED ⚠ | v1 (closes the ADR-0006 open item) |
| **G-KM-STT-1** | Khmer dictation | Whisper-km fine-tune on the 106 h corpus | CER ≤ 15% on KOOMPI-EVAL-KM-STT (classroom mic, formal register) | KOOMPI community/team (D-3 default) | 1.x |
| **G-KM-TTS-1** | One Khmer TTS voice | Piper/VITS + open recipe | Intelligibility MOS ≥ 4.0, panel n ≥ 30 | KOOMPI community/team (D-3 default) | 1.x |
| **G-EMB-2** | Embedder succession | SEA-LION-Embedding (2026-03) or later | ≥ +5% on KOOMPI-EVAL-RETRIEVAL **and** license gate **and** re-embed runbook executed in CI | UNASSIGNED ⚠ | 1.x |
| **G-NPU-1** | NPU tier detect/offload | llama.cpp OpenVINO / Hexagon backends | Stable on ≥ 2 devices KOOMPI owns | KOOMPI hardware | 1.x |
| **G-AGENT-1** | Bounded agent threads | Injection eval harness | Budgets + leash enforced; red-team pass on the lethal-trifecta scenarios (arch §9) | UNASSIGNED ⚠ | late 1.x |
| **G-A11Y-2** | Khmer screen reader assembly | AccessKit/Qt + Newton + G-KM-TTS-1 | Task-completion study with blind Khmer users | UNASSIGNED ⚠ (same gap as roadmap X-8) | 2.x |
| **G-HOME-1** | Home Node beta | Founder D-1 + E2EE sync | External audit of the sync path | founder (D-1) | 2.x |

## 4 · The register — Acts I–VIII (the buildable blueprint)

### Act I — Frame
| § | Surface | Stamp | Delta |
|---|---|---|---|
| 00 | What is KOOMPI OS? | **v1** | C-1: the "4 GB still gets a working AI" line → Reduced-local wording. |
| 84 | System Map | **RULE** | The consolidation ledger governs; new sections must reuse an engine or justify one. |
| 87 | The Near Future | **RULE** | Evidence register; re-run and re-date before stamps move (§8). |

### Act II — Foundation
| § | Surface | Stamp | Delta |
|---|---|---|---|
| 01 | Design System | **v1** | Color-as-contract is already CI-checkable; keep. |
| 02 | Shell Bar | **v1** | **One layout GA** (default). Taskbar/Dock variants = 1.x experiments; every feature × 3 layouts is a fork tax (UPSTREAM.md divergence budget). |

### Act III — Shell
| § | Surface | Stamp | Delta |
|---|---|---|---|
| 03 | Launcher | **v1** | The L1 demo surface: hybrid FTS5+vec results with "≈ semantic" provenance chips. |
| 04 | Notifications | **v1-lite** | Rule-based grouping v1; AI thread summaries 1.x on T1+. |
| 05 | Quick Settings | **v1** | — |
| 06 | OSD | **v1** | — |
| 07 | Workspace Overview | **v1** | Shell inherited; AI intent labels 1.x as *heuristics* (app class + title), no model required. |
| 08 | Widget Overlay | **v1** (existing) | Widget→app graduation 1.x; widgets stay views, never silos. |
| 09 | Cheatsheet | **v1** (inherited) | — |
| 15 | Session Screen | **v1** (inherited) | — |
| 34 | Window Management | **v1** deterministic | AI routing CUT from v1; 1.x = explainable heuristics with one-tap "never again". |
| 45 | File Manager | **ADOPT** | No first-party FM. Privacy state lives in KOOMPI surfaces (launcher, Partner, Index Status); host-FM emblem integration 1.x where cheap. |
| 46 | Clipboard | **1.x (early)** | Secret masking + retention scopes; small, self-contained, high-trust. |
| 82 | The Partner Window | **v1 = rail** | Per the browser blueprint's own v1 list. Sheets are T1+; Firefox stays the default browser on all tiers; C-9 fixes the blueprint's toolchain to ADR-0004. |
| 86 | Pocket & Tablet | **GATED(G-HOME-1)** | Pending founder D-1. The Home Node is the implementable form; a phone app program is not staffed before L1 ships. |
| 83 | The App Suite | **RULE + 1.x serial** | The build test is the rule. C-6: v1 ships shell surfaces + the Partner rail only; suite apps land one per release (Translate and the document Vault first candidates). |

### Act IV — AI Layer
| § | Surface | Stamp | Delta |
|---|---|---|---|
| 11 | Tool Approval | **v1** | Nonce-bound `Approve()`, capability tiers, bwrap sandbox, polkit escalation (arch §6). Grammar-constrained calls from day one (U1). DANGER class: no "always allow". |
| 12 | RAG Sources | **v1** | Token budget + one-click removal; retrieved chunks tagged untrusted. |
| 13 | Memory View | **v1** | Entries CRUD over the semantic store; honest-deletion copy (tombstone + VACUUM + CoW caveat, arch §5). |
| 14 | Daily Briefing | **1.x** (L4) | C-7: "0.8 s" → *ready when the lid opens* (precomputed on AC/idle). Headless = READ-only caps (arch §6). |
| 36 | AI Failure & Fixes | **v1-partial** | C-8: confidence % → grounding indicators (sources, similarity, recency). Undo journal scoped to KOOMPI tools v1. |
| 43 | Model Manager | **v1-lite** | Tier detect, signed weights, swap = unload/load (never "hot"). ADR-0014 store. NPU probing GATED(G-NPU-1). |

### Act V — Data
| § | Surface | Stamp | Delta |
|---|---|---|---|
| 26 | Index Status | **v1** | — |
| 27 | Privacy Dashboard | **v1** | Privacy Center Overview tab. |
| 28 | Egress Ledger | **v1-scoped** | C-5: v1 claim = *the AI plane is structurally incapable of unconsented egress* (systemd `IPAddressDeny` on contextd/assistantd; syncd sole egress) + hash-chained log of the two doors. Whole-system containment lands with P-2 (1.x); App Window mode stays "incomplete by construction" in UI copy. |
| 42 | App Permissions | **1.x** | Full matrix needs P-2; portal-level basics v1. |
| 85 | Web3 Native | **1.x staged** | Read-only (names, balances, provenance) first; signing ceremony 1.x, sentence-rendering **Selendra-only**; anchoring opt-in ([ADR-0009](adr/0009-selendra-anchoring-off-by-default.md)). Generic drainer protection CUT. |

### Act VI — System
| § | Surface | Stamp | Delta |
|---|---|---|---|
| 35 | First Boot | **v1** | Everything off by default; tier printed; "I don't know you yet." |
| 29 | Settings | **v1** | — |
| 30 | Factory Reset | **v1** | Gated on R-1/R-3 VM-verification (roadmap §5). Not a feature until restore is proven. |
| 31 | ~~Subsystem Modes~~ → Profiles | **1.x** | C-4: renamed — `CONTEXT.md` owns "Subsystem" (isolation). Two profiles first (Focus, Privacy); no latency promises. |
| 32 | Installer | **v1** | Close G1/G2/G3. C-10: 4 GB copy → Reduced-local honesty. |
| 33 | Khmer / i18n | **v1-partial** | I-1/2/3/5 ship together if resourced; I-4 (segmentation) with L1. Voice → GATED(G-KM-STT-1, G-KM-TTS-1). Dialect voice CUT (no corpus); register-correct *strings* yes, register-aware *generation* no. |
| 37 | Auth & Lock | **v1-reduced** | TPM2-sealed LUKS + fprintd where hardware exists. C-11: RGB liveness claims and duress mode CUT (RGB cams can't do liveness; decoy slots are forensically visible and legally hazardous). Liveness exists only behind IR-depth hardware detection. |
| 38 | Accessibility | **v1 gates** | CI = contrast + keyboard-nav. AccessKit roles 1.x as components are touched. Screen reader GATED(G-A11Y-2). "A11y as build gate" scoped to what tooling can actually check. |
| 39 | Updates | **v1** | Snapshot-first; **manual** snapshot boot via grub-btrfs at v1; automated health-gated rollback 1.x. Risk groups by repo origin, not hand labels. |
| 40 | Network | **1.x** | Trust postures via NM dispatcher + nftables zones; stricter-wins via Policy. |
| 41 | Backup & Restore | **1.x** | borg/restic wrapped; Shamir recovery. Duress decoys CUT. |
| 44 | Profiles & Sharing | **v1 invariants** | Per-user daemons/keys/index + LOCK floor are adjudicated (arch §10); management UI polish 1.x. |
| 47 | Wellbeing | **1.x** | Owns the focus score; local-only; off by default. |
| 48 | Device Continuity | **1.x** | KDE Connect as transport; Automerge capsules; Continue-or-Fork. Honest: processes don't teleport. |
| 49 | Error & Recovery | **v1-partial** | Restore entry points + calm-register copy v1; full reporter 1.x. |
| 50 | Software Center | **1.x-lite** | Privacy score from manifest/static analysis. ZK crowd flags CUT. |

### Act VII — UX Philosophy
| § | Surface | Stamp | Delta |
|---|---|---|---|
| 53 | Theme Engine | **v1** | Mostly inherited (Material You engine); the contrast hard-gate is the new code. |
| 54 | Motion Language | **v1 spec** | Reduced-motion as a peer set; CI-checkable durations. |
| 55 | Sound Design | **1.x** | Boot sound + ~5 pinpeat-derived earcons; record originals (license care). |

### Act VIII — Hardware & Platform
| § | Surface | Stamp | Delta |
|---|---|---|---|
| 51 | Display & Color | **v1 ICC** | colord-bound profiles; HDR deferred until the compositor path is stable. |
| 52 | Developer Mode | **1.x** | podman/distrobox presets + one-click revert. |
| 56 | Visual Physics | **v1 static** | Three static presets v1; thermal-auto degradation 1.x. |
| 57 | Gaming Mode | **1.x** | Adopt FeralInteractive gamemode + settings-delta journal; don't rewrite. |

## 5 · Acts IX–X — kernels only

The essays live in [`horizon.md`](horizon.md). Only the kernels below are engineering;
each is stamped there and cross-referenced here:

| § | Essay | The kernel that is engineering | Lands |
|---|---|---|---|
| 16 | Ambient Intelligence | Context Pulse widget over contextd events | 1.x |
| 17 | Memory Palace | Memory app Timeline view | 1.x–2.x |
| 19 | Proactive OS | L4 staged automations; never auto-send | 1.x |
| 20 | App-less Computing | Composer + MCP capability calls | with L3 |
| 21 | Khmer-Native AI | Eval-gated chat (G-KM-CHAT-1); register-correct strings | v1 strings |
| 22 | Data Sovereignty | Per-app revocation + local consent receipts (valuation CUT, C-12) | 1.x |
| 23 | Cognitive OS | Profiles presets (renamed §31) | 1.x |
| 24 | Lifetime OS | Lifeboat `legacy` preset | 1.x |
| 25 | Spatial Shell | — | HORIZON |
| 57a | The Thinking OS | The era-tagged store *is* the thread | v1 schema |
| 58/59 | Memory Architecture / Lifecycle | Schema + consolidation job (the daemon, not the neuroscience) | v1 / 1.x |
| 60/61 | Memory Blueprint / Impl. Stack | Rewritten to ADR-0004 reality (C-2, C-3) | v1 arch |
| 62 | Death & Estate | Lifeboat `legacy` + documented inheritance | 1.x |
| 63 | The OS That Raises You | Per-user policy LOCK floor | exists (arch §10) |
| 64 | Aging With Dignity | A11y scaling profiles | 2.x |
| 65 | Cognitive Sovereignty | Local usage stats (wellbeing) | 1.x |
| 66 | Past Self | Belief-diff view over memory history | 2.x+ |
| 67 | Hardware Succession | Restore-onto-new-machine CI test | 1.x |
| 68 | Format Archaeology | **RULE now**: open formats only (SQLite/JSON/Markdown/tar), documented schemas, export exercised in CI | now |
| 69 | Continuity Charter | Write the actual document | now |
| 70 | Refugee Mode | systemd-homed portable home + Lifeboat `refugee` preset | 1.x–2.x |
| 71 | Energy Sovereignty | **RULE**: AC/idle/thermal gating of background work (arch §11) | v1 |
| 72 | Repair Culture | Brand/hardware program | not OS |
| 73 | Ceremonial Forgetting | Honest deletion spec: tombstone + scheduled VACUUM + CoW caveat + O-1 at-rest | v1 copy + jobs |
| 74 | Model Succession | **RULE**: raw text canonical; vectors era-tagged, disposable; re-embed runbook (exercised by G-EMB-2) | v1 schema |
| 75 | Household Constitution | Policy floor file + cooling-off on amendments | 1.x (small) |
| 76 | Memory Etiquette | **RULE**: other people's content (messages, contacts) excluded from the index by default | v1 default |
| 77 | OS as Witness | C2PA-class capture provenance | 2.x watch |
| 78 | Village Commons | — | **CUT** from OS (possible future separate product) |
| 79 | Agent Diplomacy | — | **CUT** (no counterparties exist) |
| 80 | The Gardener | — | **CUT** (a self-modifying OS un-audits itself; anti-feature for a trust product) |
| 81 | The Exit Door | Lifeboat engine (v1, factory reset needs it) + `exit` preset | engine v1 / preset 1.x |

**The Lifeboat adjudication:** §30 snapshot, §24/§62 legacy, §70 refugee, §81 exit are
**one export engine with four presets** (System Map). The engine is v1 because reset
depends on it; presets land 1.x.

## 6 · Corrections register (brainstorm pages owing a rewrite)

These pages currently contradict decided architecture or physics. Until rewritten,
this register supersedes them.

| ID | Page | Wrong | Right |
|---|---|---|---|
| C-1 | §00 | "a 4 GB machine still gets a working AI" | 4 GB = search + recall; chat is consented cloud or none (arch §11) |
| C-2 | §61 | Zig daemons, resident Python AI layer, "koompi-vector (HNSW)", "boot 2.1 s" | Rust daemons (ADR-0004); sqlite-vec brute-force; no resident Python; no invented numbers |
| C-3 | §60 | Zig daemon + Python controller; "8.3 ms" framed as memory budget | Same toolchain fix; 8.3 ms is a *shell* frame budget; keep the 4-layer schema |
| C-4 | §31 | "Subsystem Modes" = personas | Rename to **Profiles**; `CONTEXT.md` owns "Subsystem" |
| C-5 | §28 | "every byte that ever left … read from the kernel" | v1 = the two consented doors, kernel-enforced on the AI plane; P-2 extends per-app (1.x) |
| C-6 | §83 | Naga Eight ship in v1 | v1 = shell surfaces + Partner rail; suite one-per-release behind the build test |
| C-7 | §14 | "prepared locally in 0.8 s" | "ready when the lid opens" — precomputed on AC/idle |
| C-8 | §36 | confidence-% meters | grounding indicators (sources, similarity, recency); local logprobs are uncalibrated |
| C-9 | `koompi-browser.md` §5.1 | Zig `koompi-webd`; "Python (in assistantd)" | Rust per ADR-0004 |
| C-10 | §32 | "degrades to 4 GB without refusing" | Degrades to Reduced-local *honestly*; chat refused-with-consent-option below T1 |
| C-11 | §37 | liveness biometrics; duress decoys | fprintd + TPM2; RGB liveness and duress CUT; liveness only where IR-depth hardware proves it |
| C-12 | §22 | "see what your data is worth" | CUT valuation; keep revocation + local receipts |
| C-13 | 20 sections (§26, §39, §40, §41, §43, §44, §48, §49, §57, §57a, §58, §59, §66, §68, §71, §76, §78, §80, §81, §82) | reference `koompi-agent-memd` | the memory engine lives inside `koompi-assistantd` (no separate daemon) — renamed 2026-06-12; §36/§37/§60/§61/§83 were already correct |
| C-14 | §35, §43, §44, §46, §48, §49, §52, §54, §56 | mockups name "Llama 3.1" (plus 3.2/70B strays) | Llama-MAU fails the license gate (ADR-0006) — replaced with the eval-pinned tier model (Sailor2-class) 2026-06-12; prose references model-agnostic per §74 |
| C-15 | §41 | "duress PIN" backup decoys | same refusal as C-11 — cut on the same grounds |
| C-16 | `global-menu-arch.html` | specs the global-menu *session daemon* in Zig | daemons are Rust (ADR-0004 — zbus is the whole point for a DBusMenu consumer); ported to Rust + zbus 2026-06-12 (doc v1.1, wire format unchanged) |

**Status 2026-06-12: C-1 … C-16 are applied to the pages.** The 2026-06-12 audit
closed the stragglers: the C-9 remainder (`koompi-browser.md` §1 process model still
said Zig), the C-3 remainder (§60's "Zig-owned" store annotation; Zig paths/syntax in
§26/§80 ported to Rust), the three pages C-13's list had missed (§41, §57, §82) plus
`agent-memd` references in `koompi-browser.md` §2.1 and `koompi-browser-prompt.md`,
the two pages C-14's list had missed (§49, §56), the Document Map cards that still
sold cut features (§33 dialect voice, §41 duress decoys, §50 ZK crowd flags, §43
"hot-swap"), and C-16 (found during repair verification).

**Status 2026-06-13 (v1.2): the section *bodies* the v1.1 audit missed are now swept
and grep-verified.** The v1.1 "applied everywhere" claim was card-deep, not
section-deep — a full-corpus grep found the stragglers that survived in the actual
pages: §02/§36 still named Llama (outside C-14's nine-page list); §43 still said
"hot-swap" and named `nomic-embed`; §45/§58/§59 named `nomic-embed` /
`bge-small-en-v1.5` (English-only, against the ADR-0006 **BGE-M3** pin); §46 had a
"Zig watcher" (ADR-0004 → Rust); §36's bundle showed `stated_conf` (its own thesis
bars it → `grounding`); §33 still sold dialect voice; §50 still sold ZK crowd flags;
and **§44/§70 still shipped the duress-decoy feature §41/C-11/C-15 had cut** — the
safety-critical one. All applied. Two reconciliations ride with it: **§44/§83 → the
global-individual wedge** (founder call; prd §2/arch §10 — Khmer/Cambodia is a served
feature, not the identity or moat); and **WWDC-2026 Apple→Gemini** evidence folded
into §87/U7 (per §8). **Lesson:** a CI grep-gate (`llama-`, `\bZig\b` outside
installer/restore, `duress|decoy`, `hot.?swap`, `ZK.?(crowd|aggregat)`,
`nomic-embed|bge-small`, `agent-memd`) makes "swept everywhere" verifiable, not asserted.

## 7 · Open founder decisions

| ID | Decision | What it changes | Default if undecided |
|---|---|---|---|
| **D-1** | The **Home Node** as a product line (one 16 GB box per household; thin clients) | §86 stamp; G-HOME-1; the pocket/tablet story; RAM-crisis hardware economics | Prototype on an N100-class mini-PC; no commitment |
| **D-2** | **SKU posture** during the RAM crisis | New-hardware floor (8 GB honest vs 16 GB premium); install-tier messaging | 8 GB floor, honestly tiered |
| **D-3** | **Khmer speech strategy** — fund the Cambodian speech-OSS community vs build in-house | G-KM-STT-1 / G-KM-TTS-1 ownership; community relations | Fund the community |

## 8 · Change discipline

- This register changes only by PR carrying either **(a)** new dated evidence (a
  re-run of the §87 review) or **(b)** a gate passing with its eval artifact attached.
- Stamps never loosen silently; a CUT reopens only against new evidence.
- The five fires precede everything in §4: **G1/G2/G3** (it must install itself),
  **R-legs VM-verified** (restore must be real), **`policies.ai` default flip**,
  **`set_shell_config` gated**, **the `localhost` check fixed** (roadmap §1, arch §2).
