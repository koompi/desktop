# KOOMPI OS — Execution Roadmap

**Date:** 2026-06-07
**Repo:** `~/workspace/koompi-desktop` (canonical) — github.com/rithythul/koompi-desktop
**North Star:** KOOMPI OS — "The OS That Thinks." AI-first, data-aware, intuitive;
a general-purpose OS for the world. (`docs/prd.md` is the product spec; this is the
build plan.)
**Method:** every file:line claim below was re-verified against the live tree on
2026-06-07. Where the older Cambodia/education roadmap was wrong about the *product*,
this rewrite inverts it (per the settled 2026-06-07 decisions); where it was right
about the *code*, it carries the evidence forward.

> **This roadmap replaces the old A/B/C "Cambodia tracks."** That framing — "the one
> real moat is regional/education," "AI is explicitly NOT the moat," "AI deferred to
> the last phase" — is **dead and inverted.** KOOMPI OS is now AI-first and
> general-purpose; the moat is *the thinks-stack + local-first ownership*; Khmer is a
> **feature** (two first-class languages: English default, Khmer included), not the
> positioning. The canonical PRD has been rewritten to match; **`docs/prd.md` is now
> AI-first.** Architecture depth for each layer lives in the layer design docs
> (referenced inline); this doc is the **sequenced, verifiable build plan**, not a
> re-statement of those designs.

---

## 1. Verdict (honest)

**Today KOOMPI OS is:** a well-built reskin of end-4/dots-hyprland (illogical-impulse)
on Arch + a commodity cloud-chatbot sidebar + a code-complete-but-**untested** btrfs/
snapper restore stack. That is the whole of it.

- **The "thinks" layer is ~0% built.** No index, no embeddings, no semantic search, no
  knowledge graph, no app-bus, no automation. The vision ("never find files again,"
  "apps talk to each other," "morning automated") is entirely unbuilt. The assistant is
  `Ai.qml` (a ~969-line Quickshell singleton) wiring 7 cloud models + Ollama
  auto-discovery, with chat persisted as flat JSON.
- **It does not yet install itself.** Three ship-gates are open: **G1** the installer
  does not execute (archinstall exec stubbed), **G2** the installer is not on the ISO
  (`packages.x86_64` has `#koompi-installer` commented out), **G3** the signed
  `[koompi]` repo is unpublished. A v1 build today boots to a root shell.
- **The restore stack has never run.** It is code-complete and wired into
  `post_install.sh main()` but **VM-untested**, with two open legs (GRUB
  `rootflags=subvol=@`, the overlayfs/systemd-hook conflict) that can silently no-op a
  rollback. Until VM-verified, factory reset is not a feature.

**The gap between vision and code is the entire thinks-stack plus a substrate that does
not yet boot.** Nothing here is a dead end — the engine is solid, the restore stack is
~one stub from running, and the assistant is the right place to grow L2 — but this
roadmap is honest that L1–L4 + the ownership/sync plane + Khmer search are *greenfield*.

**Recommended v1 (ships when it is real — capability-gated, not event-gated):** L0-solid (gates closed, restore VM-tested) +
**L1 context engine** ("never find files again") + **L2 assistant-over-your-data**
(RAG, local-first default). L3 app-bus, L4 automation, Selendra anchoring, and full
multi-device sync are **1.x**. Khmer UI base (render/type/translate) is v1 *if
resourced*; Khmer *search* (ICU segmentation + a Khmer-capable embedder) lands with L1.
See §11 for the v1-vs-1.x line, item by item.

---

## 2. Three settled cross-layer decisions (the load-bearing reconciliations)

The six layer designs each proposed sound architecture in isolation but **contradicted
each other** on three points that gate the whole sequence. These are now **settled**;
every track below references them rather than re-opening them.

### 2.1 Index/data storage — settled: per-user under `@home`, NOT a system subvolume

The L1 index DB holds **extracted plaintext FTS5 chunks + invertible embeddings** of
the user's private files/mail/chat. One constraint collapses the four competing homes
(L0's `@var_index`, L1's `@home`, ownership's `@data`, model-privacy's "TBD"):

> **`--full` factory reset must erase confidential data for clean hand-off → `--full`
> wipes `@home` → therefore the index MUST live where `--full` wipes it.**

**Decision: the index + knowledge graph + L2 memory live per-user at
`~/.local/state/koompi/` (inside `@home`), as a SQLite DB with `sqlite-vec`.** This
single placement satisfies, simultaneously:

- **Confidentiality on hand-off** — `--full` (which wipes `@home`) destroys the
  plaintext chunks + embeddings. A system `@var_index` that `--full` skips would leak
  the prior user's data — rejected.
- **Multi-user isolation** (a first-class case, not the primary deployment — prd §2) — per-`$XDG_STATE_HOME`
  means one student's index/keys are never co-located with another's, and one user's
  `koompi-restore --full` cannot wipe another user's index. A system `/var/lib/koompi`
  store breaks this — rejected.
- **System-Restore consistency** — System Restore reverts `@` and keeps `@home`, so the
  index stays consistent with the source files it indexes (both survive together).
- **Corruption recovery** — the index is a **rebuildable derived cache**; on corruption
  the daemon drops it and re-extracts from source (no independent rollback needed). It
  lives in a **per-user nested subvol** under `@home` (`~/.local/state/koompi`): `chattr
  +C` gives `nodatacow`, and being a nested subvol **excludes it from `@home` snapshots**
  so a GB-scale rebuildable cache never bloats rollback points. Created at account setup;
  the installer's **5 SYSTEM subvolumes are unchanged** (a per-user nested subvol is not a
  system subvol).

**`@var_index` is superseded** — do not add a 6th **system** subvolume to the archinstall
`disk_config` (`archinstall.zig:124-129` keeps `@ @home @var_log @var_cache
@snapshots`). The per-user index nested subvol is created at **account setup**, not in
`disk_config`. The vector index is **never synced** — each device re-embeds locally from
synced source (syncing a binary vector DB is conflict-hell). See `architecture.md` §7
for the schema; `docs/data-ownership.md` for the sync exclusion.

### 2.2 Single egress chokepoint — settled: root-owned enforcement, one decision brain

Four layers each claimed to be "the sole chokepoint." There is now **one system**, three
roles, with the enforcement at a layer a user process cannot bypass:

- **Enforcement (root-owned, mandatory):** a network boundary — `koompi-syncd` runs in
  a network namespace with `nftables` allowlisting **only** `localhost:11434` (Ollama)
  and the named KOOMPI.Cloud sync host. Default-deny for everything else. A user-level
  `curl` or `run_shell_command`'s `bash -c` **physically cannot** reach an arbitrary
  host when policy = local-only.
- **Decision brain (fail-closed):** `org.koompi.Policy`, a D-Bus daemon every data-read
  and egress consults. Unknown caller / unreachable daemon = **deny**. Session-bus
  checks are **advisory UI only** — never the enforcement point.
- **Sole egress process:** `koompi-syncd` is the one process allowed outbound for user
  data. The cloud-LLM path and KOOMPI.Cloud sync are the **only two** egress targets,
  both gated.

> **Corollary that must be sequenced:** `run_shell_command` today runs `bash -c
> <model-string>` as the full user (`Ai.qml`). For the chokepoint to mean anything, the
> shell-exec tool MUST be sandboxed (bubblewrap / `systemd-run` under the same egress
> profile) — see §2.3 and Track P.

