# The Partner Window — Technical Blueprint

Status: brainstorm-grade architecture, v0.3 · Generated from `koompi-browser-prompt.md`
Supersedes the v0.1 "KOOMPI Browser" blueprint: the browser and the AI Sidebar are one
surface now — a conversation that absorbed the browser. Frame test for every decision:
more capable without taking data · privacy posture in pixels · runs on a UHD 620 / 4–8 GB
floor · still coherent in year 30.

---

## 1 · OS-Native Intelligence: One Brain, Not Two

### 1.1 The surface ships no LLM

Every generative task goes to `koompi-assistantd` (L2) over the local Unix socket. The
measured case for an in-process 1.5–3B SLM evaporates on inspection: socket round-trip
is sub-millisecond, token generation dominates end-to-end latency by 3–4 orders of
magnitude, and a second model stack means a second RAM resident (fatal on the 4 GB
floor), a second update channel, and a second thing the Model Manager can't see. The
Partner Window is a *face*; the brain stays in the OS.

What does run in-process: **tiny ONNX classifiers** (~5–20 MB, CPU, <50 ms), registered
as a Model Manager tier so they update and roll back like every other model:

| classifier | job | budget |
|---|---|---|
| `intent-router` | composer input → URL / search / question / command | <10 ms/keystroke |
| `content-class` | page category (banking, health, docs, shop) → consent defaults | <30 ms/load |
| `instr-taint` | flags imperative-toward-agent spans in page text (§3.4) | <50 ms/page |

**Process model.** QML/Quickshell chrome — the stream, composer, thread rail (trusted
layer, hot-reload, shell tokens) · QtWebEngine renderer processes for sheets (Chromium
sandbox intact) · `koompi-webd`, a Rust daemon (ADR-0004) owning thread state, the capture
pipeline, capsules, and the CLI · Rust crates (shared with the OS) for egress hooks, the
semantic-selector engine, and the credential-broker client.

### 1.2 Hybrid routing under ADR-0001

The surface never routes to a cloud model itself. It hands tasks to assistantd with
metadata (task class, content size, thread id); assistantd's router decides local tier
vs **KOOMPI.Cloud** (self-hosted or operated, zero-knowledge). A cloud decision surfaces
as the standard **amber consent moment** in the stream, naming exactly what leaves (the
cleaned article AST, never raw pages or cookies), with an Egress Ledger receipt. Below
the floor, the partner degrades local and says so. Silent fallback is a contract
violation, not a tuning knob.

Latency budgets the stream is designed around (UHD 620 floor):

| task | path | target |
|---|---|---|
| composer intent | in-process classifier | <10 ms |
| reader re-render (cached IR) | webd cache | <50 ms |
| reader re-render (cold) | assistantd local 3B | 2–6 s, streamed into the card |
| research thread step | assistantd local 8B | 10–40 s, breathing in-stream |
| anything cloud | egress + consent card | never silent |

### 1.3 The stream is the history

There is **no browser history database** — scrolling back through a thread *is* your
memory of the web. Navigation produces capture events through one pipeline into the OS
stores:

```
navigation → readability extract (local, Rust)
          → consent gate (Policy Engine: per-site scope)
          → contextd ingest (chunk + embed → the one index)
          → assistantd episodic event (visit record → the one memory)
```

- **Per-site scopes** (Policy Engine, clipboard-style): `metadata-only` (URL + title —
  the default), `full-content` (opt-in per site), `never` (auto-suggested when
  `content-class` says banking/health). The scope chip lives in the sheet's caption —
  posture in pixels.
- **Privacy states per entry** exactly as Files (§45): INDEXED · ENCRYPTED · SHARED ·
  LEAKED-ONCE.
- **Incognito is a private thread**: a no-write mode enforced at the pipeline entry
  *and* an ephemeral renderer profile — not a UI flag over a warm cache.
- **Forgetting**: browsing memories are ordinary memories — Suppress / Seal / Destroy
  via Ceremonial Forgetting, blast radius shown (which notes cite the page).

