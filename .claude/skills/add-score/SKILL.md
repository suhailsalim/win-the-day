---
name: add-score
description: Add or modify a deterministic score or ring metric (ScoreEngine/EatingScorer/RingEngine family). Use when changing score formulas, adding ring sources, or adding custom ring metrics.
---

# Add / change a score or ring metric

## Non-negotiable design rules
1. **Pure enum, Foundation-only.** Scores are `enum` pure functions of value-type inputs
   (`ScoreEngine`, `EatingScorer`, `PrayerClassifier`, `RingEngine` are the family). No
   `@MainActor`, no managers, no AI — the LLM never computes a number.
2. **Inputs come as a snapshot.** `AppStore` builds a Sendable value context on the main actor
   and hands it in; the engine never reads UserDefaults/HealthKit itself.
3. **Fail soft, never fake.** Missing input → sub-score drops out and weights renormalize, or the
   whole score reports unavailable (grey "—"), NEVER a misleading 0. A genuinely computed 0 is a
   valid stored value. Baseline-relative scores gate behind `sampleNights ≥ 7` ("calibrating").
4. **Optional cached fields** on `Entry` use `nil` = not-computed (so a real 0 survives decode).
   Follow add-persisted-field skill for any new cached field.

## Adding a custom ring metric
1. `Models.swift` → `RingMetric`: new case (unknown-tolerant decode already handles old saves).
2. `RingEngine.compute`: switch case computing `RingResult` from `RingContext` — if the context
   lacks the value, extend the context struct AND `AppStore`'s context builder.
3. Ring editor picker: add the metric (feature-flag it off if its data source doesn't exist yet —
   never offer a ring that silently reads 0).
4. Bands: fraction = `clamp(value/goal, 0…1)`; band colors <0.34 / 0.34–0.66 / ≥0.67 unless the
   ring has a custom color (custom color changes the arc, band still drives the caption).

## Verify
- Unit tests in `EngineTests/` (determinism: same inputs → same outputs; missing-input
  renormalization; clamps). Engines are the most testable code in the repo — test them.
- Recompute-on-load semantics: changing a formula recomputes when a day is opened; no migration.
- Factors: expose `[ScoreFactor]` so the ring detail sheet and "Explain this ring" stay honest.
