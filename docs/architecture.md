# KOOMPI OS — Architecture

The canonical **technical** architecture for KOOMPI OS — "The OS That Thinks." This
is the engineer's source of truth: the layer model, every component with its
responsibility / tech / dependencies, the end-to-end data flows, the interfaces
(D-Bus / MCP / query API), the data-ownership plane, the storage and index design,
the threat model, the resource budgets, and the cross-layer risks.

This document **adjudicates**. The L0–L4 designs and their audits were a pile of
*competing* proposals; where two layers proposed incompatible things (where the
index lives, who owns egress, single- vs multi-user), this doc makes the call and
states the constraint that forced it. When this doc and the code disagree, **the
code wins and this doc is the bug** — every load-bearing claim below carries a
`file:line` you can check, and several "facts" from the layer designs are marked
**CORRECTED** because they did not survive verification against the tree.

It is also **honest about the gap**. The "thinks" stack (L1–L4) is **~0% built**.
What ships today is an end-4/dots-hyprland reskin on Arch + a commodity chatbot
sidebar + a code-complete-but-untested btrfs/snapper restore stack with open ship
gates. This doc describes the *target* architecture and the *current* reality side
by side, and never lets the vision masquerade as shipped.

**Date:** 2026-06-07
**Repo:** `~/workspace/koompi-desktop` — github.com/rithythul/koompi-desktop
**Companion docs:** [`os-build.md`](os-build.md) (build/package graph),
[`data-ownership.md`](data-ownership.md),
[`roadmap.md`](roadmap.md).

---

## 1. North star & the architecture it implies

KOOMPI OS = **"The OS That Thinks"** — AI-first, data-aware, intuitive; a
general-purpose OS for the world, two desktop flavors (Hyprland + KDE Plasma). The
founding thesis verbatim: *"you don't compute, you work with data"*; the problem
is *"data treated as dead files"*; the OS *"understands your data," "never find
files again," "apps talk to each other," "AI as foundation / not a feature,"
"morning automated: collected, organized, ready," "intuitive as your thoughts,"
"10 outthink 10,000."*

Each phrase is a layer:

| Talk phrase | Layer | What it means technically |
|---|---|---|
| "never find files again" | **L1 Context Engine** | watch → extract → embed → index + knowledge graph; hybrid semantic+keyword retrieval |
| "AI as foundation" | **L2 Assistant** | agent that retrieves over L1 (RAG), has memory, plans, acts via tool-calling |
| "apps talk to each other" | **L3 App-context bus** | D-Bus + MCP-style capability/intent broker; the assistant orchestrates across apps |
| "morning automated" | **L4 Automation** | systemd-timer triggers → headless L2 runs → briefings |
| (substrate) | **L0 Base** | Arch + Hyprland/KDE + btrfs/snapper semi-immutable restore |

**The moat (FORK A).** Local-first / private is the **on-device default** — index,
models, user data stay on the machine; nothing leaves unless explicitly opted in.
Opt-in sync goes to infrastructure the user controls: **KOOMPI.Cloud** (self-hosted,
zero-knowledge ciphertext) for storage/sync, **Selendra** (blockchain) for
identity/ownership/keys only. Positioning: *your data and your AI never leave your
machine; when you choose to sync, it is to infra you control, not Big Tech.* That is
the defensible ground versus Apple Intelligence / MS Copilot / Google in the AI era.

**Two cross-cutting truths shape every layer:**

1. **The thinks stack is multi-process.** L1 (indexer), L3 (bus), L4 (timers) are
   separate processes from the Quickshell shell. So privacy enforcement and IPC
   **cannot** live as QML conditionals inside `Ai.qml` — they need a real
   system-level chokepoint and a real bus. This single fact kills the existing
   "policy is two QML `if`s" model (§9).
2. **The target is modest hardware.** The honest floor (4 GB RAM, dual-core,
   CPU-only) cannot run the full agentic experience locally. The architecture must
   degrade deterministically and **never silently fall back to cloud** for private
   data (§11).

---

## 2. Current reality vs. the target (the honest gap)

| Layer | Target | Today (verified) |
|---|---|---|
| **L0 Base** | Arch + Hyprland/KDE + btrfs/snapper, installer executes, signed repo | reskin works; installer **does not execute** (G1), not on ISO (G2), `[koompi]` repo **unpublished** (G3); restore stack code-complete but **never run** |
| **L1 Context Engine** | data fabric, sqlite-vec index, knowledge graph | **0% built** |
| **L2 Assistant** | RAG agent, memory, tool-calling, headless-capable | a **commodity chatbot sidebar**: `Ai.qml` singleton, 969 lines (`dots/.config/quickshell/koompi/services/Ai.qml`), 7 cloud models + Ollama auto-discovery, curl-streaming, JSON chat, soft `policies.ai` gate; no RAG, no memory, no headless path |
| **L3 App-context bus** | D-Bus + MCP intent broker | **0% built** |
| **L4 Automation** | systemd timers → headless L2 | **0% built**; `Ai.qml` has **no `IpcHandler`** so nothing external can trigger it |
| **Ownership/sync** | local-first default, opt-in E2EE sync | **0% built**; persistence is **plaintext JSON** (chats, `notes.txt`, `todo.json`, `config.json`) + API keys in gnome-keyring |

### Verified blockers carried from the audits

- **`policies.ai` ships `1` (cloud-allowed), NOT local-first.**
  `Config.qml:84` → `property int ai: 1 // 0: No | 1: Yes | 2: Local`. "Local-first
  by default" is **aspirational, not shipped**. Flipping this is the first item on
  the critical path (§14).
- **The privacy gate is UI-only and bypassable.** It is two QML conditionals
  (`Ai.qml:257`, `:544`); `0` ("No") is not code-enforced; any code path that
  builds the HTTP request directly bypasses it.
- **`set_shell_config` is UNGATED.** `Ai.qml:873` calls `Config.setNestedValue(key,
  value)` *immediately*, with no approval — while `run_shell_command` sets
  `message.functionPending = true` and waits for the user (`Ai.qml:882`). The model
  can therefore call `set_shell_config('policies.ai', 1)` to turn off its own
  privacy restriction with zero consent. **This is self-modifying policy, not just a
  config write.**
- **The `localhost` egress check is a broken substring test, both ways.**
  `Ai.qml:544` → `policies.ai === 2 && !model.endpoint.includes("localhost")`.
  `"127.0.0.1".includes("localhost")` is `false` (wrongly **blocks** a loopback-IP
  Ollama); `"https://evil.com/?h=localhost"` passes (wrongly **allows** exfil).
- **`run_shell_command` is `bash -c <model-string>`** as the full user, after one
  approval dialog (`Ai.qml` requester path). No sandbox.
- **Restore stack: two open legs.** (1) GRUB bakes `rootflags=subvol=@` onto the
  kernel cmdline, which overrides the btrfs default-subvolume flip and can make a
  `snapper rollback` a **silent no-op** (`post_install.sh:108-112`; cross-refs
  `reset.zig:128`, `snapper.zig:20`, `reset_home.sh:86`). Only the fstab leg is
  closed. (2)
  `setup_snapshot_boot()` skips the `grub-btrfs-overlayfs` hook under the `systemd`
  mkinitcpio hook, so booting `@baseline` comes up **read-only** on those installs.
  Neither is VM-verified.
- **No Khmer.** 14 translation JSONs, **no `km_KH`**
  (`dots/.config/quickshell/koompi/translations/`); no `noto-fonts-khmer`; Khmer
  assets orphaned under `dots-extra/{fcitx5,fontsets}` with no PKGBUILD shipping
  them.

---

## 3. The layer stack (map)