### 2.3 Injection-gates-tool-calling — settled: a hard ordering, not a phase

L1 indexes **untrusted content** (mail, downloaded PDFs) → RAG injects it into L2 → L2
has `run_shell_command` → a poisoned document is **one-click RCE / exfiltration**. This
is the defining risk of an OS that "reads all your data and can run shell."

> **The change that enables local-model tool-calling MUST land in the same commit as:
> (a) RAG-content tainting** (retrieved content is data, never instructions); **(b)
> typed confirmation** for destructive/egress commands; **(c) sandboxed exec.** Never
> tool-calling first, mitigation later.

---

## 3. Track map

```
Track G — Ship-gates: make L0 install + update (G1, G2, G3)            [v1, blocking]
Track R — Restore legs: VM-verify the semi-immutable stack             [v1, blocking]
Track P — Privacy/policy chokepoint + safety primitives                [v1, blocking for any agency]
Track L1 — Context Engine: the data fabric ("never find files")        [v1]
Track L2 — Assistant over your data: RAG, memory, safe tool-calling    [v1]
Track L3 — App-context bus ("apps talk to each other")                 [1.x]
Track L4 — Automation ("morning automated")                           [1.x]
Track S  — Subsystem: per-context isolation (Light/App Window/Detonation) + Broker  [wrapper v1; modes 1.x]
Track O  — Ownership/sync plane (KOOMPI.Cloud + Selendra)             [P0 at-rest in v1; sync/anchor 1.x]
Track I  — Two-language (English default + Khmer first-class)          [UI base v1 if resourced; search w/ L1]
Track X  — Cross-cutting: CI/test, migration, governance, a11y,       [interleaved; some v1-blocking]
            footprint, doc-coherence, model-weight licensing
```

Dependency spine and the v1 critical path are in §10.

### 3.1 Phase-scheme crosswalk (the Track map is the model of record)

Three numbering schemes exist across the docs and they **do not align** — `prd.md` §7's
`P0–P4` and `architecture.md` §14's `P1–P6` were written before this Track map and number
*different things*. **The Track labels here are canonical;** the P-schemes are reading aids
that map onto Tracks as follows. (`data-ownership.md` already uses `O-1..O-4`, which match
Track O.)

| Concern | **Track (canonical)** | prd §7 | arch §14 | v1/1.x |
|---|---|---|---|---|
| Doc gate (rewrite to settled decisions) | precondition | — | step 0 | v1 |
| Safe-base prefix (privacy default, gate `set_shell_config`, localhost fix, storage, policy stub) | G + R + P (P-0a/b/c, P-1 stub) | P0 (prefix 1–6) | steps 1–6 | v1 |
| L0 substrate (`koompi-restore` PKGBUILD + polkit, per-user index slot, pre-stage embed/Ollama/OCR, seed model) | G + R + L1-prep | P0 | **P1** | v1 |
| Local agency (native tool-calling, model pin) | L2 (L2-2) + P | P0 | P3 (tool-calling slice) | v1 |
| L1 Context Engine ("never find files") | **L1** | P1 | P2 | v1 |
| L2 RAG + memory + safe tool-calling | **L2** | P2 | P3 | v1 |
| L3 app-bus ("apps talk") | **L3** | P3 (with L4) | P4 | 1.x |
| L4 automation / morning briefing (**edition-agnostic** — KDE incl., ADR-0007) | **L4** | P3 (with L3) | P5 | 1.x |
| Ownership at-rest | **O-1** | P4 | P6 | v1 |
| Sync / cloud / Selendra anchor | **O-2..O-4** | P4 | P6 | 1.x (ADR-0008, ADR-0009) |
| Subsystem: per-context isolation + Broker (Light/App Window/Detonation) | **S** | — (not in prd P-scheme; ADR-origin) | — | wrapper v1; modes 1.x (ADR-0010, ADR-0011) |
| Khmer i18n (atomic with L1) | **I** | cross | i18n | v1 if resourced |
| Cross-cutting (CI, migration, a11y, licensing) | **X** | cross | cross | interleaved |

**The drift to remember:** prd `P0` is the widest — it spans the arch prefix (steps 1–6),
arch `P1` (L0 substrate), **and** the tool-calling slice of arch `P3`. After that they track
1:1 but offset: prd `P1` = arch `P2`; prd `P2` = arch `P3`; prd `P3` = arch `P4`+`P5`; prd
`P4` = arch `P6` = Track O. When the schemes disagree, the Track wins.

---

## 4. Track G — Ship-gates (close G1/G2/G3; make L0 install + update)

L0 = Arch + Hyprland/KDE + btrfs/snapper. The substrate must *install itself and pull
updates* before anything above it can ship. Each item is a verifiable unit.

- **G-1. Installer executes (real archinstall exec + Review gate).** Replace the stubbed
  exec with a real `archinstall --config --creds --silent` call; gate it behind an
  actual Review keypress. *Today:* `main.zig:122-127` `nextAction()` always returns
  `.advance`; the destructive call is short-circuited in the stub (`main.zig:314-319`);
  the file header says "every dangerous step is a TODO/REVIEW stub" (`main.zig:1-8`).
  **Done when:** a VM boots the ISO and a real partition+pacstrap+chroot completes
  unattended from TUI answers.
- **G-2. Real archinstall `disk_config` from a PINNED release.** Pin archinstall to an
  **exact tag** (encode it, not `4.x`), and generate `user_configuration.json` from that
  release's `archinstall --dry-run`/save-config. *Today:* the JSON is a hand-fabricated
  shape template with literal `"obj_id": "<GENERATED-UUID>"` that archinstall **silently
  ignores under `--silent`** (`archinstall.zig:19-31, 104-132`) — a silent-failure mode
  on a destructive op. **Done when:** the emitted JSON validates against the pinned
  release and a `--dry-run` round-trips it unchanged.
- **G-3. libvaxis 0.16 event loop wired.** Re-add a pinned, 0.16-compatible libvaxis
  revision to `build.zig.zon` (currently empty deps; libvaxis was dropped while stubbed,
  `build.zig:3-8`) and wire the real TUI: keyboard input, block-device enumeration for
  the Disk step, text/radio capture for Identity/Edition/Encrypt. **Done when:** the TUI
  collects all answers interactively in a VM; **if no 0.16-compatible libvaxis tag
  exists, fall back to a hand-rolled raw-terminal TUI** (the state machine in `main.zig`
  is already dependency-free) — do NOT block the only ship-blocker phase on an upstream
  tag that may not ship.
- **G-4. `koompi-installer` + `koompi-restore` PKGBUILDs.** Create
  `sdata/dist-arch/koompi-installer/PKGBUILD` and `…/koompi-restore/PKGBUILD` building
  from `installer/build.zig`. `koompi-restore` must install `/usr/bin/koompi-restore`,
  `/usr/local/lib/koompi/reset_home.sh`, the `koompi-factory-reset-home.service`, **and a
  polkit action** so a GUI button can escalate without a root shell. Pull `koompi-restore`
  into `koompi-base`. *Today:* neither package exists; the offline `/home`-wipe unit in
  `post_install.sh:144-154` is **dead code** because no package installs the script+unit
  it enables. **Done when:** both packages build in a clean chroot and `koompi-base`
  depends on `koompi-restore`.
- **G-5. Put the installer on the ISO.** Uncomment `koompi-installer` in
  `packages.x86_64` (currently `#koompi-installer`, marked PLACEHOLDER) and wire root's
  `~/.zlogin` to exec it. **Done when:** the ISO autologin launches the installer, not a
  shell. (Depends on G-4 + G-9.)
