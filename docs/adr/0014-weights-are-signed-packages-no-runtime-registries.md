# Model weights are signed packages; OS services never pull from runtime registries

**Every default model (embed, chat, STT, TTS, guard) ships as a signed `[koompi]`
package into a system-wide read-only store, and runtime registry pulls (ollama.com,
HF auto-download) are disabled in OS services.** A model fetch is an *update* (pacman,
snapshot-protected), never a side effect. The license CI gate
([[0006-default-models-bge-m3-and-license-gate]]) runs at packaging time; weights get
the same signing chain as binaries ([[0005-package-signing-and-repo-trust-model]]).

Why:

1. **The Moat.** A registry pull is unconsented egress inside the privacy product —
   the exact behavior the egress chokepoint (roadmap §2.2) exists to prevent.
2. **Shared lab machines.** Per-user model dirs (`~/.ollama`) duplicate 2–5 GB per
   student; one read-only copy per machine, mmap-shared, serves every user
   (architecture §10's multi-user invariants).
3. **The RAM/bandwidth crisis.** Weights ride the ISO / first-boot seed and pacman
   deltas — not per-user downloads on Cambodian bandwidth (brainstorm §87, U5).
4. **Provenance.** "Which weights answered this?" must be answerable from the package
   database, not a mutable cache.

Consequences: the model runtime must serve from a read-only path — default is
**`llama-server` (llama.cpp) managed by `assistantd`**; this also inherits llama.cpp's
upstream NPU backends (OpenVINO, Hexagon) with no toolchain change. If Ollama is kept
at all it is a dev convenience: vendored, registry disabled, never a service
dependency. KOOMPI owns model-packaging cadence (a real, accepted maintenance cost).
Users may still hand-import models into their own user scope — that is their consent,
and it is logged.

**Open (owner: packaging):** the store's subvolume placement — model updates rewrite
gigabytes, so the location must not bloat `@` snapshots (candidates: a dedicated
subvolume excluded from rollback, with integrity via package verification).