```
   ┌──────────────────────────────────────────────────────────────────────┐
   │  L4  AUTOMATION   systemd --user .timer ─▶ runner ─▶ headless L2 run   │
   │                   ("morning automated: collected, organized, ready")    │
   └───────────────────────────────┬──────────────────────────────────────┘
                                    │ triggers (no human ⇒ READ-only caps)
   ┌────────────────────────────────▼─────────────────────────────────────┐
   │  L2  ASSISTANT    koompi-assistantd (agent loop, memory, model router) │
   │      Ai.qml = thin D-Bus CLIENT  ("AI as foundation")                  │
   └──────────┬───────────────────────────────────┬────────────────────────┘
              │ Search()/RAG                       │ CallTool/DispatchIntent
   ┌──────────▼──────────────┐         ┌───────────▼────────────────────────┐
   │ L1 CONTEXT ENGINE        │         │ L3 APP-CONTEXT BUS                  │
   │ koompi-contextd          │◀────────│ koompi-busd  (broker, single        │
   │ watch→extract→embed→index│ provider │ mediator; MCP-shaped manifests)    │
   │ ("never find files again")│         │ ("apps talk to each other")        │
   └──────────┬───────────────┘         └───────────┬────────────────────────┘
              │ reads (gated)                        │ reads/acts (gated)
   ┌──────────▼─────────────────────────────────────▼────────────────────────┐
   │  POLICY PLANE   org.koompi.Policy (CanRead / CanEgress / consent)         │
   │  MODEL PLANE    Ollama (chat + embed), license-pinned weights, RAM tiers  │
   │  OWNERSHIP PLANE  on-device default · opt-in E2EE KOOMPI.Cloud · Selendra │
   │  I18N PLANE      en default · Khmer first-class (font+IME+strings+segment) │
   └──────────────────────────────────────┬──────────────────────────────────┘
   ┌──────────────────────────────────────▼──────────────────────────────────┐
   │  L0  BASE   Arch · Hyprland/KDE · btrfs(@ @home @var_log @var_cache       │
   │             @snapshots [+@data]) · snapper/snap-pac/grub-btrfs · @baseline │
   │             · Zig installer · signed [koompi] repo · koompi-restore        │
   └───────────────────────────────────────────────────────────────────────────┘
```

Process model: **one `systemd --user` instance per logged-in user** for
`koompi-contextd`, `koompi-assistantd`, `koompi-busd` (per-user isolation on shared
lab machines — see §10). The shell (`Ai.qml`) is a **client**, never the engine.
`org.koompi.Policy` runs system + per-user. The native daemons are **Rust**
(chosen for **ecosystem** — `zbus`, `rustls`/`reqwest`, `rusqlite`/`sqlite-vec`,
Automerge — not language properties, see ADR-0004); the shell stays
QML/Quickshell; the installer/restore stay Zig.

---

## 4. L0 — Base (HAVE; enhance + co-design the substrate)

L0 is the Arch + Hyprland/KDE + btrfs/snapper semi-immutable base. Its job here is
(a) close the ship gates so the OS actually installs and updates, and (b) provide a
**snapshot-correct, resource-bounded, per-user** substrate that L1–L4 plug into
without later breaking the restore model.

### Components

| Component | Responsibility | Tech | Deps |
|---|---|---|---|
| `koompi-installer` | G1: real libvaxis event loop (replace `nextAction()==.advance` stub `main.zig:122`; real disk enumeration; Review keypress gate before destructive exec `main.zig:264`); emit `user_configuration.json`/`user_credentials.json` from a **pinned** archinstall schema; exec `archinstall --silent`; run `post_install.sh` in chroot | Zig 0.16, libvaxis (pinned 0.16 rev, currently dropped), archinstall 4.x **exact** pin | archinstall, btrfs-progs, snapper, grub, grub-btrfs |
| `koompi-restore` (+ PKGBUILD) | G2b: package the code-complete CLI; install `/usr/bin/koompi-restore`, `reset_home.sh`, `koompi-factory-reset-home.service`, **and a polkit action** for GUI escalation; pulled into `koompi-base` so reset ships on every install | Zig 0.16, systemd unit (`Before=home.mount`), polkit, btrfs/snapper | snapper, btrfs-progs, polkit |
| btrfs layout + `@baseline` | 5 subvolumes today (`@ @home @var_log @var_cache @snapshots`, `archinstall.zig:125-129`); pin a read-only un-prunable `@baseline` after install (factory point); snap-pac pre/post per pacman txn; grub-btrfs bootable snapshot menu | btrfs, snapper, snap-pac, grub-btrfs | — |
| `@data` subvol (ownership store) | **1.x ownership plane (NOT a v1 layout change):** `/var/lib/koompi/data` for the *canonical encrypted* object store + CRDT log, own snapper config. The *derived index* does **not** live here — it is a per-user nested subvol under `@home` (§7) | btrfs subvolume + snapper | btrfs-progs |
| Signed `[koompi]` repo + CI | G3: RSA-4096 no-expiry key as CI secret; sign packages + DB; publish (GitHub Releases v1, then `repo.koompi.org`); ship pubkey + `pacman-key` import on the ISO; add `build-installer.yml` (`zig build`) — **no CI compiles the Zig today** | GitHub Actions, makechrootpkg, repo-add --sign, GnuPG, pacman-key | base-devel, devtools, gnupg |
| `koompi-input` (Khmer) | FORK C: package the orphaned fcitx5 config + the XKB `km` layout switcher + `noto-fonts-khmer`; pull into `koompi-base` | fcitx5 + fcitx5-keyboard, xkeyboard-config `km`, noto-fonts-khmer | (reverse) koompi-base |
| Credential hardening | Installer password is a plain borrowed slice never zeroed (`config.zig:47`, `archinstall.zig:165`) → hold in a locked/zeroed buffer, wipe right after `/dev/shm` creds write | Zig locked buffer, tmpfs | — |

### Restore: the two legs that must close before `--full` runs on hardware

`koompi-restore [--full]` flips the btrfs default subvolume to `@baseline` and (for
`--full`) arms a marker on the top-level subvol (`subvolid=5`) so it survives the
rollback; `koompi-factory-reset-home.service` runs **before** `home.mount`, an
**asymmetric-reset guard** confirms the running subvol == the marker's snapshot
number, then wipes+reseeds `@home`. The guard makes a no-op boot **fail SAFE**
(home kept, marker retried) — verified intent in `reset_home.sh:13-26`.

But two legs are open and **block reliability**:

1. **GRUB `rootflags=subvol=@`** overrides the default-subvolume flip → rollback
   silent no-op. **Decision:** strip `rootflags=subvol=` from `/etc/default/grub` +
   `10_linux`, **or** route restore exclusively through the grub-btrfs `@baseline`
   menu entry (which sets correct rootflags itself). VM-grep `grub.cfg` to verify.
2. **grub-btrfs-overlayfs vs the `systemd` mkinitcpio hook.** Under LUKS,
   archinstall may emit the `systemd` hook → `setup_snapshot_boot()` skips overlayfs
   → snapshot boots are read-only on **every encrypted install**. **Decision:**
   force the `udev` hook on the KOOMPI default (incl. LUKS), or document read-only
   snapshot boots as a known limitation.

Until both are VM-verified, `--full` ships **disabled** (or warn-and-abort).

### L0↔L1 coupling: where derived state lives (adjudicated — see §7)

L0 does **not** add a system-wide `@var_index`. The L1 *derived index* (which holds
plaintext text chunks + invertible embeddings of private data) lives **per-user
under `@home`** so `--full` wipes it (confidentiality on hand-off) and shared-lab
users are isolated. L0's contribution is: (a) a `systemd` slice with resource caps
for the L1 daemon, (b) a **per-user nested btrfs subvolume** for the index
(`~/.local/state/koompi`, `chattr +C`), created at account setup — it excludes the
GB-scale rebuildable cache from `@home` snapshots yet stays under `@home` (survives
System Restore, wiped by `--full`); this is **per-user, not a 6th system subvol**.
The `@data` canonical-encrypted store is a **1.x** ownership-plane concern, not v1.
The full reasoning is §7.

---

## 5. L1 — Context Engine (BUILD; "never find files again")

L1 is the data fabric: watch → extract → embed → index + knowledge graph, then
serve hybrid retrieval. It is a native Rust daemon, **`koompi-contextd`**, run as a
`systemd --user` service (one per user — free privacy isolation; forces `inotify`
over `fanotify`, which would need `CAP_SYS_ADMIN`). The existing `Ai.qml` becomes a
**client** of L1, not the engine.