- **G-6. Signing key + secrets.** Generate one RSA-4096 no-expiry KOOMPI packaging key;
  store private key + fingerprint as GitHub secrets (`GPG_KEY`/`GPG_KEY_ID`). **Hold the
  master key offline; sign in CI with a short-lived subkey; document a
  revocation/rotation path before the repo is public** (the no-expiry key is a
  supply-chain single point of failure under `SigLevel=Required`). **Done when:** CI can
  sign without the private key ever touching the runner's disk unencrypted.
- **G-7. DECIDE the `[koompi]` publish target before flipping SIGN+PUBLISH.** GitHub
  Releases (zero-infra v1) **or** `repo.koompi.org` (needs hosting/SLA/bandwidth
  ownership — flagged unowned). The `pacman.conf Server=` and DB layout must be tested
  end-to-end in CI; an unattended ISO build against an undecided endpoint produces
  installs that cannot reach `[koompi]`. **Done when:** a target is chosen and a test
  client installs a signed package from it.
- **G-8. Wire SIGN+PUBLISH in CI.** Uncomment the SIGN+PUBLISH block in
  `build-packages.yml:82-112` (currently fully commented, "Enable only once GPG_KEY
  exists"); sign each package + the DB; publish to G-7's target. Ship
  `koompi-signing.pub.asc` in airootfs + a `pacman-key` import hook in the archiso
  profile, and uncomment the `[koompi]` stanza with `SigLevel=Required` (never
  `TrustAll`). **Done when:** the ISO trusts `[koompi]` out of the box and installs
  signed packages. (Depends on G-6, G-7.)
- **G-9. CI compiles the installer.** Add `build-installer.yml` running `zig build` (both
  `koompi-installer` and `koompi-restore`) on PRs. *Today:* **no workflow runs
  `zig build`** — a future commit can silently break the build. **Done when:** a PR that
  breaks the Zig build fails CI. (See Track X.)
- **G-10. Credential hardening.** Replace the plaintext password borrowed-slice
  (`config.zig:47-51`, never zeroed `archinstall.zig:165-166`) with a locked/zeroed
  buffer wiped immediately after `writeUserCredentials()` writes to `/dev/shm` (chmod
  600, already deleted post-exec). Verify the pinned archinstall release honors the
  `sudo`-group field on the user record (else the user can't run root-required
  `koompi-restore`). **Done when:** the password never persists in RAM past cred-write
  and the created user is confirmed in `sudoers`.

---

## 5. Track R — Restore legs (VM-verify the semi-immutable stack)

The stack is code-complete and called in `post_install.sh main()` (`ensure_pkgs` →
`setup_snapper` → `fix_root_subvol_mount` → `enable_login` → `write_os_release` →
`install_home_reset_unit` → `setup_snapshot_boot` → `pin_baseline` → `setup_grub_btrfs`,
lines 253-261), but **never executed.** Two open legs can make a rollback a *silent
no-op*; until both are closed and VM-tested, factory reset is not shippable.

- **R-1. Close the GRUB `rootflags=subvol=@` leg.** `snapper rollback` boots by flipping
  the btrfs default subvolume, but `grub-mkconfig`'s `10_linux` typically bakes
  `rootflags=subvol=@` onto the kernel cmdline, **overriding the flip** so the rollback
  no-ops at the boot layer. `fix_root_subvol_mount()` (`post_install.sh:119-136`) closes
  only the *fstab* leg; the GRUB leg is documented STILL-OPEN (`post_install.sh:108-112`,
  `reset.zig:128-134`). Fix: strip `rootflags=subvol=` from `/etc/default/grub` +
  `10_linux`, OR route restore **exclusively** through grub-btrfs menu entries (which set
  correct rootflags themselves). **Done when:** `grep 'rootflags=subvol=' /boot/grub/
  grub.cfg` returns nothing on a VM install, encoded as a CI/VM assertion.
- **R-2. Reconcile grub-btrfs-overlayfs vs the systemd mkinitcpio hook.**
  `setup_snapshot_boot()` (`post_install.sh:204-214`) SKIPS the overlayfs hook when
  mkinitcpio uses the `systemd` hook, leaving `@baseline` boots **read-only** (drops to
  emergency shell). On LUKS installs archinstall may emit the systemd hook by default —
  making read-only snapshot boots the norm on the privacy-conscious configs. Force the
  `udev` hook on the KOOMPI default install (incl. LUKS), or document read-only snapshot
  boots as a known limitation. **Done when:** a with-LUKS and a without-LUKS VM both boot
  `@baseline` read-write.
- **R-3. VM-verify the asymmetric-reset guard.** `reset_home.sh run()` refuses to delete
  `@home` unless the running root subvol is the rolled-back snapshot N (so a no-op boot
  fails SAFE — keeps `/home`, retains the marker for a clean retry). It is IMPLEMENTED
  but **VM-UNVERIFIED** (`reset_home.sh:43,89,104-117`, `reset.zig:104`): the exact
  first-line format of `btrfs subvolume show /` is unconfirmed on the target
  btrfs-progs. **Done when:** on a VM, a deliberate no-op boot leaves `/home` intact and
  the marker present; a correct baseline boot completes the wipe.
- **R-4. VM-test both modes end-to-end + power-cut idempotency.** System Restore boots
  `@baseline` with `/home` intact; `--full` wipes+reseeds `@home` offline; power-cut at
  arm / during rollback / during reseed recovers cleanly (the `sync` barriers in
  `reset_home.sh` + marker discipline). **Done when:** the full lifecycle passes in the
  CI VM harness (Track X).
- **R-5. Self-service factory-reset (polkit GUI), not root-only.** `koompi-restore`
  requires root (`restore_main.zig` `geteuid()!=0 → NotRoot`). Add the polkit action
  (from G-4) + a Settings/GUI button so a reset is self-service. Localize the type-to-
  confirm flow and messages (Track I). **Done when:** a non-root user triggers System
  Restore from Settings via a polkit prompt.
- **R-6. GATE `--full` behind R-1+R-3.** Ship `koompi-restore` in v1 but have `--full`
  **refuse to run** until the GRUB leg is VM-verified closed and the guard verified —
  otherwise a user hits a silent no-op reset and (worst case) the next student inherits
  the prior student's plaintext index/data. **Done when:** `--full` aborts with a clear
  message on an install where R-1's assertion has not passed; System Restore remains
  available.
- **R-7. Document the snapper pruning policy.** snap-pac creates pre/post snapshots per
  pacman txn (`post_install.sh:42`); without a policy the snapshot budget fills the disk.
  `@baseline` is exempt (no cleanup algorithm, `pin_baseline()` `post_install.sh:167-178`).
  **Done when:** the retention policy (count + age) is documented and bounded so snap-pac
  cannot exhaust the disk.

---

## 6. Track P — Privacy/policy chokepoint + safety primitives

This track makes "your data and your AI never leave your machine" **code-enforced**, and
makes agency safe. **The P0 items are one-liners that must land before any agency
ships.** This is the moat (FORK A) made real, not asserted.

- **P-0a. Flip the privacy default to local-first (one-liner).** Change `Config.qml:84`
  `policies.ai` default `1` → `2` (local-only) and add `policies.sync: 0` (off). *Today*
  the OS ships cloud-allowed by default — the inverse of the positioning. **Done when:**
  a fresh profile defaults to local-only and sync off.
- **P-0b. Gate `set_shell_config` (one-liner).** Mirror the `run_shell_command` approval
  gate (`Ai.qml:882`, `functionPending = true`) onto `set_shell_config`, which today
  calls `Config.setNestedValue(key,value)` **immediately, ungated** (`Ai.qml:866-873`) —
  the model can rewrite *any* shell config key, including `policies.ai`, with zero
  consent. Add a protected-key denylist (`policies.*`, security keys) the tool path
  cannot write. **Done when:** a `set_shell_config` tool call shows an approval card and
  cannot touch `policies.*`.
- **P-0c. Fix the egress check (it is spoofable both ways).** `Ai.qml:544`
  `model.endpoint.includes("localhost")` wrongly **blocks** `http://127.0.0.1:11434`
  /`[::1]` and wrongly **allows** `https://evil.com/?h=localhost`; it also runs only at
  *model selection*, not on the request path. Replace with a parsed-URL host allowlist
  (`{localhost,127.0.0.1,::1}`) enforced at a single request chokepoint
  (`makeRequest`/`buildEndpoint`), not in the UI. **Done when:** a `policies.ai=2`
  request to a non-loopback host is refused at the request layer, and a loopback-IP
  Ollama is allowed.
- **P-1. `org.koompi.Policy` daemon (the decision brain).** Rust + zbus, system +
  per-user, fail-closed. `CanRead(scope,path)`, `CanEgress(target,kind)→allow|deny|
  prompt`, `RequestConsent(action)`, `GetEffectivePolicy(uid)`. **Done when:** L1/L2
  consult it before every read/egress and an unreachable daemon denies. Ship a
  **no-op-deny stub in P0** so downstream tracks code against the fail-closed contract
  from day one.
- **P-2. Root-owned egress enforcement (the boundary).** `koompi-syncd` (the sole egress
  process) in a netns with `nftables` allowlisting only `localhost:11434` + the named
  sync host (§2.2). **Done when:** a packet capture during a local-only session shows
  zero KOOMPI-originated user-data traffic to any host but the allowlist.
- **P-3. Sandbox `run_shell_command`.** Execute the one dangerous tool inside a
  bubblewrap unprivileged namespace (read-only `/usr`,`/etc`; writable workspace +
  tmpfs; network OFF by default; `no-new-privs`; rlimits) instead of bare `bash -c` with
  full ambient authority. Escalation is a separate, explicitly-confirmed polkit tier.
  **Done when:** an approved command cannot open a non-allowlisted socket or read the
  index DB.
- **P-4. Uniform capability-tiered approval gate + audit log.** One gate for ALL tools
  by tier — READ (auto), WRITE (confirm), DANGER (always-confirm + sandbox). JSON-schema-
  validate every tool call's args before dispatch. Append-only audit log (caller, tool,
  args-digest, decision, time). **Done when:** every tool path returns a structured
  result on approve/reject/error (no silent multi-turn stalls) and the audit log records
  each call.
