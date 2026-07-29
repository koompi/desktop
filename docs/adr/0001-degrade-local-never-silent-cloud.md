# At/below the hardware floor, degrade local — never fall back to cloud silently

When KOOMPI OS cannot run a capability locally (e.g. a chat model does not fit in RAM on a
machine at or below **The Floor**), it drops to **Reduced-local mode** (embedding +
retrieval stay on; local chat off) or issues a **Consented refusal** — it never performs a
**Silent cloud fallback**. We chose this because the product's differentiator (**The Moat**)
is data ownership: the moment a low-spec machine silently ships a query to the cloud to "make
the feature work," the privacy-by-default claim is false for exactly the low-spec user we
target. The trade-off is real — silent cloud fallback would give a smoother out-of-box
experience on weak hardware — and we are deliberately rejecting that smoothness to keep the
moat honest.

The Floor itself is a working commitment of **8 GB RAM / x86-64-v2 / 64 GB storage**,
**provisional pending confirmation against the actual KOOMPI hardware fleet** (owner: KOOMPI
hardware/product). The rationale: 4 GB cannot simultaneously hold the embedding model
(~1.2 GB) + one chat model (~4 GB) + the L1–L4 daemons + Ollama, so a 4 GB floor would
*force* the silent-cloud path this ADR forbids.
