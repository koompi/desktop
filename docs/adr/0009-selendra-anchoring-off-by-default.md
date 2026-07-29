# Selendra anchoring is OFF by default; the default install has zero blockchain interaction

A default KOOMPI install performs **no blockchain interaction whatsoever.** Selendra is an
**opt-in** identity/ownership anchor (Track O-4, **1.x**), and even when enabled it is used
**only** for: the DID document, device public keys, key-rotation/revocation events, and a
**periodic signed Merkle root over the object manifest** ("these object-IDs are mine at time
T"), plus optional capability/sharing grants. **Never per-operation. Never `hash(plaintext)`** —
only salted commitments / `hash(ciphertext)` / Merkle roots.

## Why blockchain-minimal by default (the trade-off)

KOOMPI's founder comes from the blockchain world (Selendra), so a reader reasonably expects a
blockchain-forward design — chain-anchored everything, tokens in the loop. We deliberately chose
the **opposite default**:

- The data-ownership moat must rest on **cryptography the user controls** (on-device-by-default
  + E2EE), **not** on a chain. If the privacy story depends on a blockchain being up, queryable,
  and trusted, it is weaker, not stronger.
- A chain write per operation would leak metadata (timing, frequency, graph structure) — the
  exact thing the moat exists to prevent. Anchoring is therefore **rare and coarse** by design.
- Off-by-default keeps the **base OS dependency-free of any chain** — it boots, thinks, and syncs
  with Selendra entirely absent. Selendra adds *verifiable ownership/identity* for those who want
  it; it is never on the critical path for core function.

The cost is forgoing the obvious ecosystem-synergy story (and the founder's home-turf strength)
as a *default*. We accept it because credibility of the privacy moat outranks ecosystem
synergy, and the opt-in path still captures the synergy for users who choose it.

## Consequences

- Selendra is explicitly **out of scope for the v1 critical path** (prd §7 non-goal) and lands
  as **O-4 (1.x)** with the egress-audit UI.
- Anything proposing a per-operation or plaintext-derived chain write violates this ADR — it is
  a hard line, not a default to be quietly flipped.
- Pairs with [[0008-koompi-cloud-offer-both-operated-and-self-host]]: sync (O-2/O-3) and anchor
  (O-4) are independent opt-ins; neither requires the other.