- **P-5. Per-user secret + data isolation.** Per-UID keyring scoping (today secrets are
  one `application=koompi` blob — no per-component scoping) + per-user index namespace
  (Track L1) + XDG `0700` enforcement with a startup warning if world-readable. **Done
  when:** on a shared machine, one user cannot read another's keys, chats, or index.
- **P-6. Egress audit ledger (user-visible).** Append-only, user-readable record of every
  `CanEgress` allow and every file/RAG-snippet that left the device — making "nothing
  left my machine" **falsifiable**, and the only post-hoc detector for injection-driven
  exfil. **Done when:** a Settings panel renders the ledger.

> **Sequencing within P:** P-0a/P-0b/P-0c land first (one-liners). P-1's stub lands in
> P0. P-2 + P-3 + P-4 must land **before or with** the first local tool-calling change
> (§2.3, Track L2 L2-2).

---

## 7. Track L1 — Context Engine (the data fabric; "never find files again")

L1 = a per-user native daemon `koompi-contextd` (Rust, `systemd --user`), NOT QML. The
watch → extract → embed → index pipeline is CPU/IO-heavy and must survive Quickshell
hot-reloads; per-user scope gives free multi-user isolation. The existing `Ai.qml`
becomes a *client* of L1 over D-Bus. Storage is settled in §2.1. Design depth:
`architecture.md` §5 (and §7 for storage/schema).

- **L1-1. Daemon skeleton + resource fence.** `koompi-contextd` (tokio, zbus, rusqlite)
  as a `systemd --user` service inside a slice (`CPUQuota`, `IOSchedulingClass=idle`,
  `Nice`, `MemoryHigh`). **Done when:** the daemon starts, idles at single-digit MB, and
  is throttled by the slice.
- **L1-2. Storage + schema (per §2.1).** SQLite at `~/.local/state/koompi/context/
  index.db` with `chattr +C` set on the empty dir at first-run (assert dir is empty
  before setting `+C`; verify with `lsattr`). Tables: `documents`, `chunks`, `vec0`
  (sqlite-vec), `fts5`, `entities`, `edges`, `work_queue` (resumable), `state`
  (`schema_version`, `model_id`, `embedding_dim`). **Decouple embedding dimension from
  the schema** (store `model_id`+`dim` in `state`, version the vec table) so a model
  change is a managed re-embed, not silent corruption. **Done when:** the schema is
  versioned and a model swap triggers a tracked rebuild, not a crash.
- **L1-3. Watcher (scope + exclusions + atomic-save handling).** `notify` crate
  (inotify) over a configured scope (`~/Documents`, `~/Downloads`, `~/Desktop`, KOOMPI
  notes/todos). Exclude the index dir (feedback-loop guard — CRITICAL), `.git`,
  `node_modules`, caches, `.snapshots`, `/tmp`, binaries; honor `.gitignore`/
  `.koompiignore`. Treat write-temp-then-rename (editor atomic saves) as a *modify of the
  destination doc_id*, not create+delete, to keep doc identity + graph edges stable. **Do
  NOT ship the `60-koompi-inotify.conf` sysctl** — Arch already ships
  `fs.inotify.max_user_watches=524288` (`/usr/lib/sysctl.d/10-arch.conf:4`); the "65536
  too low" premise is false. Keep a periodic-rescan fallback on `EMFILE`/`ENOSPC` only.
  **Done when:** a saved file is (re)indexed once, an editor atomic-save does not churn
  doc identity, and the index dir is never self-indexed.
- **L1-4. Extractors (text/PDF/office/OCR).** Per-MIME plaintext via **killable
  subprocesses** (license-isolating copyleft tools): native text/md/code; `pdftotext`
  (poppler, GPL — subprocess boundary, not linked); `pandoc` for office (prefer over
  heavy libreoffice on modest HW); `tesseract` (+ `khm` traineddata) for OCR. Per-file
  failures isolated, never crash the pipeline. **Done when:** a PDF and a scanned image
  yield searchable text without crashing the daemon on a malformed file.
- **L1-5. Chunker + embedder (license-pinned weights).** Sentence-aware ~512-tok chunks
  (Khmer no-space handling — see I-4); batch to Ollama `/api/embed`; content-hash dedup;
  graceful degrade with backoff if Ollama is down. **Default embedder = a license-
  verified, Khmer-capable, no-strings model (BGE-M3, MIT — verify weights license at
  pin).** Pin the model + dim as a first-class no-strings dependency (Track X). **Done
  when:** embeddings persist, unchanged chunks are skipped, and Khmer + its English
  paraphrase score sane cosine similarity (empirical check, not asserted).