## 2 · The Partner Window: Conversation-First Anatomy

### 2.1 The composer — input at the bottom, and nothing above

One input for the entire surface, in the thumb/home-row zone. The `intent-router`
classifies per keystroke: a URL opens a sheet immediately (muscle memory preserved at
full speed), a question goes to the session, a command becomes a capability call. Mic
and camera sit beside the keyboard as equal inputs — composer attachments are the
desktop twin of the mobile share-sheet. There is no address bar; **a URL is one kind of
sentence**.

### 2.2 The stream — trusted chrome where everything lives

Messages, answers-with-sources, **page cards**, re-rendered tables, download receipts,
agent step-ledgers (breathing, ✓/●/○), and **consent cards** — *talk when needed, act
once agreed*: every consequential action returns to the stream as a previewed,
editable, refusable card with an undo receipt. The signing ceremony and all approvals
render **only** here. Stream discipline: link-following inside a sheet stays in the
sheet's quiet page-stack; the stream records intent and milestones, never every click.

### 2.3 Sheets — the web, full-bleed and contained

A tapped page card expands to a sheet: the webview with a *caption, not a cockpit*
(origin · privacy scope · provenance toggle <kbd>O</kbd>). Re-rendering pipeline:

1. **Snapshot**: webd serializes a cleaned article AST (Readability-class extraction in
   Rust over DOM + accessibility tree). Raw HTML never reaches a model.
2. **IR**: assistantd produces layout IR — markdown blocks, table specs — where every
   block carries `sourceNodeRef`; synthesized cells carry all contributing refs.
3. **Render**: QML reader in shell tokens; hover highlights the original DOM region;
   <kbd>O</kbd> toggles the untouched page.
4. **Marking**: §77 provenance chip (**AI-assisted re-render**); *recorded* vs
   *inferred* distinguished per cell.
5. **Cache**: IR keyed by content hash — instant, offline-capable re-renders.

On phones a dismissed sheet **minimizes to a mini-player chip** above the composer —
the web as something you hold while talking. On tablets the default is **split**:
stream | sheet, the posture the device is for. Two sheets can tile inside a thread.

### 2.4 Threads — tabs and canvases, retired together

A thread = task container `{pages, files, terminal panes, agent sub-threads, drafts}`
with one busd identity, **its own cookie jar** (different threads are different people
to the web), its own page stack, a Hyprland workspace mapping, and a Context Capsule
serialization for §48 handoff (Continue / Fork on arrival). Frozen pages are IR
snapshots + URL (~100 KB), not renderer processes — 20 "open" pages stay viable on 4 GB.

### 2.5 The mounts — one component, four places

| mount | summon | form |
|---|---|---|
| **Rail** | Super+A | slim overlay over any app — instant, resident |
| **Window** | launcher / workspace | full surface: thread rail + stream + sheets |
| **Embedded** | tiling | the stream docked beside a terminal or editor |
| **Pocket** | phone/tablet | thin partner over a thick home (§2.6) |

Closing a window never kills the partner — the surface is shell-level, not an app.

### 2.6 Pocket: thin partner, thick home

Your house is your cloud. Three tiers, honestly degraded, every handoff announced:
**mesh** to your own desktop (~8 ms, full brain) → **tunnel home** (WireGuard, 40–120 ms,
same brain) → **pocket brain** (on-device 3B, ~9 tok/s, encrypted 30-day memory cache,
StrongBox-sealed, remotely revocable from the Vault). Mobile specifics: biometric
**hold-to-approve** on commit-class consent cards (consent = identity, one motion); lock
screens show *that* a consent waits, never the Approve button; camera as composer input
(on-device Khmer OCR-translate); earbuds mode with register-aware TTS. Honest limit: a
companion app on Android cannot hardware-guarantee the layer rule (§3.3) — that arrives
only with a KOOMPI-controlled mobile build.

### 2.7 Khmer-first web

