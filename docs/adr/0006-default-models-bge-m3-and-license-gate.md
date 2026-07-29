# Default models: BGE-M3 embedder (welds the schema dim), clean-license chat tier, build-time LICENSE gate

**BGE-M3 (MIT, 1024-dim, Khmer-capable) is the default embedder.** This **welds
`embedding_dim=1024`** into the index schema (`vec_chunks float[N]`), so it is **high
lock-in** — changing the embedder later forces a destroy-and-re-embed of the entire corpus.
We chose it because it is the one embedder that is *both* clean-license *and* Khmer-capable;
it must be fixed before any L1 schema code lands ([[0001-degrade-local-never-silent-cloud]]
sets the Floor that sizes it).

**Chat defaults to a clean-license TIER** (Sailor2 / SEA-LION family, Apache/MIT), pinned to
an **exact model + quant per RAM tier at build time** — 8 GB Floor: a ~1–3B Q4 Khmer-capable
model; 16 GB+: Sailor2-8B. The v1 **reasoning-model tier is cut** (no usably-small reasoning
model fits the Floor).

**Model weights are first-class, license-gated dependencies.** A CI step reads each bundled
weight's actual `LICENSE` file and **fails the build** on use-restricted terms — explicitly
rejecting Qwen-research, Gemma custom terms, and Llama-MAU as bundled defaults. Verify the
file, never SEO claims.

**Honest consequence:** floor-tier Khmer chat is **modest**; strong Khmer is a **16 GB+**
experience. At the Floor the fallback is reduced-local or a *consented* cloud option, never a
silent cloud fallback ([[0001-degrade-local-never-silent-cloud]]).

## Open (owner: KOOMPI model eval)

The exact chat model per tier is pinned at build **after a Khmer eval** — no specific model
mandated yet.

## Addendum — 2026-06-11 (evidence update; the Open item narrows)

Verified facts (sources: brainstorm §87) that sharpen, not change, this decision:

- **Chat candidates are now concrete:** **Sailor2 1B/8B** (Apache-2.0, Qwen2.5-base —
  passes the gate) for the Floor and 16 GB tiers; SEA-LION v4 *Qwen-based* variants
  are eligible, while *Gemma-based variants fail the license gate by the policy
  above*. The pin happens via gate **G-KM-CHAT-1** (`blueprint.md §3`), which is the
  named form of this ADR's Open item.
- **SEA-LION-Embedding (released 2026-03)** is the first credible BGE-M3 successor
  for SEA retrieval. The welded-dim risk this ADR accepted is therefore **dated, not
  hypothetical**: the era-tag + re-embed runbook moves from roadmap nicety to **v1
  schema requirement**, and succession happens only through gate **G-EMB-2** (must
  beat BGE-M3 on KOOMPI-EVAL-RETRIEVAL, pass the license gate, and execute the
  runbook in CI).
- **SEA-Guard (2026-02)** is noted as the 1.x guardrail-model candidate for
  Khmer/SEA-language agency.
