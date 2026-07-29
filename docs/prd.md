# KOOMPI OS — Product Requirements Document

**The OS That Thinks.** An AI-first, data-aware, local-first operating system for the world — a rolling Arch Linux base (Hyprland + KDE Plasma) where you work with your data instead of hunting for dead files, the assistant is the foundation rather than a sidebar, and your data and your AI stay on your machine unless you choose to sync them to infrastructure you control.

**Date:** 2026-06-07
**Repo:** `~/workspace/koompi-desktop` (canonical, public) — github.com/rithythul/koompi-desktop
**Status:** Pre-v1 (Naga). Desktop base production-grade; the "thinks" stack (~0% built today) is the work this PRD scopes. The current AI surface is a commodity chatbot sidebar — see §4.
**Companion docs:** [`docs/roadmap.md`](roadmap.md) (current ship-gates, restore stack), [`docs/os-build.md`](os-build.md) (build/package architecture), [`docs/data-ownership.md`](data-ownership.md) (the ownership/sync plane design), [`docs/naming.md`](naming.md) (release eras), [`UPSTREAM.md`](../UPSTREAM.md) (fork attribution).

> **This PRD rewrites the product thesis.** The previous PRD positioned KOOMPI as a Cambodia-locked education OS whose moat was regional/recovery and which deferred AI as "not the moat." That framing is **dead and inverted** (founder decision, 2026-06-07). KOOMPI OS is now a **general-purpose, AI-first OS for the world**; the moat is **data-ownership AI in the AI era** (local-first/private by default; opt-in sovereign sync); Khmer is a **first-class feature**, not the positioning. Where the rest of the repo still carries the old frame, it is stale and must be reconciled — tracked as a hard doc-coherence gate in §11.

---

## 1. Vision & Positioning

### The thesis

Today you don't work with your data — you manage files. A document is a dead blob in a folder you have to remember; your mail, notes, calendar, and chat live in silos that cannot see each other; and the "AI" bolted onto your desktop is a chat window that knows nothing about any of it. KOOMPI OS inverts this. The OS understands your data: it watches, extracts, and indexes what is yours into a private on-device knowledge layer, so you **never find files again** — you ask, and the answer comes with its source. **Apps talk to each other** through a capability bus so the assistant can act across them. AI is the **foundation, not a feature** — the substrate the whole desktop is built on. And the morning is **automated: collected, organized, ready** before you sit down. The interface should be as intuitive as your thoughts. (Vision verbatim from the founding talk, smallworld.xyz, by OS lead Brilliant Phal: "you don't compute, you work with data"; "10 outthink 10,000".)

### The positioning — data ownership in the AI era

The differentiator is **not** that KOOMPI has AI; every OS will. It is **whose machine the AI and the data run on.** Apple Intelligence, Microsoft Copilot, and Google's assistant are converging on a model where your data is the price of the intelligence. KOOMPI's stance is the opposite and is **code-enforced, not a slogan**:

- **Local-first / private is the on-device default.** The index, the models, and your data live on the device. Nothing leaves unless you explicitly opt in (FORK A).
- **Opt-in sovereign sync.** When you choose to sync, it goes to the **KOOMPI ecosystem you control** — KOOMPI.Cloud (self-hosted storage/sync) for data, Selendra (a blockchain) for identity/ownership/keys — not to Big Tech.
- **"Your data and your AI never leave your machine; when you choose to sync, it is to infra you control."**

This is a global thesis for the AI era, not a regional one. It is for anyone who wants an intelligent desktop that does not surveil them.

### Two desktop flavors

KOOMPI ships **two first-class editions** — a Hyprland (Quickshell) edition and a KDE Plasma edition — over a shared semi-immutable Arch base. Both must carry the thinks stack; any feature that exists only on Hyprland is a v1 scope cut to be named explicitly (§7).

### Honest framing (load-bearing)

The vision above is **mostly unbuilt.** What ships today is a polished end-4/dots-hyprland reskin on Arch, a **commodity chatbot sidebar** (cloud LLMs + local Ollama, a `/`-command chat, a user-approval gate on shell commands), and a **code-complete-but-never-executed** btrfs/snapper restore stack. The data fabric, semantic search, knowledge graph, app bus, automation engine, and the ownership/sync plane are **~0% built.** §4 states the gap precisely. This PRD scopes the whole architecture (FORK B: no shortcuts) and then carves a v1 slice (§7).

### Upstream honesty

The desktop shell is **not original work.** KOOMPI OS is a downstream GPL-3.0 fork of end-4/dots-hyprland (illogical-impulse, also GPL-3.0), sharing the upstream commit history via git renames so upstream fixes auto-follow across merges (`UPSTREAM.md:11-30`). KOOMPI's own work is the Hyprland config bridge and OS integration, branding, the Zig installer + Arch packaging tree, added AI providers — and, going forward, the entire L1–L4 thinks stack and the ownership plane.

---

## 2. Target Users

General-purpose and worldwide. KOOMPI OS is for people who want an intelligent desktop that keeps their data theirs.

- **Primary:** individuals on personal laptops/desktops who want their files, mail, notes, and calendar to be queryable and their AI private — students, knowledge workers, developers, writers, researchers — anywhere in the world.
- **Secondary:** privacy-conscious users and organizations who want AI productivity without Big-Tech data egress, and who may opt into self-hosted/sovereign sync.
- **Khmer speakers** are a deliberately served audience (FORK C: Khmer first-class, English default), but Khmer is a feature of a global product, not the product's identity or constraint.