ICU dictionary break-iterator for selection and find-in-page on spaceless Khmer;
Khmer/Arabic numeral folding; km collation in thread search; register-aware local
translate as a stream card; Khmer TTS read-aloud. First-class from minute zero.

## 3 · The Action Layer: Agency with a Leash

### 3.1 Semantic web automation

Agents act on the **accessibility tree + semantic DOM**, never CSS selectors. A target
is a semantic selector `(role, accessible-name≈, landmark path, text-context
embedding)`; plans compile to a step IR and **every step re-grounds at execution** —
below confidence threshold, the plan pauses and asks via a consent card instead of
guessing. Dry-run is the default first run (targets highlighted in the sheet, nothing
acts). Replay journals record `(selector, node fingerprint, action, result hash)` for
deterministic replay and undo. Automations are busd capabilities — `web.extract`,
`web.fill`, `web.download`, `web.submit` — callable by the assistant or any consented
app.

### 3.2 Consent that scales

Policy Engine precedence `floor > constitution > app > session`:

| class | examples | default |
|---|---|---|
| read | fetch, extract | allowed within site scope |
| interact | fill, click, paginate | session policy via consent card |
| commit | submit, post, purchase | **always asks** — constitution may narrow, never waive money |
| credential | login | broker only, never scriptable |

Every commit action produces an undo receipt and a Ledger entry against its rule ID.

### 3.3 Containment — and the layer rule

| trust | engine | use |
|---|---|---|
| normal sheets | QtWebEngine renderer sandbox | default |
| autonomous scraping / unknown | headless engine in **bwrap + netns** | agent threads |
| hostile / unvetted | **Detonation Chamber** microVM; only screenshots + AX-tree exit | "open this sketchy link" |

**The hard rule that makes the fusion safe: a page renders into a sheet, never into the
stream.** The stream is QML, drawn by the shell; hostile content physically cannot
imitate a consent card or draw an Approve button. Logins go through the host-side
credential Broker (ADR-0012) — the sheet receives a short-TTL session scoped to the
thread's cookie jar; passwords never exist in page or agent context.

### 3.4 Prompt injection, concretely

1. **Channel separation** — page content reaches agents as typed, quoted data blocks;
   the instruction channel is OS-only.
2. **Taint pass** — `instr-taint` strips and quarantines imperative-toward-agent spans
   before content reaches assistantd.
3. **Violation surface** — a red stream card: *"This page attempted to instruct your
   agent"* — logged, teachable.
4. **Capability ceiling** — page-derived plans can never trigger commit or credential
   actions during autonomous runs; a human re-confirms at the boundary regardless of
   standing policy.
5. The honest limit: injection is not solved in the adversarial limit (§5.3). Ceilings
   bound the blast radius; they do not pretend immunity.

### 3.5 Web3-native: the brokered wallet