- **L1-6. Indexer + knowledge graph.** Single-writer transactional upsert into
  `documents`/`chunks`/`vec0`/`fts5`; graph `entities`/`edges` populated from cheap
  metadata first (file↔dir, mail→sender/recipient, calendar→event/attendee); deletes
  cascade. LLM-based NER is a later enrichment pass. **Done when:** deleting a file prunes
  its chunks/vectors/edges, and the graph holds metadata relations.
- **L1-7. Hybrid query API (D-Bus, taint-aware).** `org.koompi.ContextEngine.Search(query,
  filters,k)` = vec0 KNN + FTS5 BM25 fused via RRF, scoped by SQL metadata predicates,
  returning `{snippet, source_path, score, mime, entity_ids}`. **Authorize callers**
  (resolve sender PID→exe, allowlist L2/L4/launcher; gate sensitive sources behind an
  explicit grant — the fabric must not be a one-call secret-exfil oracle for any
  same-user process). **Tag every result with provenance/sensitivity** so L2 can taint
  it (§2.3). **Done when:** a vague query returns the right file with sources, and an
  unauthorized caller is refused. *This IS "never find files again."*
- **L1-8. Power-aware first crawl.** The one-time full crawl is the expensive event; run
  it incrementally at `IOSchedulingClass=idle`/deep-nice. **Allow first-crawl progress on
  battery** (deep-throttled) — requiring AC means it never finishes on a laptop that is
  always in use; gate only ongoing *bulk re-embeds* on AC+idle. Add a visible progress +
  pause control. **Done when:** a cold `~/Documents` indexes to completion on a laptop in
  normal use without pinning the desktop.
- **L1-9. Forget/purge + secure-delete.** A delete must remove content from the live
  index AND not leave plaintext in freed SQLite pages (schedule `VACUUM`/`VACUUM INTO`).
  Combined with at-rest encryption (Track O). **Done when:** a deleted sensitive document
  is unrecoverable from the index DB after purge.

---

## 8. Track L2 — Assistant over your data (RAG, memory, safe tool-calling)

L2 = extend the existing `Ai.qml` into an agent that retrieves over L1 (RAG), has
cross-session memory, and acts via **safely-gated** tool-calling. For headless reach
(L4) and a single auditable trust boundary, the agent runtime is extracted into a
per-user `koompi-assistantd` (Rust, `systemd --user`) with `Ai.qml` as a thin D-Bus
client + degraded fallback. Design depth: `architecture.md` §6. **AI-first = this layer is
the foundation, not a sidebar.**

- **L2-1. RAG wiring + source attribution.** Before responding, call
  `org.koompi.ContextEngine.Search`; inject token-budgeted snippets as a context message;
  record which sources were used (populate the existing-but-empty
  `AiMessageData.annotations`). **Done when:** an answer cites the documents it used and a
  question about a local file is grounded in it.
- **L2-2. Local-model tool-calling — the REAL fix (lands WITH §2.3 mitigations).** Switch
  the local/Ollama path to the **native `/api/chat` endpoint (a new api_format)**, which
  reliably **streams** tool calls — do NOT "add a `tool_calls` branch to
  `OpenAiApiStrategy`" mirroring Mistral: Ollama's OpenAI-compat `/v1` endpoint
  **silently drops streaming `tool_calls`**, so a parse branch there yields nothing.
  *Today* `OpenAiApiStrategy.parseResponseLine` (`OpenAiApiStrategy.qml:34-64`) has only
  `content`/`reasoning` branches — the local-first default cannot call tools at all. Ship
  this **in the same commit** as RAG-content tainting + typed confirmation for
  destructive/egress + sandboxed exec (P-3, §2.3). Add malformed/hallucinated-tool-call
  recovery (small local models tool-call unreliably). **Done when:** a local Ollama model
  drives a tool call end-to-end, RAG-sourced content cannot trigger a destructive command
  without fresh typed confirmation, and a malformed call is recovered, not crashed.
- **L2-3. Bounded agent loop + result validator.** ReAct-style loop with hard
  `max_iterations`/`max_tokens`/`max_wall_clock`; validate every tool result (exit code,
  stderr, empty output) and feed the signal back so the model can retry/abandon — fixes
  the current blind `makeRequest()` chaining that appends an exit code and continues
  (`Ai.qml:849-852`). **Done when:** a failing tool produces a recoverable observation
  and a runaway plan stops at the cap with an honest report.
- **L2-4. Cross-session + long-term memory.** Conversation history + rolling summaries +
  durable user facts, stored in the SAME per-user SQLite DB as L1 (§2.1), schema-
  versioned (today `chatToJson` has **no version field**, `Ai.qml:887` — a migration trap
  on a rolling distro). Provide a user-visible memory view + delete. **Done when:** the
  assistant recalls prior-session context and the user can inspect/delete what it
  remembers.
- **L2-5. Daemon extraction + thin client + per-conversation state.** Move the runtime to
  `koompi-assistantd`; refactor `Ai.qml`'s singleton globals (one shared message buffer /
  model / tool / strategy) into a **per-conversation object** so a headless run cannot
  clobber the live sidebar chat. `Ai.qml` becomes a D-Bus client with a degraded fallback
  that **still applies the policy/tier gate** (no fallback to raw `curl` + ungated
  `bash`). **Done when:** a headless `Ask()` and an interactive chat run concurrently
  without colliding, and the offline fallback is read-only/chat-only.
- **L2-6. Add the missing IpcHandler.** `Ai.qml` is the only service without an
  `IpcHandler` (verified: zero matches; every other service has one). Add
  `IpcHandler{target:"assistant"}` exposing `chat()/ask()/summarize()` so L4 timers and
  L3 intents can drive the assistant. **Done when:** `qs ipc call assistant ask "..."`
  returns a reply.
- **L2-7. Cloud egress is double-gated + per-source.** Cloud chat is one consent level;
  shipping the user's indexed RAG snippets to the cloud is a **higher, separate** opt-in,
  off by default even when cloud chat is enabled, with a persistent "this turn left your
  device" indicator. **Never silently fall back to cloud** on low RAM — degrade to
  retrieval-only with a banner. **Done when:** with cloud chat on and RAG-egress off, no
  local snippet is sent to the cloud, and a sub-floor machine degrades to search without
  silent egress.

---

## 9. Track L3 / L4 / O / I — the rest of the stack (mostly 1.x)

### Track L3 — App-context bus ("apps talk to each other") — **1.x**

A native broker `koompi-busd` (Rust/zbus) owns `org.koompi.Bus` on the session bus;
apps speak an MCP-shaped manifest (resources/tools/intents); the broker mediates every
call. Quickshell can CONSUME but **cannot EXPORT** D-Bus (verified: no `DBusObject`/
`registerService` in its qmltypes), so the shell talks to the broker over a unix socket
(`Quickshell.Io.Socket`) while the broker owns the D-Bus name. Design depth:
`architecture.md` §8.1.

- **L3-1. Wire contract + broker skeleton** (manifest JSON schema with `schema_version`;
  `org.koompi.Bus` + `org.koompi.Provider` XML; `Register/Query/Describe`). **Done when:**
  `busctl --user … Query` returns a registered test provider.