Multi-user / shared machines are a **normal-OS concern** the design must handle (per-user index, keyring, policy isolation), not the primary deployment the product is built around.

*Concrete target-hardware specs (CPU/RAM/storage floor) are not documented in the repo and gate local-model feasibility — see §11.*

---

## 3. The Moat — data-ownership AI

The moat is a **coherent, code-enforced, local-first AI OS**: the intelligence runs on your hardware, indexes your data on your hardware, and only ever leaves to infrastructure you own. Four strands, all gated on the roadmap:

1. **An on-device data fabric (L1).** A private knowledge layer — semantic index + metadata/knowledge graph — built from your own files/mail/notes/calendar on the device. The intelligence is grounded in *your* data, not a generic model. This is "never find files again," and it is the substrate competitors cannot offer without sending your data to their cloud.
2. **An assistant that acts, privately (L2/L3).** Retrieval-augmented, cross-session memory, plans and acts across apps via a capability bus — defaulting to a local model, with cloud strictly opt-in and per-request gated.
3. **Verifiable local-first.** Privacy is enforced in code at a single chokepoint, not toggled in the UI; the **sync path is the only audited data-egress path**, and it carries ciphertext to infrastructure you control. The honest scope of this claim is in §6 — a general-purpose desktop also runs a browser, so the guarantee is "the sync path is the audited egress and it is end-to-end encrypted to your infra," not "no byte ever leaves."
4. **Sovereign sync (the ecosystem).** Opt-in KOOMPI.Cloud (self-hosted) + Selendra (identity/ownership/keys). Data ownership becomes literal: keys you hold, infra you run.

### Why "we have AI" is explicitly NOT the moat

Cloud LLM chat (Gemini, OpenAI, Mistral, DeepSeek, GLM, MiniMax, Kimi) is inherited from upstream and is **commodity** (`Ai.qml`): the APIs are swappable and the integration is generic. A chatbot sidebar is not defensible. The defensible ground is the **combination** — local data fabric + local agent + code-enforced ownership — which is structurally hard for a Big-Tech assistant to match because their business model is the egress KOOMPI forbids by default.

---

## 4. Current State (honest)

KOOMPI OS today is a **production-quality reskin of end-4/dots-hyprland on Arch + an archiso skeleton + a code-complete restore stack**, with a **commodity chatbot** standing in for the assistant. The distance between this and §1 is the entire program of work.

### Desktop base — production-grade
The Hyprland/Quickshell editor and KDE edition are end-4's proven stack, rebranded. Real assets ship (wallpapers, logo). Package structure verified: `koompi-base` (DE-agnostic), `koompi-hyprland-config` / `koompi-kde-config` (to `/etc/skel`, mutually exclusive), `koompi-desktop-hyprland` / `koompi-desktop-kde` edition metas (`docs/os-build.md` §2).

### The assistant — a chatbot sidebar, not the foundation
The single `Ai.qml` Quickshell singleton (~969 lines) wires 7 cloud models + Ollama auto-discovery (`localhost:11434`), a `/`-command chat (`AiChat.qml`), curl-streamed HTTP, JSON-persisted chat, and tool-calling (`get_shell_config`/`set_shell_config`/`run_shell_command`) with a user-approval gate. Verified gaps that block turning it into L2:
- **Cloud is the default, not local.** `Config.qml:84` ships `property int ai: 1` (`0`=off, `1`=cloud+local allowed, `2`=local-only). The local-first thesis requires `2`.
- **The privacy gate is a UI check, not enforcement.** It lives only at model selection (`Ai.qml:544`) and uses a **spoofable** substring test, `model.endpoint.includes("localhost")` — it does not guard the request path, and a hostile endpoint like `localhost.attacker.com` passes.
- **The approval gate is one-tool-deep.** Only `run_shell_command` sets `functionPending` for approval (`Ai.qml:882`); **`set_shell_config` executes immediately, ungated** — it calls `Config.setNestedValue(key, value)` at `Ai.qml:873`, which means the model can rewrite arbitrary shell config (including `policies.ai`) with no consent.
- **No external trigger surface.** `Ai.qml` has **no `IpcHandler`** (every sibling service has one), so nothing — a systemd timer, another app — can invoke the assistant. L4 automation is architecturally blocked.
- **The local default can't act.** The OpenAI-format strategy has **no tool-call parse branch**, so the on-device Ollama default is a dumb chatbot. (And note: Ollama's openai-compat endpoint drops tool calls while streaming — the real fix routes the local path through Ollama's native API, not "add a branch to the openai strategy.")
- **No RAG, no memory, no L1.** Chat is flat JSON with no schema version; nothing indexes, embeds, or retrieves anything.

### The thinks stack (L1–L4) and the ownership plane — ~0% built
No data fabric, embeddings, semantic search, knowledge graph, app bus, automation engine, or sync/identity code exists anywhere in the tree (verified). Persistence is plaintext JSON via Quickshell `FileView`; API keys are in the FDO Secret Service.

### Restore / semi-immutable stack — code-complete + wired, never executed
Every restore step is implemented and called in `installer/src/post_install.sh main()` (snapper, snap-pac, grub-btrfs, pinned read-only `@baseline`, the offline `/home`-wipe unit). It has **never run on real hardware.** Two legs are explicitly open: (1) `grub-mkconfig` bakes `rootflags=subvol=@` onto the kernel cmdline, which can override the btrfs default-subvolume flip and make a rollback a **silent no-op** (the fstab leg is closed; the GRUB leg is not); (2) `setup_snapshot_boot()` skips the `grub-btrfs-overlayfs` hook under the `systemd` mkinitcpio hook, so `@baseline` boots **read-only** on (likely encrypted) installs until reconciled. A snapshot-ID guard makes a no-op `--full` boot fail SAFE, but VM verification is required.