No injected wallet, ever. Sheets get a provider shim (EIP-1193 for EVM dApps; a
Substrate-compatible signer for Selendra-class chains) proxying every request to
`koompi-vault` via `web3.*` capabilities. Every signature is the **signing ceremony as
a stream consent card**: local simulation rendered as a sentence ("send 25 SEL to
vathna.sel · approvals granted: none"), unlimited-allowance and `setApprovalForAll`
drainer patterns refused by default, Constitution spend limits enforced, biometric
hold-to-approve on pocket mounts. Multichain by broker, not extension zoo: Selendra is
home; EVM, Bitcoin, and other networks ride the same Vault custody. **Per-thread wallet
identity**: each thread exposes a derived account — the cookie-jar model extended to
value. Name resolution (`.sel`, ENS) cached locally, OS-wide. Chain RPC is ordinary
egress with Ledger receipts.

## 4 · Hardware-Efficient & Builder-Centric Innovations

1. **Pipe the web** — `koompi web page --md | jq …`: the active sheet (or any URL
   through the same consent stack) as markdown/JSON/AX-tree on stdout; scripts inherit
   the user's scopes and ledger.
2. **pacman-aware documentation** — install instructions detected in sheets; a stream
   card offers the real signed package and **diffs `curl | bash` scripts against the
   packaged version**. Kills Linux onboarding's most dangerous habit.
3. **Classroom capsules** — `koompi web capsule <site|list>` builds offline archives
   (WARC + IR cache) served over LAN/mesh; a lab with no internet still has the web
   that matters; tablet threads consume them natively (§2.6).
4. **Khmer-first everything** (§2.7) — the features no Valley browser will prioritize,
   default here.
5. **P2P/IPFS as first-class protocols** — `ipfs://` via a local gateway (optional, off
   by default per egress posture); opt-in Selendra provenance chips on content
   (ADR-0009: roots only).
6. **Energy-honest tiers** — IR caching and re-indexing defer to AC/solar surplus;
   thread hibernation budgets follow §56's GPU tiers; on battery the partner states
   what it deferred.
7. **Per-thread identity everywhere** — cookie jars, derived wallet accounts, and
   network posture binding ("the travel thread only exists over VPN") in one container
   model.

## 5 · Implementation Stack & v1 Scope

### 5.1 Engine and layers (ADR-0004 discipline)

**Engine: QtWebEngine (Chromium) for v1**, behind a strict **engine isolation
boundary** (`navigate, snapshot-AST, AX-tree, exec-step, jar-control`) — Chromium's
sandbox and codec maturity without a 30M-LOC fork treadmill, no Google service keys,
native QML embedding for the sheet/stream composite. Servo (Rust, Linux Foundation) is
tracked as the 2030s candidate behind the same boundary.

| layer | language | components |
|---|---|---|
| stream / composer / reader | QML/Quickshell | trusted chrome, hot-reload, shell tokens |
| session daemon | Rust (ADR-0004) | `koompi-webd`: threads, capture, capsules, CLI |
| security surfaces | Rust | egress hooks, broker client, semantic selectors, taint runtime |
| AI tools | Rust (in assistantd) | research / summarize / compare as busd capabilities (MCP, ADR-0013) |

**Privacy by topology**: sheets reach the network only through the OS egress gate
(per-thread cgroup rules); the AI tool layer has no network socket at all. Ledger
pragmatics: per-site aggregated receipts with anomaly surfacing (new destination or
category → full detail), paranoid mode for full per-request logging.

### 5.2 v1 (Naga) vs 1.x — capability-gated, real for daily use on day one

**v1**: QtWebEngine sheets inside the QML stream · named threads with per-thread jars ·
the composer with intent routing · reader re-render with provenance + <kbd>O</kbd> ·
contextd ingestion with per-site scopes + private threads · three automations through
consent cards (download+verify, form-fill, page→Notes) · pacman card · Khmer
find/translate · read-only Web3 (names, balances, provenance verify) · the rail and
window mounts.

**1.x**: agent threads with budgets · capsule handoff + the pocket mount (Connect grows
into it) · headless bwrap scraping tier + Detonation Chamber · `koompi web` CLI ·
classroom capsules · IPFS · the dApp provider + signing ceremony + agent commerce ·
energy tiers · Servo experiments.

### 5.3 The three hardest open problems — stated honestly

1. **The Chromium treadmill vs the 50-year horizon.** Weekly upstream security churn is
   a structural dependency on Google's roadmap. *Bet*: the engine isolation boundary +
   Servo optionality + funding upstream Qt WebEngine work — and saying in the
   Continuity Charter that engine sovereignty is partial for the next decade.
2. **Prompt injection in the adversarial limit.** Channel separation and taint passes
   raise the bar, not close the theory gap. *Bet*: capability ceilings + human gates on
   commit/credential classes — deliberately trading autonomy for bounded blast radius.
3. **Stream discipline at web speed.** The fused surface lives or dies on editing: if
   every click becomes a card, the conversation drowns; if too little is recorded, the
   stream stops being the history. *Bet*: sheets keep quiet page-stacks, the stream
   records intent and milestones, and the threshold is a tunable, user-visible policy —
   plus honest acknowledgment that this editorial line is a UX research problem the
   v1 will only approximate.