- **L3-2. Enforce broker-mediation as an SDK invariant.** Every `org.koompi.Provider`
  method must verify `sender == NameOwner(org.koompi.Bus)` and reject others — else the
  default session bus (`<allow send_destination="*">`) lets any peer bypass the broker.
  **Done when:** a direct (non-broker) call to a provider is rejected.
- **L3-3. Capability security (daemon-owned tiers, not self-declared).** The daemon owns
  the tool→tier map; externally-registered tools are NEVER auto-allowed regardless of
  self-declaration; authenticate registrant bus names against an allowlist (gate
  first-party trust on the G-6 key). **Done when:** a third-party tool registered as
  "READ" is still treated as confirm-required.
- **L3-4. KDE consent surface (hard, not deferred).** Both editions (Hyprland + KDE) need
  the Approve/Edit/Reject consent card; build a standalone polkit-style consent agent so
  KDE-native flows are covered. **Done when:** a gated flow renders consent on KDE.
- **L3-5. `org.koompi.index` + first-party providers** (notes/todo/calendar) and the
  xdg-desktop-portal bridge for legacy-app intents (`share.email`, `open.file`). **Done
  when:** "email this file → compose + attach + draft" runs whether mail is native,
  Evolution-via-adapter, or portal-default. *This IS "apps talk to each other."*

### Track L4 — Automation ("morning automated") — **1.x**

Durable triggers in `systemd --user` `.timer` units (NOT a QML `Timer`, which only fires
while the shell is alive); each timer runs a thin runner that drives a **headless,
capability-scoped, read-only-by-default** assistant run (the interactive approval gate is
meaningless at 6am). Design depth: `architecture.md` §8.2.

- **L4-1. Time-triggered local daily briefing** (`OnCalendar`, `Persistent=true` for
  power-off catch-up, `ConditionACPower`, slice limits) with an fsync-gated completion
  marker (idempotent across power cuts, mirroring `reset_home.sh` discipline). **Done
  when:** an overnight-powered-off box produces exactly one briefing on next boot.
- **L4-2. Headless capability model.** Automation contexts get **NO write/danger tools**
  by default (read-only L1/L3 queries + declared public RSS fetch); a tool-call from a
  non-interactive trigger is queued for human approval, never auto-executed. **Done
  when:** a briefing that would need `run_shell_command` queues it instead of running it.
- **L4-3. Egress honesty + runtime-failure degrade.** Reuse Track P's `CanEgress`
  (default local Ollama; cloud only if explicitly enabled + logged). Distinguish runtime
  failures (Ollama missing, OOM, shell-down, clock-unsynced) with distinct run-history
  statuses, and degrade to an extractive (non-LLM) digest rather than an OOM re-run loop.
  **Done when:** a box without a usable model still produces a digest and the run-history
  explains any failure.
- **L4-4. DE-agnostic runner.** `qs ipc` is Quickshell-only; extract a headless runner
  (Ollama + sqlite-vec + D-Bus) so the briefing exists on KDE too. **Done when:** the
  briefing runs on a KDE session with the shell down.

### Track S — Subsystem: per-context isolation + Broker — **wrapper v1; modes 1.x**

Per-context isolated app contexts. Design of record: [ADR-0010](adr/0010-subsystem-two-axis-trust-driven-isolation.md)
(two-axis, trust-driven; modes Light / App Window / Detonation Chamber) and
[ADR-0011](adr/0011-subsystem-credential-broker.md) (credential boundary = engine, not store;
deputy-first auth). Sequenced **boundary-value-first on cheap hardware, VM tiers later**; the
Broker is the spine everything authenticated hangs off, and the VM tiers are gated by **The
Floor** (16 GB+, [ADR-0001](adr/0001-degrade-local-never-silent-cloud.md)). Reuses Track P-2's
root-owned egress chokepoint per-context — no parallel egress plane.

- **S-0. Env-scoping wrapper** (`koompi-run --profile=…`: scoped env + key + config dir).
  Ships earliest, standalone; **explicitly NOT a security boundary** (ADR-0002) — labelled as
  ergonomics so it is never mistaken for isolation. Floor-friendly; may land in v1. **Done when:**
  the same CLI runs against two providers with separate config dirs, and the UI calls it
  convenience, not containment.
- **S-1. Broker + Light mode + Deputy** (the first real boundary). `koompi-brokerd` (per-context
  source store — *not* the shared `application=koompi` blob — + short-TTL scoped-token minting +
  host-attested context identity (SO_PEERCRED for bwrap, vsock CID for VM) + brokered interactive auth, [ADR-0012](adr/0012-subsystem-brokered-interactive-auth.md));
  Light = bwrap + per-context netns/nftables + hygiene store;
  Deputy = TLS-terminating auth-injecting egress proxy with destination-pinning. Delivers
  per-context egress isolation + deputy-first auth at **floor hardware** (no VM). **Done when:** a
  trusted CLI in one context cannot reach a host outside its allowlist, holds no long-lived
  secret, and every egress is in the host-side ledger.
- **S-2. App Window — trusted-Linux seamless** (bwrap + Wayland-socket passthrough; compositor
  withholds `wlr-screencopy`/`ext-data-control`/global-input). Seamless window for a *trusted*
  Linux GUI app at native speed. **Done when:** a trusted Linux app appears as its own KOOMPI
  window with no guest shell, screen-capture/clipboard not silently exposed.
- **S-3. Detonation Chamber** (headless VM — Firecracker/Cloud-Hypervisor; hermetic, no
  display/GPU/shared-FS; **complete** egress ledger; **no** secret injection). Want #1: run a
  risky experiment without touching the host. Sequenced before the seamless-VM tier — headless is
  simpler and is the higher-priority want. **16 GB+.** **Done when:** untrusted code runs fully
  disposable, every byte of egress is ledgered, and disposal leaves no host residue.
- **S-4. App Window — semi-trusted/foreign Linux microVM** (crosvm/Cloud-Hypervisor +
  virtio-gpu/Venus + waypipe/Sommelier; vsock early-boot secret provisioning). Want #2: a foreign
  Linux app as a seamless near-native window at VM-grade isolation. **16 GB+.** **Done when:** a
  semi-trusted Linux app renders seamlessly with credential isolation enforced by the guest
  kernel.
- **S-5. App Window — Windows** (QEMU + FreeRDP-RemoteApp/RAIL — the ADR-0003 promotion to a
  first-class App Window engine). Windows apps as seamless KOOMPI windows. **16 GB+, Windows
  license.** **Done when:** a Windows app appears as its own KOOMPI window with no Windows shell.

> Forward-looking constraint (ADR-0011 D3): if/when microVM snapshotting is built, secret-bearing
> guests are non-snapshottable (warm-start = secret-free snapshot + fresh vsock re-injection).

### Track O — Ownership/sync plane (KOOMPI.Cloud + Selendra) — **P0 at-rest in v1; sync/anchor 1.x**

Local-first/private on-device by default; opt-in E2EE sync to self-hosted KOOMPI.Cloud;
Selendra anchors identity/keys/ownership only (never bulk data). Design depth:
`docs/data-ownership.md`.

- **O-1 (v1). On-device encryption-at-rest** — `koompi-vault` (master key from
  gnome-keyring + PAM; optional TPM2 seal), per-object DEKs, XChaCha20-Poly1305. Migrate
  the existing plaintext stores (chat JSON, notes, todos, config secrets) into the
  encrypted store. **Fix the keyring-unlock leak** — replace `echo password |
  gnome-keyring-daemon` (visible in `ps`) with fd-passing / the systemd password agent.
  **Honest scope:** at-rest defends offline disk theft ONLY; a session-unlocked key is
  reachable by any same-user process (app-exfil defense = sandboxing, Track P/L3). **Done
  when:** the index/chat/notes DBs are opaque at rest and the keyring password never
  appears in `ps`.