### Installer / ISO / repo — three open ship-gates
- **G1 — Installer doesn't execute.** Zig 0.16 TUI compiles and walks its state machine, but the archinstall exec is stubbed (`main.zig`), the Review gate is a TODO, disk enumeration is a placeholder, and the `disk_config` JSON is a **hand-written shape template with fake UUIDs** that archinstall silently ignores. libvaxis was dropped while the event loop is stubbed.
- **G2 — Installer not on the ISO.** `packages.x86_64` has `koompi-installer` commented out; a v1 build boots to a root shell.
- **G3 — `[koompi]` repo unpublished.** The signed repo has a TODO GPG key + publish URL; nothing can install `koompi-*` packages, which blocks shipping every new daemon the thinks stack needs.

### Subvolume layout (the L0/L1 coupling)
`archinstall.zig:125-129` defines **five** subvolumes: `@ @home @var_log @var_cache @snapshots`. There is no 6th **system** subvolume (and must not be); the per-user index lives in a **nested subvol under `@home`** created at account setup — a different category (§5.0). Live ISO locale is `C.UTF-8`; installer locale hardcodes `en_US.UTF-8`.

### Tests / CI — none
Zero test files in the repo; no `zig build`/`zig test` in any workflow; no AI eval/golden/red-team harness; CI sign+publish is commented out. For an OS that indexes untrusted content and can run shell commands, the **absence of a prompt-injection regression corpus** is a first-order gap (§5.6).

---

## 5. Product Pillars & Functional Requirements

Seven pillars, mapped to the layer model (L0–L4) plus the cross-cutting model, privacy/ownership, and i18n planes. Requirements are functional (WHAT/WHY); the HOW lives in the layer designs and `docs/data-ownership.md`. FORK B means **all of L0–L4 and the planes are scoped here**; §7 then carves the v1 slice. Where a layer design was over-optimistic, the FR reflects the **critique-corrected** state.

### 5.0 The one storage decision (resolve once; every pillar references it)

The L1 index DB holds **extracted plaintext chunks and invertible embeddings** of the user's documents/mail/chat. That single fact collapses three competing proposals (a system subvolume that survives restore; `@home`; a separate `@data` subvol that `--full` skips):

