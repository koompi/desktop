# KOOMPI OS — Naming Convention

The canonical naming scheme for the OS, its releases, and its components.
Decided here so it isn't re-litigated per release.

## Product

**KOOMPI OS** — the product/brand name (unchanged).
Development name / repo: `koompi-desktop`.

## Release codenames — *Sacred Beings of Angkor*

Each major era is named after a Khmer mythological being carved across the
Angkor temples. The theme is short, internationally pronounceable, and
unmistakably Cambodian — no other distribution uses it. **Naga** debuts as v1:
the serpent guardian of water and temple thresholds, the foundational motif on
every Angkor balustrade.

### Roster (canonical order)

| Ver | Codename     | Being                     | Era theme |
|----:|--------------|---------------------------|-----------|
| 1   | **Naga**     | serpent guardian          | foundation, protection — the debut |
| 2   | **Apsara**   | celestial dancer          | grace + polish (the "face" era) |
| 3   | **Garuda**   | divine eagle              | speed / performance (Naga's eternal rival) |
| 4   | **Kinnari**  | half-bird maiden          | harmony — creative / media |
| 5   | **Makara**   | sea-beast of gateways     | thresholds — installer / onboarding |
| 6   | **Reachsey** | guardian lion             | strength, stability |
| 7   | **Hamsa**    | sacred goose              | wisdom, migration (major stack jump) |
| 8   | **Yeak**     | guardian giant            | hardened / fortified — security |
| 9   | **Hanuman**  | monkey warrior            | loyalty, power |
| 10  | **Mekhala**  | lightning goddess (Moni Mekhala) | the spark — a bold leap |

**Reserve pool** (genuine beings, for v11+ or substitutions): Kinnara (the male
counterpart to the roster's Kinnari), Vasuki (cosmic serpent — the churning-rope
of the Ocean of Milk relief), Ananta (the cosmic serpent Vishnu reclines on),
Lokeshvara (bodhisattva of compassion — the four faces of the Bayon), Tevada
(celestial deity), Erawan (three-headed divine elephant), Nandin (sacred bull),
Gajasimha (elephant-lion), Sovann Maccha (golden mermaid), Ream Eyso (storm
demon), Preah Thong & Neakareaj (the founding legend — the prince and the Naga
King).

> Not eligible: words that are *qualities*, not beings — e.g. *Sovann* (gold)
> alone. Keep the roster to actual mythological figures.

### Rules

- **Next era takes the next being** on the roster, in order.
- **A new codename marks a milestone, not a routine update** — a new installer,
  a major shell redesign, or a kernel/stack jump. Point updates keep the current
  name. This keeps "Naga" meaningful for ~6–12 months instead of burning the
  roster monthly.

## Version format

Arch base → **rolling system, named ISO eras** (snapshot model, not frozen
point-releases):

- Marketing: **`KOOMPI OS — Naga`**
- Technical: `KOOMPI OS 1.0`; in-era point updates are `1.1`, `1.2`, … and keep
  the **Naga** name until the next milestone era (**Apsara**).

## Component names (the "world")

Releases stay mythological; the *parts* take Khmer common-words so the system
feels coherent without diluting the roster. (Proposed — adopt incrementally.)

| Component            | Name        | Meaning / why |
|----------------------|-------------|---------------|
| Desktop shell        | **Bayon**   | the temple of faces → the face of the OS |
| Installer            | *koompi-installer* | named plainly — "installer" is already an active agent-noun; a passive place-name (Tonle) was rejected here |
| Software store       | **Psar**    | Khmer for *market* — instantly legible to locals |
| Welcome app          | **Suostei** | literally "hello" |
| Settings / control   | **Reach**   | royal, "to rule" |

AI assistant: intentionally unnamed for now (AI is the last phase). Candidate
when we get there: **Mealea**.

## Visual identity

Ship a **per-era wallpaper + boot splash of that being** — v1 boots into a
stylized multi-headed Naga. Gives instant brand recognition and a reason to
anticipate each release. The Naga also makes a clean minimal logo mark.

## Transliteration

Romanized names here are the **canonical ASCII forms** used in code, filenames,
and docs. Official Khmer script and diacritics are finalized by the KOOMPI team;
when in doubt, the Khmer team's spelling wins (e.g. *Tevada*, not *Tevoda*).