- **O-2 (1.x). Single-device E2EE backup to self-hosted KOOMPI.Cloud** (SeaweedFS
  Apache-2.0 — explicitly NOT MinIO/Garage which are AGPL; zero-knowledge server) via the
  sole egress daemon `koompi-syncd` (Track P-2) with the append-only egress log. **Done
  when:** a packet capture shows only ciphertext to the one allowlisted host.
- **O-3 (1.x). Multi-device CRDT sync + key custody** — Automerge for structured data;
  the vector index is **never synced** (each device re-embeds from source, §2.1); QR
  device-pairing with an SAS/verification step (so the master key is never wrapped to an
  unverified pubkey); optional zero-knowledge recovery code. Enforce migrate-before-wipe
  before `--full`. **Done when:** two devices converge on notes/todos and a new device
  re-embeds its own index.
- **O-4 (1.x). Selendra anchoring** — periodic signed Merkle root over the object
  manifest (NEVER per-operation; NEVER `hash(plaintext)` — only salted commitments) +
  device key rotation/revocation, behind an abstract anchor interface (native pallet vs
  EVM/ink! TBD). **Resolve the gas/onboarding string** (anchoring a root costs a paid tx
  — subsidize/relay, or make anchoring fully optional with a "works with zero blockchain
  interaction" default). **Done when:** ownership is anchorable with no token purchase
  required of the user.

### Track I — Two-language (English default + Khmer first-class) — **UI base v1 if resourced; search w/ L1**

Three rendering/typing/translation legs ship TOGETHER (any subset = tofu boxes), plus a
fourth search leg with L1. English default; Khmer is a feature, not the positioning.

- **I-1 (v1). `km_KH.json` + fallback chain.** Add the 15th locale JSON (matches the
  existing schema); add an explicit `km_KH → en_US → key` fallback in `Translation.tr`
  (today it falls straight to the English key). Add a CI **coverage gate ≥95%** vs
  `en_US.json` before the locale is selectable. (Fix the malformed `he_HE`→`he_IL` while
  here.) **Done when:** the coverage gate passes and untranslated strings fall back to
  English, never raw keys.
- **I-2 (v1). Khmer rendering.** Add `noto-fonts-khmer` to `koompi-fonts-themes`
  (currently absent) + a fontconfig fallback rule. **Done when:** Khmer text renders, not
  tofu.
- **I-3 (v1). Khmer typing — XKB `km` layout (NOT fcitx5-unikey).** Ship the XKB `km`
  layout (the correct path; usable Khmer IMEs do not exist) with `fcitx5` +
  `fcitx5-keyboard` as the unified switcher (the orphaned `dots-extra/fcitx5/conf/
  classicui.conf` anticipates this) — **reject fcitx5-unikey (Vietnamese)**, the old
  audit's wrong suggestion. Include the IM **session-env wiring** + autostart (Khmer
  won't type without `GTK_IM_MODULE`/`QT_IM_MODULE`/Wayland IM env). **Done when:** a
  us↔km toggle types Khmer in GTK, Qt, and Hyprland/KDE.
- **I-4 (with L1). Khmer search.** Khmer has no inter-word spaces — L1 lexical/FTS
  indexing needs ICU dictionary-based word segmentation (`libicu` BreakIterator), exposed
  to L1 as `tokenize(text, lang)`. Semantic search is covered by the Khmer-capable
  embedder (L1-5). **Done when:** a Khmer keyword query returns relevant Khmer documents.
- **I-5 (v1). Installer locale/keymap + live ISO.** Offer Khmer in the installer locale
  picker (English default); write `/etc/locale.conf` + `/etc/vconsole.conf`; set the live
  ISO locale from `C.UTF-8` to `en_US.UTF-8` for a renderable pre-install session. **Done
  when:** a fresh install can boot in `km_KH.UTF-8` with rendering + input working.

---

## 10. Track X — Cross-cutting (owned by nobody today; some v1-blocking)

These span the whole stack and were unowned across the layer designs. They are tracks,
not footnotes.

- **X-1 (v1, BLOCKING). CI/test foundation.** Add `zig build`/`zig test` to CI (Track G-9);
  build the **restore VM harness** (Track R) and run it on the encrypted-index case;
  create a **prompt-injection regression corpus** (poisoned doc/email/PDF fixtures) +
  a tool-call/RAG golden set that runs against the pinned local model. *Today: zero tests
  in the repo; no `zig build` in any workflow; no AI eval harness.* **Done when:** a PR
  that breaks the build, regresses a known injection, or breaks the restore lifecycle
  fails CI.
- **X-2 (v1, BLOCKING). Schema migration / rolling-distro seam.** KOOMPI is rolling Arch
  — there is no discrete v1→v1.1 event; `pacman -Syu` continuously updates the daemon,
  sqlite-vec, the embedding model, and the on-disk schema. Build a **forward-only,
  version-stamped migration runner** (stamp `schema_version`+`model_id`+`embedding_dim`;
  migrate-or-rebuild on daemon start; idempotent/resumable against partial-update +
  power-cut). **Define the post-System-Restore reconciliation:** binaries roll back to
  `@baseline` while `@home` data stays current → daemon version < data schema → auto-
  rebuild, never silent corruption. **Done when:** a simulated binary-vs-schema skew
  (incl. after a rollback) auto-recovers instead of corrupting.
- **X-3 (v1). Doc-coherence gate (DONE for PRD; keep enforced).** The canonical PRD has
  been rewritten to the settled AI-first thesis; **no thinks-stack issue is handed to a
  contributor/agent while any repo doc still encodes the dead Cambodia/education moat.**
  **Done when:** a grep for the dead theses ("AI is NOT the moat," "for Cambodian
  students" as positioning) across `docs/` returns nothing load-bearing.
- **X-4 (v1). Model-weight licensing + offline seed.** Pin the default **chat** and
  **embedding** weights as first-class no-strings dependencies and verify each weights'
  license text at pin time. **Reject** non-OSI/use-restricted weights: Qwen *research*
  license (non-commercial), Gemma custom Terms (acceptable-use strings — confirm any
  "Gemma 4 = Apache" claim against the actual LICENSE file, not SEO), Llama MAU clause.
  Default chat = a verified-Apache/MIT, Khmer-capable tier (e.g. Sailor2, Apache-2.0,
  Qwen2.5-base lineage). Provide an **offline-seed / LAN-mirror** path so a fresh or
  low-connectivity install has a working local assistant without a ~4GB first-boot pull.
  **Done when:** the bundled default weights are confirmed no-strings and a fully-offline
  install has a working local model.
- **X-5. Multi-user isolation as a first-class input** (a must-handle normal-OS concern,
  not the primary deployment — prd §2). **v1:** per-user index namespace + per-user
  keyring scoping + per-user policy + per-user `--full` hand-off semantics. **1.x (school
  admin tier):** the admin/parent **LOCK FLOOR** (a minor must not reset away the parental
  floor) — needs a persist-across-`--full` home (note `/etc` lives in `@`) + a restrictive
  `@baseline`; deferred to the 1.x admin interface. **Drop all system-wide `/var/lib/koompi` user-data stores.** **Done
  when:** two users on one device are isolated and a student account cannot loosen the
  admin floor via factory reset.
- **X-6 (v1). Aggregate hardware footprint + honest capability ladder.** Sum **all**
  always-on daemons + Ollama + the resident embed model + the chat model + DE + browser
  on the 4GB/8GB/16GB tiers — each layer self-declared "cheap" in isolation; the honest
  truth is the **4GB floor cannot run the agentic-local experience** (chat+embed alone
  exceed the ~1.5GB free budget). Publish a capability ladder: 4GB = embed+retrieval only
  (local chat off, cloud opt-in); 8GB = one model resident; 16GB+ = chat+embed resident.
  Add power/thermal gating (index only on AC+idle+under-temp for bulk work). **The demo
  runs on adequate hardware; the floor degrades to retrieval-only, never silent cloud.**
  **Done when:** the ladder is documented and the floor never silently routes private
  data to cloud.
- **X-7 (v1). Privacy-governance artifact.** A written privacy posture / data-collection
  matrix (what stays local, what leaves only on opt-in, retention/TTL), a minors/parental/
  school-admin consent framework, and the user-visible egress audit ledger (Track P-6).
  `telemetry=none` is policy-enforced in v1 and **structural** (no outbound path exists)
  only once P-2 netns/nftables lands (1.x) — never merely a flag. **Done
  when:** the posture doc exists and a school can audit what a minor's machine indexed and
  what (if anything) left it.
- **X-8 (1.x). Accessibility track.** Zero a11y references exist anywhere in the stack.
  Assess Wayland/Orca/at-spi reality for Hyprland + KDE; add font-scaling/contrast/
  reduced-motion to the Quickshell shell; ensure the consent/approval surface (Track P-4,
  L3-4) is keyboard-only + AT-reachable; design the assistant's text/voice path as a
  deliberate accessibility affordance. **Done when:** the security-consent flow is
  operable by a screen-reader/keyboard-only user.
- **X-9 (1.x). Cross-component packaging + service orchestration.** Own the dependency
  graph and the systemd-unit / D-Bus-activation **ordering** of the 4–5 new daemons that
  all depend on `org.koompi.Policy`. **Done when:** a clean install brings up
  policy → context → assistant → bus in the correct order with activation, and a
  `cargo deny` license+transitive scan gates CI.

### 10.1 Ratified owner assignments (settled in grilling — DO re-confirm names, not the decisions)

The *decisions* below are ratified; what each line needs is a **named human owner** before its
work starts. One line is still **UNASSIGNED** and that is the real gap.

| Decision | Ratified outcome | Owner | Where recorded |
|---|---|---|---|
| TPM2 across the device lineup | survey required/optional/absent; sizes the master-key sealing story | **KOOMPI hardware** | `data-ownership.md` (ON-DEVICE) |
| KOOMPI.Cloud operation | offer BOTH operated + self-host (zero-knowledge) | **KOOMPI business/ops** | ADR-0008 |
| Selendra anchoring | OFF by default; opt-in identity/ownership anchor, 1.x | **KOOMPI + Selendra** | ADR-0009 |
| Recovery / key-escrow | optional wrapped key-escrow blob, default-OFF; explicit UX | **KOOMPI product** | `data-ownership.md` (KOOMPI.Cloud), ADR-0008 |
| Khmer translation execution | `km_KH.json` gated on coverage threshold; `he_HE`→`he_IL` when touching locales | **KOOMPI community/team** | Track I (I-3), prd FR-I1 |
| Accessibility track (X-8) | a11y is a real 1.x track, not a footnote | **UNASSIGNED ⚠** | Track X-8 |
| Phase-numbering reconciliation | Track map is the model of record | **DONE** (§3.1 crosswalk) | §3.1 |
| Package-signing custodian | CI-secret-with-guardrails for v1 | **open (KOOMPI-internal)** | ADR-0005 |

---

## 11. v1 vs 1.x (the concrete line) + sequencing

### v1 (the real thing, shipped when ready): L0-solid + L1 + L2

- **Track G** (G1–G3 closed) — installs itself, signed repo, installer on ISO.
- **Track R** (restore VM-tested; `--full` gated behind R-1/R-3) — restore is real.
- **Track P** P-0a/P-0b/P-0c + P-1 stub + P-2/P-3/P-4 (the safety floor for agency).
- **Track L1** — the context engine; "never find files again."
- **Track L2** — RAG over your data, local-first default; "AI as foundation."
- **Track O** O-1 (on-device encryption-at-rest).
- **Track I** I-1/I-2/I-3/I-5 (Khmer render/type/translate/installer) **if resourced**;
  I-4 (Khmer search) lands **with** L1.
- **Track X** X-1, X-2, X-3, X-4, X-5, X-6, X-7 (the cross-cutting v1-blocking set).

### 1.x (after v1)

- **Track L3** (app-bus; "apps talk to each other"), **Track L4** (automation; "morning
  automated"), **Track O** O-2/O-3/O-4 (cloud sync + multi-device + Selendra anchoring),
  **Track X** X-8 (accessibility), X-9 (orchestration polish).

### Hard sequencing dependencies (encode these)

```
G-6 → G-7 → G-8  (signing key → publish target → SIGN+PUBLISH)   [G3]
G-8 → G-5        (signed repo MUST publish before installer ships on ISO)  [G3→G2]
G-1 + G-2 + G-3 → installer executes                              [G1]
G-4 → G-5        (PKGBUILDs before ISO inclusion)
R-1 + R-3 → R-6  (close GRUB leg + verify guard → --full allowed to run)
            ↑ the L1 "--full erases the index" confidentiality guarantee is GATED on this;
              if --full silently no-ops, the next user inherits plaintext (§2.1, R-6)
P-0a/P-0b/P-0c   land FIRST (one-liners) before any agency ships
P-1 stub         lands in P0 so L1/L2 code against fail-closed from day one
P-2 + P-3 + P-4 → L2-2  (egress boundary + sandbox + uniform gate BEFORE local tool-calling)  [§2.3]
L1 storage (§2.1) → L1-* → L2-1 (RAG) → L2-2 (tool-calling, with §2.3 mitigations)
I-1 + I-2 + I-3   ship TOGETHER (any subset = tofu); I-4 lands with L1
X-1 (CI/test) + X-2 (migration) underpin everything that ships
```

---

## 12. Explicitly NOT gaps / settled (don't re-litigate)

- **Inheriting the end-4 engine** — deliberate soft-fork (`UPSTREAM.md`); track upstream,
  diverge on identity surfaces.
- **Bare-environment app policy** — ship shell + system tools; users install apps.
- **Arch-only packaging** — Arch + archiso, by decision.
- **Index storage** — SETTLED: per-user under `@home`/`$XDG_STATE_HOME` (§2.1). `@var_index`
  superseded; do not re-open.
- **Single egress chokepoint** — SETTLED: root-owned netns/nftables enforcement +
  `org.koompi.Policy` brain + `koompi-syncd` sole egress (§2.2).
- **`sqlite-vec` as the default vector index** — MIT/Apache, single C file, no strings,
  co-located in the per-user SQLite DB. LanceDB is open-core → optional heavier tier only,
  never a default/transitive dep.
- **Khmer is a feature, English is the default** — two first-class languages; Khmer is not
  the positioning (the dead "Khmer-first moat" thesis is inverted).