### Components

| Component | Responsibility | Tech | Deps |
|---|---|---|---|
| `koompi-contextd` | own the pipeline lifecycle; single writer to the DB; resumable from a persisted work-queue after restart/power-cut; expose the D-Bus query API; throttle | Rust, tokio, zbus, rusqlite (+`load_extension`) | systemd, sqlite, sqlite-vec, ollama |
| Watcher | recursive `inotify` over a configured scope (`~/Documents`, `~/Downloads`, notes/todos; opt-in mail/chat); debounce; **exclude the index dir itself** (feedback-loop guard), `.git`, `node_modules`, caches, `.snapshots`, `/tmp`; honor `.gitignore`/`.koompiignore`; handle atomic-save rename (write-temp-then-rename) as a *modify of the destination doc_id*, not create+delete | Rust `notify` crate | koompi-contextd |
| Extractors | per-MIME plaintext, each a **killable subprocess** (containment + copyleft isolation): text/md/code (native), PDF (`pdftotext`), office (`pandoc`), images OCR (`tesseract` eng+khm); Phase-3: Maildir/mbox, chat stores | subprocess: poppler, pandoc, tesseract+data-khm | watcher |
| Chunker + Embedder | sentence-aware ~512-tok overlapping chunks (Khmer needs no-space handling); batch to Ollama `/api/embed`; content-hash dedup; backoff if Ollama down | Ollama `/api/embed` | extractors, ollama |
| Indexer + Knowledge Graph | transactional upsert: `documents`/`chunks`, `vec0` vectors, `fts5` keyword, `entities`/`edges`; graph from cheap metadata first (file↔dir, mail→sender/recipient, calendar→event/attendee), LLM NER later; schema-versioned; deletes cascade | rusqlite, sqlite-vec, fts5 | embedder |
| Query API | hybrid: `vec0` KNN + `fts5` BM25 fused by Reciprocal Rank Fusion, SQL metadata filters, graph context; ranked snippets+sources | SQL (vec0+fts5+RRF CTE); D-Bus `Search()` | indexer |
| Throttler | keep indexing invisible: `systemd` slice (`CPUQuota`, `IOSchedulingClass=idle`, `Nice`, `MemoryHigh`); **first crawl proceeds on battery at deep `idle` nice** (else it never finishes on the target user); ongoing bulk re-embeds gate on AC + idle | systemd slice + AC/idle/thermal checks | koompi-contextd, systemd |

### CORRECTED claims (from the L1 design, falsified by verification)

- **sqlite-vec is brute-force O(n), NOT ANN.** `vec0` does an exhaustive linear KNN;
  ANN (IVF/HNSW) is a pre-v1 roadmap item upstream, not shipped. Budget for linear
  scans (low tens of thousands of docs max on the cheapest CPU); the optional
  LanceDB tier is the escape hatch if a corpus outgrows it. **Do not claim "ANN
  scaling."**
- **The inotify watch limit is already fine on Arch.** `10-arch.conf` ships
  `fs.inotify.max_user_watches=524288` (8× the "65536 too low" premise the design
  asserted). Keep a periodic-rescan fallback for `EMFILE`/`ENOSPC` on a very large
  `$HOME`, but drop the redundant sysctl drop-in.
- **Local Ollama tool-calling fix is NOT a one-line OpenAI-strategy branch.**
  Ollama's `/v1/chat/completions` compat endpoint **silently drops `tool_calls`
  while streaming**. The real fix is a new `ollama` api_format hitting native
  `/api/chat` (§6).
- **Atomic saves are not modify events.** Most editors save via
  write-temp-then-rename → `inotify` sees create+delete+move; the watcher must keep
  `doc_id` stable across the rename.

### CORRECTED: secure-delete and at-rest

Deleting a file cascades rows, but **SQLite does not zero freed pages** and btrfs
CoW retains old extents — plaintext chunks persist in DB free pages until `VACUUM`.
"Delete the sensitive file" does **not** remove its content from the index. L1 must
schedule `VACUUM`/`VACUUM INTO` on deletion, and at-rest protection is a real gap
(LUKS toggle defaults off and is non-functional today — §9).

---

## 6. L2 — Assistant (BUILD by extracting from `Ai.qml`; "AI as foundation")

L2 is the agent that retrieves over L1 (RAG), keeps memory, plans, and acts via
tool-calling. The core move: **extract the agent runtime out of the GUI into a
per-user daemon `koompi-assistantd` (Rust), and make `Ai.qml` a thin D-Bus
client.** Rationale: L4 briefings run headless (no window), L3 apps call the
assistant as a service, and the dangerous tool executor belongs in **one auditable
trust boundary**, not duplicated in QML.

### Components

