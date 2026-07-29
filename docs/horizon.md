# KOOMPI OS — Horizon (the vision shelf)

**v1.1 · 2026-06-12 · status: explicitly non-roadmap**

This document holds the long-arc essays of the brainstorm — Acts IX and X, the
50–100-year material. It exists so the vision can stay ambitious **without leaking
into engineering**: nothing on this shelf may be cited as a commitment, scheduled,
or marketed. The binding register is [`blueprint.md`](blueprint.md); the dated
evidence is brainstorm **§87 The Near Future**.

## The shelf rule

Every essay here names its **kernel** — the one piece of it that is real engineering —
and where that kernel lives in the Blueprint. The essay keeps its full ambition; the
kernel keeps its feet. An essay **graduates** only by earning a row in the Blueprint's
capability-gates registry (`blueprint.md §3`): a named external unlock and a measurable
threshold. No gate, no graduation.

## The shelf

| § | Essay | What it dreams | The kernel (engineering) | Kernel lands |
|---|---|---|---|---|
| 16 | Ambient Intelligence | The OS senses much, shows everything, interrupts almost never | Context Pulse widget over contextd events | 1.x |
| 17 | Memory Palace | Query your life by meaning; tombstones prove deletion | Memory app Timeline view; honest-deletion spec | 1.x–2.x |
| 19 | Proactive OS | Prepares freely, proposes visibly, never sends unasked | L4 timers → headless READ-only runs | 1.x |
| 20 | App-less Computing | Intent assembles capabilities | Composer + MCP capability calls (ADR-0013) | with L3 |
| 21 | Khmer-Native AI | Reasons in Khmer — registers, honorifics, idiom | Eval-gated Khmer chat (G-KM-CHAT-1); register-correct strings | v1 strings |
| 22 | Data Sovereignty | Every flow visible and revocable; priced by no one | Per-app revocation + local consent receipts (valuation CUT, C-12) | 1.x |
| 23 | Cognitive OS | The shell reshapes to your mental state | Profiles presets (renamed §31) | 1.x |
| 24 | Lifetime OS | Eras, reflections, ceremonies across 50 years | Lifeboat `legacy` preset | 1.x |
| 25 | Spatial Shell | Workspaces as rooms; AI as presence | — | stays here |
| 57a | The Thinking OS | A 52-year continuous thread | The era-tagged store *is* the thread | v1 schema |
| 58/59 | Memory Architecture / Lifecycle | Neuromorphic layers; sleep consolidation | Schema + consolidation batch job | v1 / 1.x |
| 60/61 | Memory Blueprint / Impl. Stack | The executable spec of a mind that is yours | Rewritten to ADR-0004 reality (C-2, C-3): the schema + the wiring | v1 arch |
| 62 | Death & Digital Estate | Wills per memory-domain; consultable, never impersonated | Lifeboat `legacy` + documented inheritance | 1.x |
| 63 | The OS That Raises You | Autonomy grows with the child | Per-user policy LOCK floor | exists |
| 64 | Aging With Dignity | Silent adaptation; assist always, diagnose never | A11y scaling profiles | 2.x |
| 65 | Cognitive Sovereignty | The dependence dial | Local usage stats (wellbeing) | 1.x |
| 66 | Past Self | Belief-diffs, letters to your future | Diff view over memory history | 2.x+ |
| 67 | Hardware Succession | Machines retire with honor | Restore-onto-new-machine CI test | 1.x |
| 68 | Format Archaeology | Data outlives every program | **RULE now** — open formats, schemas documented, export in CI | now |
| 69 | Continuity Charter | The OS outlives the company | Write the charter document | now |
| 70 | Refugee Mode | A life on one microSD + a passphrase | systemd-homed portable home + Lifeboat `refugee` | 1.x–2.x |
| 71 | Energy Sovereignty | The OS schedules its metabolism around solar | **RULE** — AC/idle/thermal gating (exists, arch §11) | v1 |
| 72 | Repair Culture | A 20-year machine is a badge | Brand/hardware program | not OS |
| 73 | Ceremonial Forgetting | Suppress / Seal / Destroy | Honest deletion: tombstone + VACUUM + CoW caveat + at-rest | v1 |
| 74 | Model Succession | The soul is data; weights are replaceable | **RULE** — raw text canonical, era-tagged vectors, re-embed runbook (G-EMB-2) | v1 schema |
| 75 | Household Constitution | Approve policies, not invocations | Policy floor file + amendment cooling-off | 1.x |
| 76 | Memory Etiquette | The first OS with manners | **RULE** — others' content excluded from index by default | v1 default |
| 77 | OS as Witness | Provenance against the deepfake century | C2PA-class capture provenance | 2.x watch |
| 81 | The Exit Door | Full-fidelity leave | Lifeboat engine (v1) + `exit` preset | engine v1 / preset 1.x |

## Cut from the shelf entirely

Recorded so they are not re-litigated without new evidence (`blueprint.md §8`):

- **§78 Village Commons** — a different product, not an OS layer. Revisit post-1.x as
  a standalone app if the community asks for it.
- **§79 Agent Diplomacy** — no counterparties, no standards, nothing to build against.
- **§80 The Gardener** — a self-modifying OS un-audits itself. For a product whose
  thesis is *trust through verifiability*, this is an anti-feature, snapshot guards
  or not.

And the standing refusals that no amount of horizon-thinking re-opens without data:
open-ended autonomous agents on consumer hardware; browser-engine sovereignty
(Servo stays a 2030s watch item); Khmer dialect voice without a corpus; liveness
claims on RGB cameras; ZK crowd flags; data-valuation theater; any plan assuming
cheap RAM before 2028.

## Why keep a shelf at all

Because the essays do real work: they set the *direction* the kernels walk in
(forgetting-as-ceremony shaped the deletion spec; format archaeology became a CI
rule; the exit door became one export engine). The shelf is where ambition waits,
in writing, for its evidence to arrive — and §87 is how the evidence gets measured.