- **FR-S1.** The index/knowledge-graph/memory store lives **per-user under `@home`** as a **per-user nested btrfs subvolume** (`~/.local/state/koompi/...`), `nodatacow` via `chattr +C` on the empty subvol before the DB is created (SQLite on btrfs CoW fragments badly), and **excluded from `@home` snapshots** (a rebuildable GB-scale cache must not bloat rollback points). It is **NOT** a system `/var/lib` store and **NOT** a 6th *system* subvolume — a per-user nested subvol is a different category, created at account setup, and `--full` wipes it.
- **FR-S2.** Consequence — **`--full` factory reset wipes the index** along with `@home` (required: a separate store would leak the prior user's plaintext to the next person; this is the confidentiality guarantee). **System Restore keeps `@home`**, so files and their index stay consistent. **Corruption is recovered by rebuild from source**, not rollback (the index is a derived cache).
- **FR-S3.** Because System Restore reverts `@` (the daemon binary, the extension, the embedding model, the schema) while `@home` stays forward, the daemon **must** detect daemon-vs-schema skew on start and **forward-migrate or rebuild**, never silently corrupt. This also covers the rolling-distro case where `pacman -Syu` updates the daemon/extension/model independently of the on-disk schema. This migration story is owned **here**, not deferred (§5.6).

### 5.1 Installable, recoverable semi-immutable base (L0)
- **FR-A1.** The installer must execute a real install: wire a real libvaxis 0.16 event loop, real block-device enumeration, gate the destructive archinstall exec behind an actual Review keypress, and replace the fake-UUID template with a `disk_config` generated from a **pinned** archinstall release (`--dry-run`/save-config); let archinstall mint the UUIDs.
- **FR-A2.** Hold the install password in a zeroed/locked buffer wiped immediately after credential write (today it is a plain borrowed slice never zeroed). Root stays locked; admin via a verified sudo-group user.
- **FR-A3.** Package `koompi-installer` and `koompi-restore`, place the installer on the ISO, and pull `koompi-restore` into `koompi-base` so factory reset ships on every install (today the restore binary has no package and its offline `/home`-wipe unit is dead code).
- **FR-A4.** Publish the **signed** `[koompi]` repo (real RSA-4096 key as a CI secret with a documented rotation/revocation plan; a decided publish target; ship the pubkey + `pacman-key` import on the ISO). Add `zig build` + package builds to CI.
- **FR-A5.** Run and **VM-verify** the restore lifecycle end-to-end: close the GRUB `rootflags=subvol=@` leg (strip it or route restore exclusively through grub-btrfs menu entries), reconcile the `grub-btrfs-overlayfs`-vs-`systemd`-hook conflict (force the udev hook on the KOOMPI default incl. LUKS, or document read-only snapshot boots), and verify the asymmetric-reset guard. **`--full` must be VM-tested WITH an encrypted index present** so the confidentiality guarantee (FR-S2) is proven, not assumed — until then `--full` ships disabled or warn-and-abort.
- **FR-A6.** Add a `koompi-restore` polkit action + a Settings GUI button so factory reset is self-service, not root-shell-only.

### 5.2 The Context Engine — the data fabric (L1)
The on-device knowledge layer. This IS "never find files again."
- **FR-L1-1.** A per-user daemon (`systemd --user`) watches a configured scope (default `~/Documents`, `~/Downloads`, `~/Desktop`, notes/todos; opt-in mail/chat) via inotify with debounce and an exclusion list (the index dir itself, `.git`, caches, `.snapshots`, `/tmp`, ignore-file honoring).
- **FR-L1-2.** Per-MIME extraction to UTF-8 in **killable subprocesses** (text/markdown/code native; PDF via poppler; office via pandoc; OCR via tesseract incl. Khmer). Failures are per-file isolated.
- **FR-L1-3.** Sentence-aware chunking; embeddings via a **local** model (Ollama `/api/embed`); content-hash dedup to skip unchanged chunks (incremental).
- **FR-L1-4.** Store in **one SQLite DB** (per FR-S1): `sqlite-vec` vectors (the settled default — MIT/Apache, single C file, bit-quantization), FTS5 keyword index, metadata, and a knowledge-graph (entities/edges from cheap metadata first; LLM NER later). Schema is **version-stamped with `model_id` + embedding dimension** so a model change triggers a managed re-embed, not silent corruption.
- **FR-L1-5.** Hybrid query (vector KNN + FTS5 BM25, RRF-fused, metadata-filtered) over a session/D-Bus API returning ranked snippets **with source attribution**.
- **FR-L1-6.** Resource-bounded: run inside a systemd slice (`CPUQuota`, `MemoryHigh/Max`, `IOSchedulingClass=idle`, `Nice`); **power/thermal-aware** (the first-run full-corpus crawl and bulk re-embed are gated on idle, but the initial crawl must be allowed to make progress on battery at deep idle priority, or it never completes on a laptop).
- **Honesty:** `sqlite-vec` KNN is **brute-force O(n)**, not ANN. The index is scoped to the user's relevant corpus; for very large corpora an optional heavier tier (LanceDB OSS — Apache-2.0 lib, but open-core, never the default) is a documented escape hatch. Do not claim ANN scaling.

### 5.3 The Assistant — AI as foundation (L2)
Extend the existing `Ai.qml`, but move the agent runtime out of the GUI.
- **FR-L2-1.** Extract the agent runtime into a **per-user service** (`systemd --user`); `Ai.qml` becomes a thin client. Required because L4 automation runs headless and L3 apps call the assistant as a service; the dangerous tool executor belongs in one auditable boundary.
- **FR-L2-2.** **Isolate conversation state.** Today `Ai.qml` is a singleton with one shared conversation/model/tool buffer; a headless run would clobber the user's live chat. A conversation must be an object so headless and interactive runs don't collide. (Prerequisite for L4.)
- **FR-L2-3.** RAG: retrieve from L1 before/within a turn, inject snippets + provenance into context, record sources for display.
- **FR-L2-4.** A bounded agent loop (plan→act→observe) with hard iteration/token/wall-clock budgets and **tool-result validation** (nonzero exit / stderr / empty output fed back so the model can retry or abandon — today exit code is appended and the loop blindly continues).
- **FR-L2-5.** Cross-session + long-term memory in the L1 DB (rolling summaries + durable user facts), with a user-visible **view/edit/delete** surface (memory hygiene).
- **FR-L2-6.** Enable local tool-calling via the **native Ollama API path** (not the openai-compat streaming path, which drops tool calls). Without this the local-first default has no agency.
- **FR-L2-7.** Local model is the default; cloud is BYO-key opt-in routed through the privacy chokepoint (§5.5). A deterministic **capability ladder** degrades on low RAM — and the degraded path **must NOT silently fall back to cloud** (that would invert the moat for its own target user); it must either run reduced-local or refuse with a clear, consented prompt.

### 5.4 The App-context bus — apps talk to each other (L3)
- **FR-L3-1.** A per-user broker daemon owns a D-Bus name and mediates an MCP-shaped schema (resources/tools/intents). Apps register a small provider interface; consumers (the assistant) never bind apps directly. (Quickshell can consume D-Bus but cannot export it, so the QML shell talks to the broker over a unix socket while the broker owns the bus.)
- **FR-L3-2.** **Capability tiers owned by the broker, not self-declared by apps:** READ (auto), WRITE (confirm), DANGER (always confirm + sandbox). Externally-registered tools are never auto-allowed regardless of how they self-describe.
- **FR-L3-3.** Every mediated call is JSON-schema-validated and written to an append-only, tamper-evident audit log.
- **FR-L3-4.** Legacy/sandboxed apps participate via `xdg-desktop-portal` intent mapping and `.desktop`-derived intents, so the "email this file → draft + attach" flow works whether a native provider, an adapter, or only a portal MUA is present.
- **FR-L3-5.** A **stated threat model:** the bus defends against the confused-deputy assistant and cooperative apps, **not** against malicious same-UID code (same-UID has no kernel isolation). Genuine isolation of sensitive providers (mail/contacts/index) requires sandboxing (portals / separate UID), which is the path to make the gates real rather than advisory.

### 5.5 Privacy / ownership plane — local-first, code-enforced (FORK A)
The plane spanning L0–L4 that makes the moat true.
- **FR-P1 (flip the default).** Ship `policies.ai = 2` (local-only) and add `policies.sync = 0` (off). Today's `ai: 1` default makes the local-first claim false out of the box.
- **FR-P2 (real enforcement point).** Egress enforcement must be **architectural, not advisory**: a **root-owned** mechanism (network namespace + nftables allowlist permitting only `localhost:11434` and the named sync host when policy is local-only) so a user-process `curl` — or `run_shell_command`'s `bash -c` — **physically cannot** reach arbitrary hosts. A session-bus policy daemon that components voluntarily consult is necessary for UX but is **not** the isolation boundary. Replace the spoofable `includes("localhost")` check with a parsed-host allowlist.
- **FR-P3 (gate every tool uniformly).** `set_shell_config` gets the same approval gate as `run_shell_command` and a protected-key denylist so the tool path can never write `policies.*` or other security keys. `run_shell_command` runs inside an unprivileged-namespace **sandbox** (read-only system, no network by default, rlimits), not bare `bash` with full ambient authority.
- **FR-P4 (encryption at rest).** On-device envelope encryption (per-object DEKs, master key custodied in the keyring, PAM-unlocked, optional TPM2 seal), with the keyring-unlock leak fixed (fd-passing / systemd password agent instead of `echo password | …`). Honest scope: at-rest encryption defends **offline device theft**; it does **not** defend against malicious same-UID code while the session is unlocked (that needs the sandboxing in FR-L3-5/FR-P3).
- **FR-P5 (cloud egress is double-gated and consented).** A cloud call requires `policies.ai = 1` **and** a BYO key **and** a passing egress check; sending **RAG snippets or file attachments** to a cloud model is a **separate, off-by-default** opt-in from cloud chat, with a per-turn consent showing the literal destination, and the key fetched only after the egress check passes.
- **FR-P6 (per-user isolation).** Per-user keyring scope, per-user index namespace, per-user policy. An admin/parent policy **floor** must live where factory reset cannot revert it (a system-floor in `@` is wiped to baseline by `--full`).
- **FR-P7 (verifiable, honestly scoped).** A user-visible **append-only egress ledger** (object id, time, ciphertext size, destination) makes "what left my machine" falsifiable. The claim is **"the sync path is the only audited data-egress path and it carries E2EE ciphertext to infra you control,"** not "no byte ever leaves" — a general desktop also runs a browser.
- **FR-P8 (opt-in sovereign sync).** KOOMPI.Cloud (self-hosted, zero-knowledge ciphertext + encrypted CRDT op-log for structured data via Automerge; large blobs content-addressed; **the binary index is never synced — each device re-embeds from synced source**) and Selendra (DID, device pubkeys, key rotation/revocation, **periodic salted-commitment Merkle roots over the manifest** — never `hash(plaintext)`, never per-operation). QR device-pairing with an out-of-band verification step; optional zero-knowledge recovery escrow with a documented "lose password + all devices = data gone" outcome; migrate-before-`--full` UX-enforced.

### 5.6 Quality, testing, migration, accessibility (cross-cutting, ownerless today)
- **FR-Q1 (tests/CI).** Add `zig build`/`zig test` to CI; a VM harness for the restore lifecycle (run **with an encrypted index present**); a tool-call/RAG golden suite against the pinned local model; and a **prompt-injection regression corpus** (poisoned doc/email/PDF fixtures) that runs in CI — the single most important test category for this product class. Injection mitigation must ship **with** local tool-calling, never a phase later.
- **FR-Q2 (migration).** A forward-only, version-stamped, idempotent/resumable schema+model migration runner (per FR-S3), correct against partial updates + power-cut, and against post-System-Restore daemon/schema skew.
- **FR-Q3 (accessibility).** Font scaling, contrast, reduced-motion in the shell; the security consent/approval surface reachable by keyboard-only and assistive tech on **both** editions; assess Wayland/Orca/at-spi reality for Hyprland and KDE; treat the assistant's text/voice path as an accessibility affordance.
- **FR-Q4 (packaging/orchestration).** Own the cross-component dependency graph and the systemd-unit / D-Bus-activation **ordering** of the ~5 new daemons (all gated on `[koompi]`/G3), plus model **weights** as distributable artifacts with a license-verified pin (§5.7) and an **offline-seed / LAN-mirror** path so a fresh or low-connectivity install has a working local assistant without a multi-GB first-boot pull.

### 5.7 Model plane — local-first, license-clean
- **FR-M1.** Local Ollama is the on-device default for chat and embeddings; cloud is BYO-key opt-in.
- **FR-M2.** Default the **clean-license TIER**, not a single family. Pin exact model + quant per RAM tier at build, **verifying each model's actual LICENSE file** (not SEO claims). Reject non-OSI/use-restricted weights as bundled defaults: Qwen2.5-3B (research/non-commercial), Gemma custom terms, Llama MAU clause. Safest-attested candidates to evaluate: **Sailor2 / SEA-LION** (Apache/MIT, SEA incl. Khmer) for chat; **BGE-M3** (MIT, explicit Khmer) or nomic-embed (Apache) for embeddings.
- **FR-M3.** A local "reasoning model" tier is **cut** for v1 — no usably-small reasoning model fits the floor; reasoning routes to cloud opt-in. Embedding dimension is decoupled from the schema so model choice is a managed re-embed, not a destroy-everything.

### 5.8 Khmer + English — first-class, English default (FORK C)
Ship Khmer as an **atomic unit** or not at all — a half-built language is worse than English-only (tofu boxes, or search that silently fails).
- **FR-I1.** `km_KH.json` (matching the existing per-locale schema) **+** a `Translation.tr` fallback chain `km_KH → en_US → key` **+** `noto-fonts-khmer` + fontconfig fallback **+** XKB `km` layout with an fcitx5 switcher (reject `fcitx5-unikey` — that is Vietnamese) **+** session IM-environment wiring (Hyprland Wayland IM + env; KDE native) **+** ICU dictionary word-segmentation for L1 lexical search (Khmer has no inter-word spaces) **+** a Khmer-capable **embedding** model for semantic search. Gate the locale on a coverage threshold (e.g. 95%); fix the malformed `he_HE` → `he_IL` while touching locales.
- **FR-I2.** Installer offers Khmer in a locale picker (English default); writes `/etc/locale.conf` + `/etc/vconsole.conf`; live ISO locale set to `en_US.UTF-8` so the pre-install session renders.

### 5.9 Automation — morning automated (L4)
- **FR-L4-1.** Durable triggers via `systemd --user` `.timer`/`.service`/`.slice` (`OnCalendar`, `Persistent=true` for overnight catch-up, `ConditionACPower`, `RandomizedDelaySec`, resource caps) — chosen over a QML timer because it survives shell restarts and catches up after power loss.
- **FR-L4-2.** A thin runner invokes the assistant via the **new `Ai.qml` IpcHandler** (the prerequisite — today absent), with run-id idempotency, `flock`, and an fsync-gated completion marker (sync-barrier discipline) so a power cut yields exactly one run.
- **FR-L4-3.** A **separate unattended execution mode** with default-deny write/danger capabilities: the interactive human-approval gate is meaningless at 6am, so headless runs are READ-only unless the user explicitly granted a capability to that specific automation; tool calls from non-interactive triggers are never auto-executed.
- **FR-L4-4.** The flagship daily briefing (calendar + mail + notes/todos + RSS → local summarization → notification + sidebar card + markdown digest), fully local by default, degrading and labeling missing sources.
- **FR-L4-5.** A Settings → Automations surface (discover/enable/run-now/edit-grants/view-history); opt-in only, nothing auto-enabled; run-history is the audit ledger for "what did my automations do, did anything leave."
- **Honesty:** `qs ipc` requires the shell alive and is Quickshell-only — so the briefing engine is the **headless flow-runner** (Ollama + sqlite-vec + D-Bus, no shell), which makes it **edition-agnostic**. Settled (§7; ADR-0007): the KDE edition gets the briefing in v1.

---

## 6. Non-Goals

- **Not surveillance-funded AI.** No analytics or chat telemetry by default. `telemetry=none` is **policy-enforced in v1**; it becomes *architecturally* **no phone-home path** only once the root-owned netns/nftables enforcement (P-2) lands (**1.x**) — v1 does not overclaim it as structural (see the bounded claim below, FR-P7).
- **Local-first is not a UI toggle.** Egress enforcement is code/kernel-level (FR-P2); a session-bus policy daemon alone does not isolate.
- **The "nothing leaves your machine" claim is bounded.** It means the **sync path is the only audited data-egress path** (FR-P7), not that a general-purpose desktop with a browser emits zero packets. We will not overclaim.
- **The index is not a sync product and not survive-restore state.** It is a per-user derived cache under `@home`, wiped by `--full`, rebuilt on corruption (FR-S1/S2). No separate subvolume outlives the user.
- **Factory reset is not backup/sync.** `koompi-restore` reseeds from `@baseline`/`/etc/skel`; no selective recovery, no version history, no scheduled/remote/fleet wipe in v1.
- **No unsandboxed agentic shell.** `run_shell_command` is sandboxed and consent-gated; automation contexts hold no danger/write capability by default.
- **No cloud egress of private data without explicit, separate consent.** Cloud chat ≠ shipping your indexed files to the cloud; the latter is its own off-by-default opt-in (FR-P5).
- **No dual-boot / unknown-hardware partitioning in v1.** Targets the supported install path; arbitrary-disk, multi-OS, shrink-partition flows are out of scope.
- **The shell is not re-implemented.** KOOMPI tracks end-4 upstream and diverges on identity + the thinks stack (`UPSTREAM.md`).
- **No multi-distro packaging.** Arch-only; v1 = Arch + archiso.
- **Khmer is not the positioning.** It is a first-class feature of a global product; English is the default.

---

## 7. Scope & v1 (Naga) Definition + phasing recommendation

**v1 name:** KOOMPI OS — Naga (technical 1.0; in-era updates 1.1, 1.2 keep the Naga name until Apsara). KOOMPI is **rolling Arch**, so "v1" is a quality bar — capability-gated, not event-gated — not a frozen point-release — which is exactly why the migration runner (FR-Q2) is load-bearing.

### The prefix every feature depends on (must land first)
A "make-it-safe-and-true" base the critiques converge on, before any L1–L4 feature:
1. **Flip the privacy default** — `policies.ai = 2`, add `policies.sync = 0` (FR-P1; one-line change with large payoff).
2. **Gate `set_shell_config`** like `run_shell_command` + protected-key denylist; **fix the spoofable localhost check** (FR-P3, FR-P2).
3. **Fix storage location** — index per-user under `@home`, `chattr +C` (FR-S1).
4. **Ship a fail-closed policy stub** so downstream layers code against the enforcement contract from day one.
5. **Isolate `Ai.qml` conversation state** (FR-L2-2) so headless automation can't clobber live chat.
6. **Close G1/G2/G3 + the restore legs** (GRUB `rootflags`, overlayfs hook) and **VM-test `--full` WITH an encrypted index present** (FR-A1…A5).

### Phasing recommendation (FORK B architecture, demo-carved)
- **P0 — Safe base + local agency:** the prefix above; native-Ollama local tool-calling (FR-L2-6); pin + license-verify the default model tier (FR-M2); a fail-closed policy stub.
- **P1 — L1 core ("never find files again"):** the Context Engine over a few folders (text/PDF/OCR), hybrid query with source attribution, fully local — the headline thesis beat.
- **P2 — L2 RAG + memory + safety:** RAG into the agent loop, two-tier memory, the bounded loop + result validator, the sandbox for `run_shell_command`, the multilingual layer; **prompt-injection mitigation ships with tool-calling, not after** (FR-Q1).
- **P3 — L3 bus + L4 briefing (the demo's "apps talk / morning automated"):** the broker + one pilot provider (calendar/files), the `Ai.qml` IpcHandler, a fully-local morning briefing.
- **P4 — Ownership/sync plane:** on-device encryption-at-rest first (the privacy default, zero cloud); then opt-in KOOMPI.Cloud backup + DID; then multi-device CRDT sync + QR pairing; then Selendra anchoring + the egress-audit UI. No sync code ships without a written protocol + encryption-in-transit spec.

**Minimal coherent v1 (if scope must shrink):** P0 + P1 (RAG over a few folders, local model) + a slice of P3 (the morning briefing) — that alone delivers the three thesis beats (*never find files again*, *AI as foundation*, *morning automated*) **fully local**, without the complete L3 bus or the sync plane. The complete L0–L4 + planes remain the documented architecture (FORK B); the minimal cut is a slice of it, not a shrink of it.

**Out of scope for v1:** a software store, fleet management, a multi-device sync UI beyond single-device backup, Selendra anchoring on the critical path, and any heavier (LanceDB) vector tier. **Settled scope decision:** the morning briefing is **edition-agnostic** (daemon-side headless `Ask()`, not shell-specific), so the **KDE edition gets it in v1** alongside Hyprland/Quickshell — see ADR-0007.

---

## 8. Success Metrics

No metric below has been measured (the installer has never executed; the thinks stack does not exist). Design intents are stated; every numeric target is **(TBD / to validate)** with the KOOMPI team.

| Metric | What it measures | Target |
|---|---|---|
| Privacy default | Ships `policies.ai = 2` + `policies.sync = 0` | **Design intent: yes** (FR-P1); base ships `ai: 1` today |
| Egress enforcement | Local-only blocks non-allowlisted egress at the kernel layer, not the UI | **Design intent: yes** (FR-P2); today UI-only + spoofable |
| Uniform tool gating | `set_shell_config` and `run_shell_command` both gated; sandboxed shell | **Design intent: yes** (FR-P3); `set_shell_config` ungated today |
| Install success rate | Clean installs that boot to desktop | (TBD) — installer never executed |
| Restore lifecycle pass | VM + hardware verify of `@baseline`, grub-btrfs, rollback, **`--full` with encrypted index** | (TBD) — currently 0; never run |
| Hand-off data-leak | Confidential data (incl. index plaintext) remaining after `--full` | (TBD; intent = zero) |
| Retrieval quality | Hybrid query precision/recall on a golden set (incl. Khmer) | (TBD) — no index yet |
| Prompt-injection resistance | Poisoned-content fixtures that drive a tool call / egress | (TBD; intent = zero un-consented actions) — no corpus yet |
| First-crawl completion | Full-corpus index completes on the hardware floor | (TBD) — gated on hardware specs (§11) |
| Local agency | On-device model can call tools via native Ollama path | (TBD) — no branch today |
| Khmer UI coverage | % UI strings in `km_KH`, gated for enablement | (TBD) — currently 0% |
| Egress ledger fidelity | Every cloud/sync egress recorded, user-auditable | **Design intent: complete** (FR-P7) |
| Adoption | Installed base / reach | (TBD) — see §11 |

---

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Prompt-injection → tool execution (the #1 risk of this product class).** Untrusted indexed mail/PDF enters RAG context; the model proposes a destructive/exfil command; one habituated approval click runs it. Absent from every layer design's threat model. | Tag RAG content as **untrusted, non-instruction**; separate read-tools from act-tools; force **fresh consent** for any act whose args derive from retrieved content; sandbox `run_shell_command`; ship a **prompt-injection regression corpus** in CI **with** tool-calling (FR-Q1, FR-P3, FR-L3-2). |
| **"Sole egress chokepoint" is advisory and forgeable**, and moot while a tool runs `bash -c`. | Make enforcement **root-owned** (netns/nftables allowlist) + sandbox the shell tool; the session-bus daemon is UX, not isolation (FR-P2/P3). |
| **Privacy default inverted** (`Config.qml:84` `ai:1`) — local-first is false out of the box. | Flip to `2` + add `policies.sync=0` as part of the P0 prefix (FR-P1). |
| **4GB floor can't run chat+embed locally** once all daemons + Ollama + both models are summed; silent cloud fallback would invert the moat. | Honest capability ladder; degraded path is reduced-local or a consented refusal, **never silent cloud** (FR-L2-7); sum the real footprint per tier (FR-Q4). |
| **Index/schema skew on every rollback + continuous rolling updates.** System Restore reverts the daemon while `@home` keeps the newer schema; `pacman -Syu` updates components independently. | Version-stamp schema+model_id+dim; forward-migrate-or-rebuild on skew; idempotent/resumable against partial-update + power-cut (FR-S3, FR-Q2). |
| **`--full` silently no-ops (open GRUB leg)** → next user inherits prior user's plaintext index + invertible embeddings. | Close the GRUB leg, VM-test `--full` **with an encrypted index present**, ship `--full` disabled until verified (FR-A5). |
| **Model-weight license** — Big-Tech "open" weights carry strings (Qwen research, Gemma terms, Llama MAU). | Pin a clean-license **tier**, verify each LICENSE file at build, reject use-restricted weights as defaults (FR-M2). |
| **`[koompi]` repo single point of failure / unpublished (G3)** blocks shipping every new daemon. | Real key as CI secret + documented rotation/revocation + backup mirror; decide publish target before flipping sign+publish (FR-A4). |
| **Half-shipped Khmer** = tofu boxes or silently-failing search. | Ship the six legs (translation+font+input+IM-env+segmentation+embedding) atomically, gated on coverage (FR-I1). |
| **Selendra anchoring has a gas cost** — paying tokens to anchor proof of your own data is an economic "string" and an onboarding blocker. | Make anchoring optional/non-blocking with a zero-blockchain default; if subsidized/relayed, document the centralization tradeoff (FR-P8, §11). |
| **No tests / CI** for installer, restore, or the AI system. | Add `zig build`/`zig test`, the restore VM harness, RAG/tool golden sets, and the injection corpus as a hard gate before the thinks stack lands (FR-Q1). |
| **Accessibility unaddressed** across the stack. | Add the a11y track (FR-Q3) before GA. |

---

## 10. Dependencies & Sequencing

- **Hard prefix → all features:** the P0 safe-base prefix (§7) gates every L1–L4 pillar.
- **L0 → everything:** G1 (installer executes) → G3 (signed repo) → G2 (installer on ISO); FR-A5 (restore VM-verify) depends on FR-A1. The thinks-stack daemons cannot ship until G3 publishes the repo.
- **L1 → L2 → L3/L4:** the data fabric (L1) is the substrate for RAG (L2), the bus (L3), and automation (L4). Index storage (FR-S1) gates all of them and must be decided before L1 code.
- **Planes are cross-cutting:** the privacy/ownership plane (§5.5) and the model plane (§5.7) underpin every layer; the policy enforcement point (FR-P2) and a fail-closed stub must exist before L1–L4 call it.
- **Dependency licenses (verified 2026-06-07):** `sqlite-vec` (MIT/Apache, default vector index), SQLite/FTS5 (public domain), Ollama/llama.cpp (MIT), Automerge (MIT), libsodium (ISC), BGE-M3 (MIT). **Flagged:** LanceDB OSS is Apache-2.0 but **open-core** → optional heavier tier only, never the default. **Model weights** are first-class dependencies and must be license-verified per FR-M2. Run a transitive license scan (`cargo deny`) in CI.

Execution detail and the current restore stack live in [`docs/roadmap.md`](roadmap.md); build/package architecture in [`docs/os-build.md`](os-build.md); the ownership/sync plane in [`docs/data-ownership.md`](data-ownership.md).

---

## 11. Open Questions

Genuine unknowns the repo does not answer; resolve with the KOOMPI team and ecosystem partners.

**Hardware floor (gates the whole local-first story)**
- What are the supported CPU/RAM/storage specs and the guaranteed **minimum** ("the floor")? This gates the default model tier, the throttle limits, whether chat + embeddings can coexist locally, and the first-crawl completion target. If the floor cannot run agentic-local, the honest answer (reduced-local or consented refusal, never silent cloud) must be designed in, not patched later.

**Model plane**
- Exact default chat + embedding model pin and quant per RAM tier — **verify each LICENSE file at build**, do not assert from secondary sources.
- Khmer chat/embedding **quality** vs the RAM budget — Khmer-strong models live in larger tiers that may not fit the floor; is "first-class Khmer" on the floor effectively weak-local-or-cloud-opt-in?

**Ownership / sync ecosystem**
- Who **hosts** KOOMPI.Cloud for non-technical users — a KOOMPI-run instance (which weakens "infra you control") vs user/school-hosted? Positioning-critical.
- Selendra capability (native DID pallet vs EVM/ink! registry), finality, and **per-tx gas economics** — and whether KOOMPI subsidizes/relays anchoring or users pay (the economic string in §9).
- Recovery-escrow default (on-with-printed-code vs strict opt-in) — determines how many users hit the "data gone" outcome.
- Confidentiality boundary + a written **privacy posture / consent framework / data-collection matrix** (general, incl. any minors using the OS) — the moat's governance artifact, owned by no layer today.

**Restore / migration**
- The decided fix for the GRUB `rootflags=subvol=@` leg (strip vs route through grub-btrfs); LUKS↔overlayfs-hook interaction; and VM-verification of `--full` with an encrypted index present.

**Infrastructure / packaging**
- `repo.koompi.org` ownership, signing-key custody, hosting/SLA/mirror; the offline-seed / LAN-mirror path for model weights on low-connectivity installs.
- libvaxis 0.16 compatibility (a pinned commit that compiles clean) and whether Zig 0.16 + libvaxis is a stable installer baseline.

**Product / scope**
- ~~Is the KDE edition co-first-class for the thinks stack and the morning briefing in v1?~~ **Settled (§7; ADR-0007):** yes — the thinks stack is daemon-based and the briefing runs on the headless flow-runner, both edition-agnostic, so KDE is co-first-class in v1.
- Translator + Khmer-QA resourcing and the coverage threshold to enable `km_KH`.
- Accessibility baseline for GA (Wayland/Orca/at-spi reality on Hyprland and KDE).
- Release-era naming (currently Khmer-mythology codenames, `docs/naming.md`) — keep as neutral internal codenames or move to a region-neutral scheme now that the product is positioned globally.