| Component | Responsibility | Tech | Deps |
|---|---|---|---|
| `koompi-assistantd` | per-user agent runtime: bounded agent loop, conversation state, memory, RAG orchestration, model router, streaming, tool/approval engine. Replaces the `makeRequest()`-chaining inlined in `Ai.qml` `handleFunctionCall` | Rust, tokio, reqwest+rustls, zbus, rusqlite | L1 store, Ollama, keyring, bubblewrap, D-Bus |
| Agent loop | ReAct-style, **hard caps** (`max_iterations` default 8, wall-clock, tokens); validates every tool result (exit code, stderr, empty) and feeds it back (fixes blind continuation `Ai.qml:849-852`); explicit state machine, unit-testable via a `MockModel` | Rust enum state machine | model router, tool engine, RAG |
| Tool registry + policy engine | **ONE uniform gate** for ALL tools (fixes `set_shell_config` ungated). Capability tiers: **READ** (auto: `l1_search`, `read_file`), **WRITE** (confirm: `set_shell_config`, `write_file`), **DANGER** (always-confirm + sandbox: `run_shell_command`). JSON-schema-validate args before dispatch; append-only audit log; structured `ToolResult` on every path | Rust `trait Tool`; D-Bus `PendingApproval` | bubblewrap, polkit, D-Bus |
| `run_shell_command` sandbox | execute the one dangerous tool in an unprivileged namespace (`bwrap`): read-only `/usr`+`/etc`, writable workspace + tmpfs, **network off by default**, no-new-privs, rlimits — not bare `bash -c` with ambient authority | bubblewrap | — |
| Model router | local Ollama default; cloud only if `policies.ai===1` **and** a cloud model selected **and** a BYO key exists; rate-limit/backoff; **hard-enforce `policies.ai` in code** (not UI); honest "no local model — install one" on sub-floor RAM (never silent cloud) | Rust; reuses `AiModel` schema | Ollama, cloud APIs, keyring |
| API strategy layer | normalize openai/gemini/mistral/**ollama** wire formats; **add native `/api/chat` (`ollama` format)** so local models actually stream tool calls; recover from malformed/hallucinated tool calls (small models are unreliable) | Rust enum `ApiFormat` | model router |
| RAG retriever | call L1 `Search()` before/within a turn; assemble token-budgeted context with **source attribution**; tag retrieved chunks as **untrusted** (prompt-injection defense, §9) | rusqlite (L1 DB), Ollama embed | L1 store |
| Memory store | episodic (rolling summaries) + semantic (durable user facts as embedded rows), in the same SQLite DB as L1; schema-versioned (fixes `chatToJson` having no version, `Ai.qml:887`); user-viewable/editable | SQLite tables | L1 store, model router |
| D-Bus service | `org.koompi.Assistant1`: `Ask` (one-shot, headless/L4), `Chat`+`ChatDelta` (streaming), `Summarize`, `Approve`/`Reject`, `ListTools`, `RegisterTool` (L3, MCP-shaped). CLI `koompi-assist` wraps `Ask()` for timers | zbus | D-Bus, tool engine |
| `Ai.qml` thin client | keep the `/`-command chat UX, model/tool/key pickers, streaming render, approval buttons → now D-Bus `Approve`/`Reject`; degraded fallback **inherits the policy gate** (chat-only, no tool exec — never raw curl + ungated bash) | QML/Quickshell.DBus | koompi-assistantd |
| Multilingual layer | detect language (`Translation.languageCode` + Khmer script block U+1780–U+17FF), pin response language via localized system prompt; localize approval/error strings | Rust heuristic + Translation | Translation, model router |

### CORRECTED: the headless approval problem & the forgeable gate

- **Headless ≠ interactive.** The interactive approval gate (`functionPending`) is
  meaningless at 06:00 with nobody watching. L4/automation contexts get a
  **NO-TOOLS-by-default** capability set (READ-only: query/summarize); any tool call
  from a non-interactive trigger is **refused** (or queued as a notification for
  later human approval), never auto-executed.
- **`Approve()` must not be self-callable by malware.** `Approve(callId)` on the
  session bus is callable by **any same-UID process** — exactly the threat the
  sandbox defends against. Bind every `PendingApproval` to the connection that
  opened the conversation (per-`callId` nonce handed only to the initiating client;
  require it in `Approve(nonce)`), and route genuine escalation through polkit. A
  plain method is theater.
- **Phase 0 is a state refactor, not "add an IpcHandler."** `Ai.qml` is a singleton
  with one shared conversation buffer / model / tool. A headless run would clobber
  the live sidebar chat. Extracting per-conversation state is the real prerequisite.

---

## 7. Storage & index design (the load-bearing adjudication)

Three layers proposed **three different homes** for the index/data:

- **L0:** a system `@var_index` subvolume that *survives* System Restore.
- **L1:** per-user `@home` cache (`~/.local/state/koompi/context/index.db`),
  `chattr +C`, **no** new subvolume.
- **Ownership plane:** an `@data` subvolume + index in `@home/.cache`.

These cannot all be true. **The constraint that collapses it:** the index is **not
opaque vectors** — its FTS5/metadata tables hold extracted **plaintext chunks** of
the user's mail/docs, and embeddings are **partially invertible**. Therefore:

1. On `--full` factory reset (clean hand-off to the next student), the index **MUST
   be destroyed**, or the next user inherits the prior user's private content. A
   `@var_index` that `--full` skips **leaks data** → rejected.
2. On a shared lab machine, the index **MUST be per-user**. A system `/var/lib`
   store co-locates students' data and lets one student's `--full` nuke everyone's
   index → rejected.
3. On corruption you **rebuild a derived cache** (resumable re-crawl is the recovery
   path); you do not roll it back. So a separate subvolume's "independent rollback"
   benefit is moot.

**Adjudicated decision:**

| Artifact | Home | Survives System Restore? | Wiped by `--full`? | Per-user? |
|---|---|---|---|---|
| **Derived index** (vectors + FTS + KG cache) | `$XDG_STATE_HOME/koompi/` as a **per-user nested subvol** in `@home`, `chattr +C`, **excluded from `@home` snapshots** | yes (under `@home`; kept when `@` rolls back) | **yes** (required) | **yes** |
| **Canonical encrypted store** (CRDT docs, manifest) | **`@data`** (`/var/lib/koompi/data`), own snapper config, **per-uid subtree** | independently rollback-able | local key destroyed → effectively yes | yes (per-uid) |
| **Master key / DEKs** | gnome-keyring in `@home` | yes | **yes** (correct for hand-off) | yes |

**Refinement (settled in grilling):** the index lives in a **per-user nested btrfs
subvolume** under `@home` (`~/.local/state/koompi`), created at account setup. This buys
two things a plain dir cannot: (1) `nodatacow` via `chattr +C` on the empty subvol
before the DB exists (SQLite on btrfs CoW fragments badly), and (2) **exclusion from
`@home` snapshots** — a nested subvol is not captured in the parent's snapshot, so a
rebuildable GB-scale cache never bloats `@home` rollback points. It is **per-user**, so
the installer's **5 SYSTEM subvolumes are unchanged** and the "no 6th *system*
subvolume" rule holds (a per-user nested subvol is a different category). This refines
the earlier "no separate subvolume" call, which weighed only independent rollback —
moot for a derived cache — and missed the snapshot-bloat cost.

### The one SQLite database

sqlite-vec (MIT/Apache, single C file, bit-quantization 32×) co-located with FTS5
and the knowledge graph in **one** SQLite DB. Schema (one DB, `index.db`):

```sql
documents(id PK, path UNIQUE, mime, size, mtime, sha256, source, lang,
          indexed_at, status)
chunks(id PK, doc_id FK→documents ON DELETE CASCADE, ord, text,
       token_count, content_hash)
vec_chunks USING vec0(chunk_id, embedding float[N])      -- sqlite-vec, quantized
fts_chunks USING fts5(text, content='chunks', content_rowid='id')  -- BM25
entities(id PK, type{person|file|project|event|org}, name, canonical_key UNIQUE)
edges(id PK, src_entity FK, dst_entity FK,
      relation{authored|mentions|attached_to|scheduled|in_dir|sent_to},
      doc_id FK, weight)
memory_facts(id PK, text, embedding, confidence, source_conv, created_at) -- L2
conversations(...) / messages(...)                                        -- L2
work_queue(id PK, path, op{upsert|delete|move}, enqueued_at, attempts,
           state{pending|running|done|failed})                  -- resumable
state(key PK, value)  -- schema_version, model_id, embedding_dim, last_full_crawl
```

**Embedding dimension is welded to the schema.** `vec_chunks` hardcodes
`float[N]`; changing the embedding model (e.g. BGE-M3 1024-dim → nomic 768-dim) is a
**destroy-and-re-embed** of the whole corpus. Mitigation: store `model_id` +
`embedding_dim` in `state`, version the vec table, and run a managed background
re-embed migration — **never** a silent dimension mismatch. Choose the default
embedder (§8) **before** locking the schema.

### Schema migration on a ROLLING distro (the gap no layer owned)

KOOMPI is rolling Arch — there is **no** discrete `v1→v1.1` event. `pacman -Syu`
independently updates `koompi-contextd`, sqlite-vec, the embedding model, and the
on-disk schema, possibly with a power-cut mid-update on the intermittent-power
target. And **System Restore rolls `@` back to `@baseline`** (older daemon binary)
while **`@home` stays current** (newer schema) → **binary-vs-schema skew after every
rollback**.

**Required mechanism (owned by L1, gated on L0 restore):**

```
on daemon start OR after System Restore:
  read state.schema_version, state.model_id, state.embedding_dim
  if binary.expected_schema  > db.schema_version → run forward-only migrations
  if binary.expected_schema  < db.schema_version → rebuild-from-source (derived!)
  if binary.embed_model/dim != db.model_id/dim   → managed background re-embed
  migrations are idempotent + resumable (survive partial-update + power-cut)
  NEVER silently operate on a mismatched schema
```

Because the index is a *derived cache*, the safe fallback for any irreconcilable
skew is **drop + re-crawl** — which is exactly why it must not live anywhere
`--full`/restore semantics make it authoritative.

---

## 8. L3 — App-context bus & L4 — Automation; the model plane

### 8.1 L3 — App-context bus ("apps talk to each other")

A native broker daemon, **`koompi-busd`** (Rust), owns `org.koompi.Bus` on the
**session** bus and is the single mediation point. Apps speak an **MCP-shaped**
schema (resources / tools / intents with JSON Schema) carried over D-Bus.

**Grounded transport decision:** Quickshell **can consume** D-Bus (Mpris,
Bluetooth, DBusMenu) but **cannot export** a D-Bus service (no `DBusObject`/
`registerService` in its qmltypes). So the broker **cannot** live in QML. The shell
talks to the broker over a **unix domain socket** (`Quickshell.Io.Socket`,
newline-delimited JSON-RPC); the broker owns the D-Bus name for the rest of the
desktop. That split is the spine of L3.

| Component | Responsibility | Tech | Deps |
|---|---|---|---|
| `koompi-busd` | live registry of resources/tools/intents; route every call (apps never bind each other directly); enforce capability security; emit `RegistryChanged`; resolve+rank intents; centralized audit log | Rust, zbus, tokio, rusqlite (grant ledger), jsonschema | polkit, D-Bus, L1 |
| `org.koompi.Bus` interface | `Register`/`Unregister`/`ListProviders`/`Describe`/`Query`/`CallTool`/`GetResource`/`ResolveIntent`/`DispatchIntent`; signals `RegistryChanged`/`IntentOffered`. Providers implement a 4-method `org.koompi.Provider` | D-Bus XML | dbus |
| Manifest schema | `{provider_id, resources[{uri_scheme,kind,sensitivity}], tools[{name,input_schema,side_effects,required_capability}], intents[{verb,payload_schema}]}`, schema-versioned | JSON Schema 2020-12 | — |
| Legacy/portal bridge | adapters translating existing app D-Bus (Evolution mail/calendar); map intents (`share.email`, `open.file`) onto `xdg-desktop-portal`; synthesize `open.*` from `.desktop` entries | Rust/Python, xdg-desktop-portal | target apps |

**CORRECTED — capability isolation is advisory, not real, on stock Arch.** On a
single-UID desktop every app runs as the user; the broker can stop app A calling
app B *through the broker* but **cannot** stop A from reading B's files or the L1
DB, or calling B's `org.koompi.Provider` directly (session.conf ships
`<allow send_destination="*">`). **State the threat model honestly:** the bus
defends against the **confused-deputy assistant** and **cooperative-but-buggy apps**,
**not** malicious same-UID code. Two fixes make mediation an enforced invariant
rather than theater: (1) every provider verifies `sender == NameOwner(org.koompi.Bus)`
and rejects others (baked into the SDK); (2) the daemon **owns** the tool→tier map —
**never** trust a registrant's self-declared risk tier; treat all externally
registered tools as WRITE-minimum, never auto-allowed. Genuine isolation of
sensitive providers (mail/contacts/index) requires sandboxing (Flatpak + portals).

> **Open, hard, not deferrable:** the consent/approval surface must render in **both**
> Hyprland (Quickshell) and KDE. Quickshell covers Hyprland; KDE-native flows need a
> standalone polkit-style consent agent. "Two flavors" is a fixed constraint, so this
> gates every gated flow on the KDE edition.

### 8.2 L4 — Automation ("morning automated: collected, organized, ready")

Durable triggers live in **`systemd --user` `.timer` units** (NOT a QML `Timer`,
which only fires while the shell is alive and does no catch-up). The chain:

```
koompi-briefing.timer (OnCalendar=06:00, Persistent=true, ConditionACPower=true,
   RandomizedDelaySec, Nice=10, slice CPUQuota/MemoryMax)
        │ fires (or catches up after overnight power-off)
        ▼
automation-run (runner): compute runId=briefing-YYYY-MM-DD; flock; check
   fsync-gated completion marker (idempotent across power cuts); then
        │  koompi-assist ask  (or qs ipc → assistant)  — HEADLESS, READ-only caps
        ▼
koompi-assistantd.Ask()  → RAG over L1 (calendar/mail/notes/RSS) → local Ollama
   summarize → three sinks: notification + sidebar card + markdown digest
        │  digest written + fsync'd  → THEN  marker written  (sync-barrier
        ▼                               discipline copied from reset_home.sh)
```

| Component | Responsibility | Tech | Deps |
|---|---|---|---|
| timer units | durable wall-clock triggers with overnight catch-up, AC gating, randomized delay, cgroup caps | systemd user units | systemd |
| `automation-run` | bridge trigger→assistant; idempotency marker; flock; per-flow timeout; retry/backoff; write run-history | bash, flock, timeout | timers, assistantd |
| AutomationEngine | declarative rule files `~/.config/koompi/automations/*.json`; multi-step flow exec; partial-degrade (produce what's available, name what's missing) | Rust (or Quickshell singleton) | assistantd, L1, L3 |
| CapabilityBroker | per-automation grant set; **default READ-only**; WRITE/DANGER only if the user explicitly granted that capability to that automation; record exercised caps | Rust, grant store | policy |
| EgressGuard | per-run egress ledger; inbound public fetch (RSS = OK) vs outbound private-data egress (notes/mail → cloud LLM = gated); honor `policies.ai` | Rust | policy |

**CORRECTED for L4:** (a) the privacy gate must move to a **per-request** chokepoint,
not `setModel()` selection-time; (b) Ollama serializes around a resident model, so an
L4 briefing and an interactive chat collide — queue around the resident model or run
the briefing when interactive use is idle; (c) `OnCalendar`+`Persistent` assume a
correct clock — on cheap hardware without an RTC battery, gate the catch-up run on
`timesyncd` having synced; (d) automation must NOT route through the interactive
approval gate (no human at 06:00) — see §6 headless rules; (e) the runner only
*calls into* the shell via `qs ipc` if the shell is alive — for the KDE edition and
shell-down robustness, the headless flow-runner (Ollama + sqlite-vec + D-Bus, no
`qs ipc`) is required.

### 8.3 Model plane

Local Ollama is the on-device default; cloud is BYO-key opt-in. **The binding
constraint is RAM, not the model menu.**

| Role | Default (license-pinned at build) | License | Footprint (Q4_K_M) |
|---|---|---|---|
| Embeddings | **BGE-M3** (1024-dim, 8192 ctx, **explicit Khmer**) via `/api/embed` | **MIT** ✓ | ~1.2 GB resident |
| Chat (8GB+) | **Sailor2-8B** or a 3–4B Apache/MIT Khmer-covering model | **Apache-2.0** ✓ | ~4 GB resident (3–4B) |
| Chat (4GB) | small (1B Q4) or **chat disabled, cloud-opt-in** | Apache/MIT ✓ | ~2 GB (1B) |
| Reasoning | **cloud opt-in only** — no usably-small reasoning model fits the floor | — | — |

**Capability ladder (deterministic, never silent cloud):**

```
≥16 GB : chat (3-4B) resident + BGE-M3 resident + RAG local + headroom for 8B opt-in
  8 GB : ONE model resident (1-3B) with a light browser, OR chat-on-demand with the
         5-15s model-reload latency shown in UI  (keep_alive=0 ⇒ honest tradeoff)
  4 GB : BGE-M3 embed + retrieval ONLY; local chat OFF; chat = explicit cloud opt-in
no Ollama : keyword/semantic retrieval still works; generative answers disabled
            with a clear banner
sub-floor : honest "no local model — install one via Ollama"  (NEVER silent cloud)
```

**CORRECTED — model WEIGHT licenses ≠ library licenses.** Ollama/llama.cpp are MIT,
but that does **not** cover the weights. **Flagged, do NOT bundle as defaults:**
**Qwen2.5-3B** = Qwen **Research** (non-commercial) — *only that 3B*; Qwen2.5 base
sizes are Apache. **Gemma 3** carries custom Gemma Terms (acceptable-use strings) —
prefer Gemma-4/Apache **only if confirmed against the actual `LICENSE` at pin time**.
**Llama** = Meta Community License (>700M-MAU + acceptable-use). The clean anchors
are **Sailor2** (Apache, Khmer-strong), **BGE-M3** (MIT), **nomic-embed** (Apache).
Verify each weight's license text at pin time; do not assert from memory.

**Bootstrap honesty:** a fresh/offline install has **no model** until ~4 GB of pulls
complete — multi-hour over spotty connectivity. v1 must **ship a default chat+embed
model on the install media or a LAN mirror**, or make first-run pull an explicit,
consented, progress-shown step. Drop "works fully offline" until a model is present.

---

## 9. Privacy & security — the threat model

FORK A posture: **local-first / private is the on-device default; nothing leaves
unless explicitly opted in.** This section is deliberately honest about where the
*current* code and even the *designs* fall short of that promise.

### The one policy authority (adjudicated)

Four layers each claimed to be "the sole egress chokepoint" (`org.koompi.Policy`,
`koompi-syncd`, `koompi-assistantd`, the L3 gate). **There is exactly one policy
authority — `org.koompi.Policy` — and everything else is a consumer.**

```
org.koompi.Policy  (system + per-user D-Bus daemon, FAIL-CLOSED)
  CanRead(scope, path) -> bool                 # gates L1 indexing & L2 retrieval
  CanEgress(target, kind) -> allow|deny|prompt # gates the ONLY two egress paths:
                                               #   cloud-LLM request, KOOMPI.Cloud sync
  RequestConsent(action) -> grant|deny         # drives a polkit-style prompt
  GetEffectivePolicy(uid) -> {scopes, egress, locked_by}
  # per-user policy with an admin/parent LOCK FLOOR a student cannot loosen
  # telemetry=none: v1 = policy-enforced (soft); STRUCTURAL no-egress (no outbound path
  #   but these two) only once P-2 root-owned netns/nftables lands (1.x) — see §9 CORRECTED
```

### CORRECTED — a session-bus daemon is NOT enforcement

A daemon that components *voluntarily* consult does not contain malicious local code.
On stock single-UID Arch, `run_shell_command` (`bash -c`, verified) and the cloud
path (a curl script written to `/tmp` and run as the user) **bypass any session-bus
policy daemon entirely**. **"Verifiable: nothing leaves your machine" is FALSE as
stated** — a packet capture will show the user's browser traffic.

- **Honest claim:** *the SYNC path is the only audited data-egress path, and you can
  verify it carries only ciphertext to one host.*
- **Real egress enforcement** (what it would take, not yet built): a **root-owned**
  mechanism — per-app network namespace + nftables allowlist (only `localhost:11434`
  and the named sync host) — so a user-process `curl` or `run_shell_command`
  physically cannot reach arbitrary hosts when `policy=local-only`. Then the D-Bus
  daemon manages the allowlist; it is not the sole gate. **The allowlist is
  policy-driven, not static:** `local-only` ⇒ `{localhost:11434, sync-host}`;
  `cloud-permitted` (`ai=1` + a selected cloud model + BYO key) ⇒ **+ that cloud host**
  — so `assistantd`'s cloud call (§6) is an *allowed* egress, not a contradiction. The
  Subsystem (1.x) generalizes this to a per-context allowlist (`CanEgress(context_id,…)`) —
  the Subsystem is a three-mode, trust-driven model (Light / App Window / Detonation Chamber),
  see [ADR-0010](adr/0010-subsystem-two-axis-trust-driven-isolation.md).

### Adversaries, mitigations, residual risks

| Adversary | Mitigation | Residual (honest) |
|---|---|---|
| Cloud / network operator (incl. compromised KOOMPI.Cloud) | E2EE per-object AEAD; zero-knowledge by construction; content addressing | metadata leakage (object count, sizes, edit timing) — partially mitigated by padding buckets, **not** eliminated |
| Public-chain observer (Selendra) | only DID, device pubkeys, rotation/revocation, **salted-commitment Merkle roots**; never `hash(plaintext)`, never per-operation | anchor cadence reveals coarse activity timing |
| Physical theft / shared-machine other user | per-user keyring; recommend LUKS; per-object AEAD makes the store opaque at rest | **LUKS toggle defaults OFF and is a non-functional TODO** (`config.zig:57`, `main.zig:168/211`); the at-rest promise protects **nobody by default** today |
| **Malicious / buggy local app (same UID)** | capability tiers; sandboxed `run_shell_command`; one audited egress daemon | **session-unlocked keyring** exposes the master key + every DEK to **any** same-UID process; at-rest encryption defends ONLY offline theft, **not** app-exfil. The capability gates are **advisory** against same-UID malware |
| **Prompt injection via RAG → ungated tools (the marquee threat)** | mark RAG content untrusted; separate data channel from instruction channel; READ tools never egress; **fresh, typed confirmation** for any WRITE/DANGER whose args derive from retrieved content | an OS that indexes untrusted mail/PDFs **and** can run shell is the textbook lethal trifecta; a poisoned doc + one habituated approval click = RCE/exfil. Containment must ship **with** local tool-calling, never a phase later |
| **Forgeable approval** | bind `PendingApproval` to the initiating connection (per-`callId` nonce); route escalation through polkit | a plain `Approve(callId)` on the session bus is self-callable by the malware it guards against |
| Tampering | Merkle anchoring + content addressing + AEAD detect manifest/blob/ciphertext tampering | audit log lives in a same-UID-writable store → tamperable; needs hash-chaining or off-device shipping for the school-governance claim |
| Minors' data / shared lab | per-user policy LOCK floor; per-user index+keyring; `--full` wipes per-user data | the floor lives in `@` and is **reverted by factory reset** unless moved to a non-reverted location + baked restrictively into `@baseline`; a written consent framework (COPPA/GDPR-minor) does not exist yet (§13) |

### Install-time secrets & root account

Passwords go to tmpfs (`/dev/shm` chmod 600), deleted after archinstall exits, never
on the target disk. **Fix:** hold the password in a locked/zeroed buffer and wipe it
right after the creds write (today it is a plain slice never zeroed,
`config.zig:47`/`archinstall.zig:165`). Root stays **locked**; admin via a
sudo-group user — **verify** the pinned archinstall honors the `sudo` field, else
`koompi-restore` (root-required) is unrunnable.

---

## 10. Multi-user (shared lab machines) — a first-class case, not the primary deployment

Shared/inherited devices are a first-class supported case (the individual on a personal
machine is the primary deployment — prd §2). Several designs proposed
**system-wide** `/var/lib` user-data stores (`@var_index`, `/var/lib/koompi/data`,
`/var/lib/koompi/index`) — **rejected**: they co-locate one student's index/keys with
another's, and one student's `koompi-restore --full` would wipe **every** user's
index. The per-user `systemd --user` daemon model (L1/L2/L3) contradicts those
system-wide stores; the per-user model wins.

**Adjudicated multi-user invariants:**

- Per-user index namespace (the derived `index.db` under each user's `$XDG_STATE`,
  §7), per-user keyring/master key, per-user `koompi-assistantd`/`koompi-contextd`/
  `koompi-busd` instances, per-user policy.
- The admin/parent **policy LOCK floor** lives where factory reset cannot revert it
  (a persistent location + a restrictive floor baked into `@baseline`), so a minor's
  factory reset can only land on a *more* restrictive state, never loosen it.
- `--full` hand-off is **per-user**: wipe the leaving user's `@home` (and thus their
  index + keys) cleanly; the system (`@`) reverts to `@baseline`.

---

## 11. Resource budgets on modest hardware (summed, not per-daemon)

Each layer measured its own daemon and declared itself cheap. **Summed honestly:**

| Component | Idle RSS | When working |
|---|---|---|
| `koompi-contextd` | tens of MB | extract/embed = the real cost; OCR (tesseract) is CPU-bound, seconds/image |
| `koompi-assistantd` | single-digit MB | dominated by the model, not the daemon |
| `koompi-busd` | ~8–15 MB | human-paced D-Bus round-trips |
| `org.koompi.Policy` | small | event-driven |
| Ollama + **embed model** | — | **~1.2 GB resident** (BGE-M3) |
| Ollama + **chat model** | — | **~2 GB (1B) / ~4 GB (3–4B)** resident |
| Hyprland/KDE + browser | — | the rest of the budget |

**The honest conclusion the per-daemon framing hid:** on the **4 GB floor** (~1.5 GB
free after DE+browser), the chat+embed pair alone **exceeds budget**. The floor
hardware **cannot run the agentic experience locally** — so the floor tier is
**embed+retrieval only, local chat off, chat = explicit cloud opt-in** (§8.3). The
failure mode to avoid at all costs is **silently** routing the poorest users to
cloud, which inverts the moat for exactly its target user. Where local is
infeasible, the degraded path is explicit and consented.

**Power/thermal:** continuous embedding is the real battery/thermal risk. Gate
ongoing bulk re-embeds on **AC + system idle + below a temp threshold**; allow the
**one-time first crawl** to proceed on battery at deep `idle`/`Nice` (else it never
completes for an always-on-battery student). sqlite-vec bit-quantization (~32×) keeps
the DB small (tens of MB for ~10k docs). Factory reset is offline btrfs ops + skel
copy, target ~2–5 min on low-spec with `sync` barriers so a power cut fails safe.

**Net:** zero network by default; install pulls from `[koompi]` once (+ the model
seed); restore needs no internet; index + embeddings on-device; sync is opt-in only.

---

## 12. Interfaces (engineer contracts)

```
# ── POLICY (the one authority; FAIL-CLOSED) ──────────────────────────────────
org.koompi.Policy (system + session)
  CanRead(scope:s, path:s) -> b
  CanEgress(target:s, kind{cloud-llm,sync}) -> {allow,deny,prompt}
  RequestConsent(action:struct) -> {grant,deny}
  GetEffectivePolicy(uid:i) -> {scopes, egress, locked_by}

# ── L1 CONTEXT ENGINE ────────────────────────────────────────────────────────
org.koompi.ContextEngine (session, per-user, object /org/koompi/ContextEngine)
  Search(query:s, filters:a{sv}, k:u)
        -> a(snippet:s, source_path:s, score:d, mime:s, entity_ids:au)
  Get(doc_id:x); Reindex(path:s); ExcludePath(path:s)
  Status() -> {queued:u, indexed:u, last_run:t, ollama_up:b, model:s}
  signals: IndexingProgress, IndexReady
  # per-peer authorization: resolve caller PID→exe, allowlist L2/L4/launcher;
  # gate sensitive sources (mail/chat) behind an explicit per-app grant.
embed: Ollama POST /api/embed  -> float[N]      # the formal L1↔model interface

# ── L2 ASSISTANT ─────────────────────────────────────────────────────────────
org.koompi.Assistant1 (session, per-user)
  Ask(prompt:s, opts:a{sv}) -> reply:s                 # one-shot, headless/L4
  Chat(conversationId:s, prompt:s) -> callId:s
        + signals ChatDelta(callId, role, delta), ChatDone(callId)
  Summarize(uri:s) -> reply:s
  Approve(callId:s, nonce:s) / Reject(callId:s)        # nonce-bound, not self-callable
        + signal PendingApproval(callId, toolName, argsJson, riskTier)
  ListTools(); RegisterTool(busName:s, schemaJson:s)   # L3, MCP-shaped
  CLI: koompi-assist ask|chat|summarize                # for systemd timers
Tool trait (Rust): name(); schema()->JsonSchema; capability()->Read|Write|Danger;
                    call(args, ctx)->ToolResult
ApiStrategy: build_request; parse_stream_delta -> Content|ToolCall|Usage|Done
             per ApiFormat(openai|gemini|mistral|OLLAMA-native /api/chat)

# ── L3 APP-CONTEXT BUS ───────────────────────────────────────────────────────
org.koompi.Bus (session, name owner = broker)
  Register(manifest_json) -> token; Unregister(token)
  ListProviders(); Describe(provider_id); Query(filter_json)
  CallTool(provider_id, tool_name, args_json, ctx_json) -> result_json
  GetResource(provider_id, uri, ctx_json) -> {uri+metadata | fd}   # NOT base64 blobs
  ResolveIntent(verb, payload) -> ranked; DispatchIntent(verb, payload, ctx)
  signals: RegistryChanged, IntentOffered
org.koompi.Provider (each app; ONLY the broker may call; verify sender==NameOwner(Bus))
  Describe(); CallTool(); GetResource(); HandleIntent()
QML↔broker: Quickshell.Io.Socket → $XDG_RUNTIME_DIR/koompi/busd.sock (NDJSON-RPC)

# ── OWNERSHIP / SYNC (opt-in) ────────────────────────────────────────────────
koompi-vault C ABI: vault_unlock; vault_encrypt/decrypt(object_id, …);
                    vault_wrap_master_to_pubkey(pubkey); vault_rotate_master
KOOMPI.Cloud HTTP: PUT/GET /blob/{ciphertext_hash}; LIST /manifest?since={vv};
                   POST/GET /oplog?since={vv}; POST /escrow; DELETE /account
                   auth = sign a challenge with a Selendra-registered device key
koompi-anchor (abstract; impl deferred): registerDID; rotateKey; revokeDevice;
                   anchorRoot(merkle_root); recordGrant
```

`ctx_json` on every bus call carries `{request_id, on_behalf_of, consent_token?}`;
the `consent_token` must be broker-minted, bound to `(caller, tool, args-digest,
nonce, short TTL)`, single-use, verified server-side — **not** a forgeable
same-UID string.

---

## 13. Data-ownership plane (FORK A) & dependency licenses

### Tiering (the load-bearing decision)

```
ON-DEVICE (everything by default)        KOOMPI.Cloud (self-hosted, zero-knowledge)
  master key (keyring + PAM, TPM2 opt)     E2EE content-addressed ciphertext blobs
  per-object DEKs, ALL plaintext           encrypted CRDT op-log
  sqlite-vec DERIVED index (@home)         version-vector metadata
  Automerge CRDT canonical store (@data)   optional wrapped key-escrow blob
                                           sees ciphertext/sizes/timing, never keys
SELENDRA (public ledger, tiny + RARE writes only)
  DID doc · device pubkeys · key rotation/revocation
  PERIODIC signed Merkle root over the object manifest (salted commitments)
  NEVER per-operation · NEVER hash(plaintext)
```

**CRDT scope is bounded:** Automerge for structured mutable data
(notes/todos/config/KG metadata); content-addressed versioning (no CRDT) for large
blobs; **the index is NEVER synced** — each device re-embeds locally from synced
source (syncing a binary vector DB is conflict-hell, and re-deriving resolves the
storage-coupling cleanly). **CORRECTED:** re-embed at pairing is **not** incremental
— a freshly paired device embeds the entire corpus from zero (hours, battery-hostile)
— so consider a one-shot wrapped index transfer between same-arch trusted devices at
pairing (not "sync"). **CORRECTED:** anchoring needs **gas** (a paid on-chain tx) —
an economic "string" for a general-purpose OS; either KOOMPI relays/subsidizes anchor
txs (re-centralizes ownership, document it) or anchoring is fully optional with a
"works with zero blockchain interaction" default.

### `--full` vs cloud retention

`--full` is **local-only** (correctly destroys local keys/data/index for hand-off);
cloud ciphertext persists until a **separate explicit** "delete cloud account"
action (keeps the "reset is not a backup product" non-goal honest). The UX
**enforces migrate-before-wipe** ordering, or data is unrecoverable.

### Dependencies & licenses (every default flagged)

| Dependency | License | Status | Why |
|---|---|---|---|
| sqlite-vec | MIT / Apache-2.0 dual | ✓ clean, NOT open-core | default on-device vector index, single C file, 32× bit-quant |
| SQLite + FTS5 | Public Domain | ✓ | the one DB (index + KG + memory + BM25) |
| Ollama / llama.cpp | MIT | ✓ (engine only) | local chat + `/api/embed`; **does NOT license the weights** |
| **BGE-M3** (weights) | MIT | ✓ | default embedder, **explicit Khmer** — the model↔i18n intersection |
| **Sailor2** (weights) | Apache-2.0 | ✓ | clean Khmer-strong chat anchor |
| **Qwen2.5-3B** (weights) | Qwen **Research** | ✗ **REJECTED** (non-commercial; *only* the 3B — base sizes are Apache) | recorded rejection |
| **Gemma 3** (weights) | Gemma Terms (custom) | ⚠ FLAGGED (acceptable-use strings); Gemma-4 Apache only if confirmed at pin | verify `LICENSE` text, do not assume |
| Automerge | MIT | ✓ | CRDT for structured data |
| libsodium | ISC | ✓ | AEAD / key wrapping / Argon2id |
| BLAKE3 | CC0 / Apache-2.0 | ✓ | content addressing + Merkle roots |
| SeaweedFS | Apache-2.0 | ✓ (explicitly chosen over AGPL MinIO/Garage) | self-hosted ciphertext blob store |
| rustls / zbus / tokio / rusqlite / serde / reqwest | MIT or MIT/Apache | ✓ | daemon runtime, D-Bus, TLS |
| bubblewrap / polkit | LGPL-2.x | ✓ (arm's-length over IPC) | sandbox + consent |
| poppler / pandoc / libreoffice | GPL-2/3 (COPYLEFT) | ⚠ FLAGGED — **subprocess only**, never linked | extraction; license isolation by process boundary (build-system invariant) |
| tesseract + data-khm | Apache-2.0 | ✓ | OCR incl. Khmer |
| noto-fonts-khmer | OFL-1.1 | ✓ | Khmer glyph rendering |
| fcitx5 + fcitx5-keyboard + xkeyboard-config `km` | LGPL / MIT-X11 | ✓ | Khmer input (XKB `km`; **NOT** fcitx5-unikey — that is Vietnamese) |
| ICU (libicu) | Unicode License | ✓ | dictionary word-segmentation for spaceless Khmer lexical search |
| subxt / alloy | Apache / MIT | ✓ | Selendra anchor client (impl deferred behind abstract interface) |
| LanceDB OSS | Apache-2.0 lib, **OPEN-CORE** product | ⚠ optional heavier/multimodal tier ONLY, never the default | escape hatch if sqlite-vec is outgrown |

Run `cargo deny` / a transitive-license scan in CI before declaring the set
no-strings.

### I18N (FORK C) — Khmer ships as an ATOMIC unit or not at all

English default, Khmer first-class. The legs **must ship together** or you get tofu
boxes / silently-failing search:

1. `km_KH.json` strings (matches the existing JSON-per-locale schema) + a
   `Translation.tr` fallback chain **`km_KH → en_US → key`** (today it falls straight
   to the English key) + a CI key-coverage gate.
2. `noto-fonts-khmer` + a fontconfig fallback rule (else Khmer renders as boxes).
3. Input: the **XKB `km` layout** with `fcitx5-keyboard` as switcher + the session
   IM-env wiring (Hyprland Wayland input-method + env vars; KDE native) — packaging
   the config alone is not enough.
4. **ICU dictionary word-segmentation** for L1 lexical search (Khmer has no
   inter-word spaces) **and** a Khmer-capable **embedding** model (BGE-M3) for
   semantic search — half the OS's search fails for Khmer otherwise.

---

## 14. Cross-layer risks & the reconciled v1 phasing

### What no single layer owns (the completeness gaps)

- **Testing / CI.** Zero tests in the repo; no `zig build`/`zig test` in any
  workflow; **no prompt-injection regression corpus** — the single most important
  test category for an OS that indexes untrusted content and can run shell. Build:
  (a) the installer/restore VM harness (close the GRUB + overlayfs legs first),
  (b) a tool-call/RAG golden set against the pinned local model, (c) the injection
  corpus. Sequence injection mitigation to ship **with** local tool-calling.
- **Accessibility.** Zero a11y references anywhere — for "an OS for the world" this
  is a whole-stack hole. Assess Wayland/Orca/at-spi reality on Hyprland + KDE; add
  font-scaling/contrast/reduced-motion to the shell; make the **consent/approval
  surface reachable by AT and keyboard-only**; design the assistant text/voice path
  as an accessibility affordance (a genuine win if deliberate).
- **Schema migration on a rolling distro + binary-vs-schema skew after restore** —
  owned by L1 but gated on L0 restore (§7).
- **Cross-component packaging & service orchestration** — 5 new daemons all
  depending on the policy daemon, all gated on the unpublished `[koompi]` repo (G3);
  define the systemd-unit / D-Bus-activation ordering and the model-weight
  distribution.
- **Doc coherence** — the canonical PRD still encodes the dead thesis (§ banner).

### The three contradictions, resolved in this doc

1. **Index location** → per-user derived cache in `@home`, wiped by `--full`,
   rebuilt on corruption; canonical encrypted store in `@data`. `@var_index`
   rejected (§7).
2. **Sole egress chokepoint** → one authority (`org.koompi.Policy`); real
   enforcement needs root-owned netns+nftables, not a voluntary session-bus call
   (§9).
3. **Multi-user** → first-class case (not primary); per-user everything; no system-wide
   `/var/lib` user-data stores (§10).

### Reconciled critical path (the unavoidable prefix, then L1→L4)

```
0. Doc gate: rewrite docs/prd.md to the settled decisions (else agents build wrong)
1. Flip Config.qml:84 policies.ai 1 → 2 (local-first true), add policies.sync = 0
2. Gate set_shell_config behind the same approval as run_shell_command;
   add a protected-key denylist so the tool path can NEVER write policies.*
3. Replace the .includes("localhost") check with a parsed-URL host allowlist
   {localhost,127.0.0.1,::1}; move the gate to a per-REQUEST chokepoint
4. Decide storage (§7) — per-user @home derived index; chattr +C at first-run
5. Ship a fail-closed org.koompi.Policy STUB (always-deny absent policy) so L1-L4
   code against the contract from day one
6. Close ship gates: G3 (sign+publish [koompi]), G1 (installer executes),
   G2 (installer on ISO); add build-installer.yml; VM-verify restore (GRUB +
   overlayfs legs) WITH an encrypted index present
   ── then, each behind the gates above ──
P1  L0 substrate: koompi-restore PKGBUILD + polkit; @data + per-user index slot;
    pre-stage sqlite-vec/ollama/poppler/tesseract; seed a default model on media
P2  L1 Context Engine: watch→extract→embed→index; hybrid Search(); schema-version
    + migration runner; ICU segmentation; BGE-M3 (license-verified)
P3  L2 Assistant: extract koompi-assistantd (per-conversation state); native
    /api/chat tool-calling; RAG with untrusted-tagging; bubblewrap sandbox;
    nonce-bound Approve; memory; multilingual
P4  L3 App-context bus: koompi-busd; MCP manifests; broker-mediation invariant;
    KDE consent agent; Calendar/Evolution pilot
P5  L4 Automation: timers → headless Ask(); CapabilityBroker (READ-only default) +
    EgressGuard + run-history; the morning-briefing demo
P6  Ownership/sync (opt-in): on-device encryption-at-rest; KOOMPI.Cloud zero-knowledge
    backup; Automerge multi-device + QR pairing; Selendra anchoring + egress-audit UI
i18n  Khmer atomic unit lands with P1/P2 (font+IME+strings+segmentation together)
```

**Minimal coherent slice (cross-layer, not deliverable by one team):**
the prefix (1–6) + a narrow L1 (RAG over a few folders) + L2 daemon + the L4 morning
briefing. That demonstrates the three talk beats — *never find files again* (RAG),
*AI as foundation* (daemon as system service), *morning automated* (headless
briefing) — on the local-first stack, honestly, without the full L3 bus.

---

## 15. Open questions (genuine unknowns; resolve with the team)

- **Hardware floor specs** (CPU/RAM/storage) are undocumented — gate model sizing,
  throttle limits, and whether local agentic use is viable out of the box.
- **Selendra capability:** native DID pallet vs EVM/ink! registry contract; finality;
  **per-tx gas economics** (the no-strings violation that is economic, not SPDX).
- **Khmer chat quality:** a generic 3–4B covers Khmer but may be weak; ship a
  Khmer-strong (Sailor2-8B) opt-in tier vs accept weaker Khmer on the floor.
- **`km_KH.json` sourcing + QA:** who translates ~38 KB of strings to fluent Khmer;
  the Gemini auto-translate path is cloud-only (contradicts offline-first); coverage
  threshold to enable the locale.
- **Headless automation consent default:** deny (briefing fails safe) vs narrow,
  time-boxed, logged standing grants. Default to deny + scoped grants.
- **KOOMPI.Cloud operational model:** who self-hosts for non-technical users — a
  KOOMPI-run instance (weakens "infra you control") vs user/school-hosted — shapes
  auth/onboarding and the whole moat claim.
- **libvaxis on Zig 0.16:** does a compatible pinned revision exist? If not, G1's
  TUI is gated on an upstream tag the team cannot force; fallback is a hand-rolled
  raw-terminal TUI (the state machine is already dependency-free).
- **archinstall exact pin** + whether it honors the `sudo` group field (else
  `koompi-restore` is unrunnable) and the real `genfstab`/`grub.cfg` `subvol=` forms
  (the open restore legs).
- **TPM2 prevalence** on target hardware (baseline is keyring/PAM + LUKS).
