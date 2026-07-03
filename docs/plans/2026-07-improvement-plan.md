> **Verification caveat.** This plan targets the **Win the Day** iOS app, which is **not** the repository this document lives in. Every "verified at `X.swift:NNN`" reference below (`ReadinessScorer.swift:18`, `Models.swift:929–932`, `TodayView:175`, lines 1520/1382/786) is a claim about the iOS codebase and **must be re-confirmed against that checkout** before relying on it — it cannot be verified from the monorepo. The `node:sqlite`/`packages/config` env-door conventions referenced elsewhere are the web platform's, not this iOS target's.

# Win the Day — Implementation Plan: Rings, Scores, Coach, and Nutrition Revamp

**Owner:** Suhail · **Author:** Lead engineer · **Date:** 2026-07-02 · **Target:** Win the Day (SwiftUI, iOS, on-device)

---

## 1. Framing — what's changing and why

This plan reshapes Win the Day around a single idea: **a row of adjustable, Whoop-style rings on Today**, each backed by a **deterministic, on-device score**, plus a **smarter, tool-calling AI coach** and a **rebuilt food/nutrition stack**. It touches seven feature areas, but they share three engines (a ring registry, a score registry, a food lookup service) and one coach tool layer, so the work compounds rather than fragments.

Four guiding principles constrain every decision below:

| Principle | What it means in practice |
|---|---|
| **Local-first, no backend** | No WeatherKit/CloudKit (free Apple signing). Scores, prayer classification, and the bundled food DB all run on-device. Chat threads and tips live in UserDefaults; the only network calls are the user's chosen AI provider + free Open-Meteo/Open Food Facts/USDA. |
| **Deterministic on-device scores** | Every score (Sleep, Readiness, Active, Eating, Prayer-on-time) is a **pure function** (`enum` in the `ReadinessScorer` style) of HealthKit signals + logged data + rolling baselines. No LLM ever computes a number. Same inputs → same score, unit-testable. |
| **Tolerant Codable everywhere** | Every persisted struct gets a custom `init(from:)` with `(try? c.decode(...)) ?? default`. New fields never break old saves; missing data fails soft (compute what's available, renormalize, mark "partial") rather than showing a misleading `0`. Optional-typed fields use `nil` as "absent," **never `0`** (a real computed `0` — e.g. red-band Readiness — must survive a decode round-trip). |
| **Provider-agnostic AI, degrade-not-fail** | The coach's new tool layer normalizes Anthropic / OpenAI-compat / Gemini wire formats behind one `CoachProvider` protocol. Providers **without** reliable tool/JSON support (Apple Intelligence, non-tool Ollama models) degrade to the existing text path and to deterministic fallbacks — never a crash or empty bubble. Vision/estimate flows are untouched. |

The existing manager pattern (`AppStore` `@MainActor` hub + `HealthManager`/`WeatherManager`/`PrayerManager` + `AIEstimator` stateless router) is preserved. New engines are pure enums; new managers follow the existing `ObservableObject` shape; all mutations route through `mutate()`/`updateModules()`/`publishSnapshot()`.

---

## 2. Shared foundations (build these first — multiple features depend on them)

Three cross-cutting pieces are dependencies for the feature work. They are the spine of the whole plan.

### 2.1 Generic ring registry + `RingEngine`

A single config-driven ring model so Today's ring row, custom rings, and score rings are one system, not three.

- **`RingDef`** (tolerant Codable, `Identifiable`): `id`, `source: RingSource` (`.sleep|.readiness|.active|.eating|.prayer|.custom`, unknown→`.custom`), `title`, `metric: RingMetric` (custom-only: `.prayersOnTime|.hydrationPct|.studyGoalPct|.workHours|.proteinPct|…`, unknown→`.unknown`), `goal: Double = 100`, `unit`, `colorHex: UInt = 0`, `enabled`, `order`. Stored in `AppData.rings: [RingDef] = []` inside the existing `suhail_health_v2` blob (no new key), seeded to defaults when empty (exactly like `data.habits`).
- **`RingEngine`** (pure `enum`, non-isolated, unit-testable): `static func compute(_ def: RingDef, entry: Entry, ctx: RingContext) -> RingResult`. `RingContext` is a small `Sendable` **value snapshot** built by `AppStore` on `@MainActor` (targets, water target, habit score, prayer bands, study/work goals, focus minutes) so the engine stays pure and thread-safe. Built-in sources delegate to the score registry (§2.2); `.custom` switches on `metric`.
- **`RingResult`** (not persisted): `fraction (0…1)`, `value`, `displayValue`, `caption`, `band (.low/.mid/.high)`, `available: Bool`, `factors: [ScoreFactor]` (reused for the expand sheet). When a source has no data (e.g. Active with no Watch and no kcal), `available=false` and the ring renders **grey/"—", not 0**.
- Ring fraction is always `clamp(value/goal, 0…1)`; band color by fraction (<0.34 coral, 0.34–0.66 amber, ≥0.67 sage) unless `colorHex ≠ 0`. Whoop banding (green ≥67 / yellow 34–66 / red <34) for Readiness.
- **All ring sources ship** (Sleep, Readiness, Active, Eating, Prayer-on-time + user-created customs). The user chooses **how many rings display — 3 or 4 — via `AppSettings.visibleRingCount`** and **which** rings + their order in the ring editor. A hard cap of 4 governs layout + the snapshot; `publishSnapshot()` slices to `visibleRingCount` (≤4) so the App-Group payload never overflows.
- **Custom rings** are user-created `RingDef`s (`.custom` source): pick a metric, title, goal, unit, and color swatch. This is the full "custom ring" surface — see §4.3 for the metric implementations.

`AppStore` gains `updateRings(_:)`, `visibleRings`, `ringResult(_:)`, `moveRing(from:to:)`. `RingGauge` is refactored out of the existing `TodayView.readinessRing` (generalized to `fraction/value/color/label` with `.animation(.easeOut, value: fraction)`).

### 2.2 Score registry — `ScoreEngine`

One pure enum supersedes `ReadinessScorer` (which today returns `{readiness, sleepScore, factors}` — verified at `ReadinessScorer.swift:18`). It emits three sibling scores plus Eating, all deterministic:

- `ScoreEngine.Inputs` (sleep, HRV, RHR, respiratory rate, wrist-temp delta, prior-day strain `S` (§2.2.1), daily active-kcal, `checkIn: DayCheckIn`, `baselines: ScoreBaselines`, age/maxHR).
- `ScoreEngine.Result { sleepScore, readiness, activeScore: Int; activeAvailable: Bool; factors: [ScoreFactor] }` with `computeSleep()/computeReadiness()/computeActive()`.
- `ReadinessScorer` is kept as a **thin delegating shim** so the one call site (`AppStore.computeReadiness`, ~line 1520) and existing UI compile unchanged during the transition.
- **`ScoreBaselines`** (own key `score_baselines_v1`): rolling mean+sd for `ln(HRV)`, RHR, respiratory rate; 14–30-night median sleep-need + median daily strain `L0`; 4-night mid-sleep history; 3-night capped sleep debt; `typicalActiveKcal` (median active-kcal); `sampleNights`. Recomputed nightly so morning scoring is O(1). **Gate all scores behind `sampleNights ≥ 7`** (grey "calibrating (n/7)") — this is mandatory or z-scores swing wildly.

#### 2.2.1 Single strain source of truth (resolves the double-definition)

There is **exactly one** strain quantity `S ∈ [0,21]`, computed by `ScoreEngine.strain(...)`, and **both** Active (§4.1) and Sleep-Need (§4.1/§7 `SleepPlanner`) consume it. `SleepPlanner` and `ScoreEngine` never redefine strain independently.

```
S = clamp(6 + 8·log2(1 + activeKcal / typicalActiveKcal), 0, 21)
   typicalActiveKcal = baselines.typicalActiveKcal (median; fallback 400)
```

`activeKcal` (`HKQuantityTypeIdentifier.activeEnergyBurned`) is available on **iPhone alone** (no Watch), so `S` — and therefore Sleep-Need's `StrainAdd` — is always computable. If a **paired Watch** is present, per-minute HR is additionally used to refine Active's saturation (§4.1) but **not** to redefine `S`. This removes the circular dependency: Sleep-Need depends on `S` (kcal-derived, always available), not on a prior Active score.

`EatingScorer` and `PrayerClassifier` are siblings in the same pure-enum family (§4.2, §4.3).

### 2.3 Provider-agnostic tool-calling abstraction

The neutral vocabulary the three wire families converge on, plus one protocol:

- **Neutral core:** `CoachToolSchema {name, description, parametersJSON}`, `CoachToolCall {id, name, arguments}`, `CoachToolResult {callId, content, isError}`. Nothing else in the app knows provider JSON.
- **`protocol CoachProvider { func send(system:history:tools:) async throws -> CoachProviderResponse }`** with three adapters:
  - `AnthropicCoachProvider` (`tool_use` blocks, native object `input`, `tool_result`-first user block).
  - `OpenAICompatCoachProvider` (**one class** reused for OpenAI/OpenRouter/DeepSeek/Ollama/OllamaCloud — collapses 5 of 8 providers; JSON-decode the stringified `arguments`, echo `role:tool`).
  - `GeminiCoachProvider` (`functionDeclarations`; wrap scalar results in `{result:…}`). **Call-id scheme:** because Gemini has no wire-level call id and `functionResponse` matches by `name`, the runner assigns ids `"\(name)#\(ordinalWithinTurn)"` in **deterministic model-emission order**, and when the same tool is called twice in one turn the two `functionResponse` parts are emitted back **in that same order** with matching names. `AgentRunner` preserves emission order for id synthesis and response assembly (see below).
- **`AgentRunner`** (`@MainActor`) — **serial, ordered execution** (see §2.3.1 for the concurrency contract): loop model → parse tool calls in emission order → execute each tool (errors → `isError:true` instructive message the model can recover from) → assemble `tool_result`s in the same order → model. **`maxIterations = 6`** guard.
- **`maxIterations` terminal behavior (never an empty bubble):** if the model is still requesting tools at iteration 6, the runner issues **one final model call with `tools: []`** (forcing a natural-language completion) and returns that text. If even that yields empty text, it returns a deterministic "I gathered your data but couldn't finish the reasoning — here's what I found: …" summary built from the last successful tool results. The coach **always** returns non-empty assistant text.
- **Capability gating:** `supportsTools(settings)` — true for Anthropic/OpenAI/Gemini/OpenRouter/DeepSeek; Ollama gated **both** on a tool-trained model allowlist (llama3.1+/qwen2.5+/mistral-nemo/command-r+) **and** a one-time runtime probe (a trivial tool call on first use; cache the result per model+endpoint) so renamed/quantized local models that fail the probe fall back to text rather than silently mis-parsing; **false for Apple** → falls back to the existing text path (§5 fallback).

#### 2.3.1 Concurrency contract (resolves the `@MainActor` vs TaskGroup contradiction)

Read/write tools call `@MainActor` `AppStore` methods, so **tool execution is serial on the main actor** — there is no `TaskGroup`-parallel execution of tools that touch `AppStore`. This is the correct and compiler-accepted design (parallel child tasks hopping back to `@MainActor` would serialize anyway and would data-race on non-`Sendable` `AppStore` state). Tools are cheap in-memory reads, so serial execution is fine. If a future tool needs real off-main work (e.g. an OFF network fetch), it takes a `Sendable` snapshot of the inputs it needs and does the I/O off-actor, returning a `Sendable` result — but no such tool ships in v1.

### 2.4 Food lookup service

The four-tier, self-warming chain (research-backed priority, verified foods never touch the LLM):

1. **User library** (`data.catalog`, highest trust, offline)
2. **Bundled read-only USDA SQLite** (`FoodDB.sqlite`, ~4–10MB, FTS5 index — **Foundation Foods + SR Legacy only** by default; see licensing below re: Branded)
3. **Live external** — Open Food Facts for **barcode scans only**; optional USDA `/foods/search` (key from Keychain, never bundled)
4. **`AIEstimator.parseEntries()` LLM guess** — last resort for restaurant/freeform

**Rate limiting (concrete, enforced).** Only tier 3 ever calls OFF. A single `OFFRateLimiter` token-bucket component guards **every** OFF request: barcode lookups (budget 15/min) share one bucket; search (10/min) is a **separate** bucket, but **search-as-you-type never calls OFF at all** — search is served only from tiers 1–2 (local). If a barcode burst would exceed the bucket, the limiter defers/drops with a soft "try again in a moment," never risking an IP ban. The "respects OFF's search cap" language is retired because no code path issues OFF search requests in v1.

**Licensing (attribution + share-alike handled end-to-end).** Each downstream hit is written **up** into `data.catalog` tagged `source: FoodSource` (`user|usda|curated|computed|openfoodfacts|llm`).

- **USDA (public-domain compilation).** Foundation Foods + SR Legacy are bundled. **Branded Food data is NOT bundled by default**: individual product **names, brand marks, and label images are third-party IP**, not USDA's to sub-license, so shipping "top-N branded" rows in the IPA needs a per-item legal review we do not gate the release on. Branded items instead arrive only via **live OFF/USDA-search at runtime** and are tagged `openfoodfacts`/`usda`.
- **OFF (ODbL, share-alike).** Because ODbL is a **database** share-alike license, **commingling OFF rows into `data.catalog` and then exporting/syncing that catalog is redistribution of an ODbL-derived database.** To stay clean: (a) OFF-sourced rows are stored in a **logically separate partition** distinguishable by `source == .openfoodfacts`; (b) the **`BackupBundle` export excludes `.openfoodfacts` rows by default** (only `user`/`llm`/USDA-public rows travel), so the user's exported catalog is not an ODbL-derived DB; (c) if the user opts into a "full export including OFF-sourced items," the exporter attaches the **ODbL attribution + share-alike notice** and marks the whole bundle accordingly. This is the guardrail that makes Q10 backup safe.

> **iOS note:** the monorepo's `node:sqlite` / `packages/config` env-door conventions are the **web platform's, not this iOS target's**. Use Apple's C `SQLite3` (FTS5 is compiled into the system `libsqlite3`) and keep external calls on the app's existing direct-`URLSession` pattern (same as `lookupBarcode`).

---

### 2.4.1 Indian & South-Indian food coverage

USDA FoodData Central is already bundled (US-government public domain — unconditionally redistributable in a closed-source app). No Indian food-composition table matches that cleanliness: virtually every dataset with real Indian/Kerala nutrient values traces back to **ICMR-NIN's IFCT 2017**, whose copyright page permits personal-use reproduction with attribution but explicitly forbids storing/reproducing the data *"in any electronic format for creating a product without the prior written permission of the National Institute of Nutrition, Hyderabad."* Bundling in a shipped app *is* "creating a product." A downstream repackager applying MIT/CC-BY/CC-BY-SA/"Open" to IFCT-derived numbers **cannot cure this** — you can't license rights you don't hold (license-laundering). India also has no US-style "government works are public domain" rule, so age/official-publisher status does not free IFCT, Gopalan NVIF, or FSSAI docs.

#### Verdict table

| Dataset | Coverage | License | Bundle? | Why |
|---|---|---|---|---|
| **USDA FoodData Central** (bundled) | Generic global ingredients + a few generic FNDDS "dosa/idli" survey items | US Public Domain | ✅ | Unconditional; zero attribution/obligations. Ingredient backbone + compute-from-recipe basis. |
| **Open Food Facts — India** (~10k products) | Branded/**packaged** items only (batters, ready-mixes, snacks); no cooked dishes | ODbL 1.0 (data) + DbCL; images CC BY-SA 3.0 | ✅ | Closed app = ODbL "Produced Work" (allowed). Bundle **data only**, isolated table, with attribution. See export rule below. |
| **IFCT 2017** (ICMR-NIN) | 528 raw ingredients × 151 components; **no cooked dishes** | © ICMR-NIN, no open license | ❌ | Copyright forbids electronic reproduction "for a product" w/o NIN written permission. Use as unbundled compute reference only, or get NIN sign-off. |
| **INDB** (Anuvaad/Jaacks) | **1,014 cooked recipes** — verified strong Kerala/S-Indian (idli, dosa, sambar, appam, puttu, avial, thoran, rasam, payasam…) | Paper CC BY; **repo has no LICENSE**; values IFCT-derived | ⚠️ | Richest dish source, but CC BY covers the paper not the data, and IFCT underlay is NIN-encumbered. Bundle only after written data terms from Anuvaad **and** IFCT clearance from NIN. |
| **nodef/ifct2017** (npm/JSR) | IFCT reproduction, raw foods | **AGPL-3.0** (was MIT) atop IFCT | ❌ | Double blocker: AGPL copyleft is incompatible with a closed-source app, and MIT/AGPL can't launder NIN's copyright. |
| Kaggle/HF INDB-derived CSVs (batthulavinay CC BY-SA, adarshzolekar CC BY, kashyap077 **CC BY-NC-SA**, gijoe707/syedkhalid076 **Unknown**) | Small dish/ingredient subsets | Mixed; NC / Unknown / SA | ❌ | NC forbids commercial ship; "Unknown" = no grant; the rest are still IFCT-tainted upstream. |
| Gopalan NVIF / FSSAI | Older raw foods / regulatory text | © ICMR-NIN / Govt-of-India, no open license | ❌ | Same NIN encumbrance, nutritionally inferior; FSSAI has no independent bundleable dataset. |

#### Recommended strategy (license-clean, no waiting on NIN)

Ship without any IFCT-derived table. Cover Kerala/South-Indian food in four layers, all clean:

1. **Generic ingredients — bundle USDA FDC** (already in) as the public-domain ingredient backbone. Where a truly-open Indian-specific ingredient set exists it can be added, but no such table is cleanly licensed today, so USDA + computed values is the safe default.
2. **Branded/packaged Indian foods — live from Open Food Facts India (ODbL).** Same rules as the main plan: keep OFF data in its **own isolated table/DB**, show "Data from Open Food Facts, ODbL" attribution (per-product where shown), and **do not bundle OFF images** (CC BY-SA 3.0 is viral).
3. **Regional prepared dishes — compute, don't copy.** Author your own Kerala/South-Indian recipes (idli, dosa, sambar, appam, puttu, avial as ingredient lists + cooking yields/retention factors) and compute dish nutrition from the **bundled generic USDA ingredients**. Recipe formulas are facts/procedures; the computed values become *your* dataset, tagged `source=computed`. INDB/IFCT may be consulted as an **unbundled** cross-check only.
4. **Curated Kerala/South-Indian starter list — hand-authored**, values sourced from public-domain USDA/clean references (never transcribed from IFCT/INDB), tagged `source=curated`. Seeds common everyday dishes so the app is useful on day one without recipe expansion.
5. **Last-tier gap-fill — LLM estimator** for arbitrary restaurant/home dishes no table covers, grounded on the bundled USDA/computed/curated values as retrieval context. Never the primary path for dishes the curated/computed layers already cover accurately.

If richer authoritative coverage is later wanted, the *only* clean unlock is written permission from **ICMR-NIN Hyderabad** (IFCT) and **Anuvaad** (INDB) — pursue in parallel, don't block shipping on it.

#### Fit into the existing 4-tier lookup chain + ODbL export rule

- **Tier 1 — bundled exact match:** USDA generic ingredients + the hand-authored **curated** Kerala/S-Indian starter list (`source=curated`).
- **Tier 2 — branded/barcode:** Open Food Facts India (`source=off`), served live, isolated table.
- **Tier 3 — computed dishes:** recipe-composed values from bundled USDA ingredients (`source=computed`).
- **Tier 4 — LLM estimator:** grounded fallback (`source=llm`) for the long tail.

Every row carries a `source` tag so provenance and license drive behavior. The **ODbL export-exclusion rule** from the main plan applies unchanged: only OFF (`source=off`) rows are ODbL-encumbered, so any user-data/database export must **exclude the OFF partition** (or regenerate it live from OFF) — the isolated partitioning keeps share-alike from bleeding into USDA (public domain), curated, computed, or LLM data or into app code. USDA, curated, and computed rows are freely redistributable; LLM rows are your own output.

---

## 3. Rings & ring engine (Today's new hero)

**What changes:** A configurable row of **3–4 concentric rings** is pinned to the top of Today (new core module key `"rings"`, inserted first in `defaultOrder`, added to `coreKeys` so it can't be disabled but can be reordered). The single readiness ring becomes the drill-down detail surface.

**Data model:** §2.1 (`RingDef`, `RingResult`, `AppData.rings`). `ModulePrefs` gains `"rings"` in `defaultOrder` + `coreKeys` + a `label("rings") → "Readiness rings"` case. The tolerant order migration in `init(from:)` (verified at `Models.swift:929–932` — it appends missing default keys) means **old saves automatically gain the ring row**. `SharedSnapshot` gains `rings: [SnapshotRing] {title, pct, display, colorHex}`, capped at 4.

**Views/services:** `RingEngine.swift` (§2.2), `RingRowView` + `RingGauge`, `RingDetailView` (large ring + factor list reusing the `sleepModule` ±delta row style), `RingEditorView` (drag-reorder ≤4, enable/disable, add built-in/custom, color swatch grid). Wired via `case "rings": ringsModule` in `moduleView` and a gear in the section header + a row in `ModulesEditorView`.

**UI:** HStack of ~72pt rings above the tip card, animating trim on value change, serif center value + title below. Unavailable rings render grey with "—". Tap → detail sheet. Custom `colorHex` overrides the arc but **band still drives the caption** (a green-accented ring in a red band still reads "Take it easy" in text) to avoid confusion.

**AI — per-ring "Explain this ring":** each `RingDetailView` has an **"Explain this ring"** button that routes the ring's `factors` + score through the existing `chat()` path (all 8 providers, deterministic text fallback when tools/JSON unavailable). This is **in scope for v1** (M3), not deferred — it is a user-requested feature and needs zero new routing.

---

## 4. Score algorithms (the explicit formulas)

All scores are `enum` pure functions consuming HealthKit + logged data + `ScoreBaselines`. `sigmoid(x)=1/(1+e^{-x})`. HRV is **ln-transformed** (SDNN is right-skewed) and taken as the **median of overnight-window samples** (Apple exposes SDNN only, sampled sparsely — a single "latest" value is too noisy).

### 4.1 Sleep, Readiness, Active (WHOOP-style)

**Data model:** The **Readiness score** is the WHOOP-style evolution of the app's existing `Entry.readiness: Int` — it is **recomputed in place on load** by the new `ScoreEngine`, so there is **no new score field and no migration** (the next time a day is opened its readiness is overwritten by the new formula; nothing is lost). `Entry` gains only `activeScore: Int?` (**optional** cached Int; `nil` = not computed, so a genuine `0` survives) + `checkIn: DayCheckIn` (tolerant): `bedtimeIntentEpoch`, `soreness/stress/mood (0–3)`, `alcohol (0–3)`, `lateCaffeine`, `illness`. `SharedSnapshot` keeps `readiness` (old widget binaries keep working unchanged) and gains `activeScore`.

**Sleep (0–100):**
```
Sleep = 0.50·Sufficiency + 0.20·Efficiency + 0.20·Consistency + 0.10·StageQuality
Sufficiency = 100·min(asleepMin / SleepNeed, 1)
  SleepNeed(min) = Baseline + StrainAdd + min(SleepDebt, 120)
    Baseline    = 14–30-night median asleepMin (fallback 480)
    StrainAdd   = 60 · 1.7 / (1 + e^((17 − S)/3.5))    // S = single strain source of truth (§2.2.1)
    SleepDebt   = capped Σ over last 3 nights of max(0, Need_n − slept_n)
Efficiency  = 100·(asleepMin / inBedMin)          [fallback 90 if inBed unknown]
Consistency = 100 − clamp(MAD(midSleep over last 4 nights, min), 0,120)/120·100
StageQuality= hasStages ? 100·clamp((deepMin+remMin)/asleepMin / 0.40, 0,1) : 100 (weight redistributed)
```
`StrainAdd` reads the kcal-derived `S` (§2.2.1) — **no dependency on a prior Active score**, so no circular dependency and no Watch requirement.

**Readiness (0–100), HRV-dominant, baseline-relative:**
```
Readiness = 100·(0.55·HRVsub + 0.25·RHRsub + 0.10·SleepSub + 0.05·RespSub + 0.05·TempSub)·SelfReportMult
HRVsub  = sigmoid( (ln(SDNN_today) − lnHrvMean) / lnHrvSd )
RHRsub  = sigmoid( −(RHR_today − rhrMean) / rhrSd )     [inverted; lower better]
SleepSub= todaySleepScore/100
RespSub = sigmoid( −(resp − respMean)/respSd )
TempSub = clamp(1 − |wristTempDelta|/1.5, 0,1)
SelfReportMult ∈ [0.85, 1.0]: ×0.93 alcohol≥2, ×0.96 alcohol==1, ×0.96 lateCaffeine,
  ×0.95 illness, −0.02·soreness, −0.02·stress   (floor 0.85)
```
Missing sub-scores drop out and weights renormalize. **Always also surface the sensor-only Readiness (mult=1)** for transparency — bounding the multiplier and showing the raw number is a hard trust guardrail. WHOOP bands: green ≥67 / yellow 34–66 / red <34.

**Active (0–100), log-saturating strain — computable without a Watch:**

Active is a **primary ring** because its input `S` (§2.2.1) is always available from iPhone `activeEnergyBurned`.
```
Active = 100·(1 − e^(−S / Sref)),   Sref = 10.5   // half-scale strain → ~63; full strain 21 → ~86
  S = clamp(6 + 8·log2(1 + activeKcal / typicalActiveKcal), 0, 21)   // §2.2.1, kcal-only, always available
Watch refinement (optional, when paired Watch → per-minute HR exists):
  replace the kcal proxy inside S's activeKcal term is unchanged; additionally compute
  HRload = Σ over HR-minutes of e^(3·f),  f = clamp((HR − RHRbase)/(maxHR − RHRbase), 0,1),
  and blend: S_final = max(S_kcal, clamp(6 + 8·log2(1 + HRload/typicalHRload),0,21)).
  maxHR = observed or 208 − 0.7·age. This only *sharpens* Active on Watch users; it never gates it.
```
Because `S` is kcal-derived, Active **never** renders 0-for-lack-of-Watch. If even `activeKcal` is missing for the day (no motion data at all), `activeAvailable=false` and the ring greys out.

**Ordering note:** Sleep-Need reads the **kcal-derived `S`** for the relevant day, so Sleep and Active can be computed in either order; neither blocks the other.

**Views/services:** `ScoreEngine.swift`, `HealthManager` fetches (overnight-median HRV, respiratory rate, wrist temp, active-kcal, optional per-minute HR, mean+sd baselines), `AppStore.computeScores()` (evolves `computeReadiness`), `AppStore.updateBaselines()`, `CheckInSheet.swift`. `sleepModule` becomes a **three-ring row** (Sleep/Readiness/Active) with grouped factor lists and a "sensor-only" transparency line. `coachContext()` gains one line of the three scores + notable check-in facts.

**First-launch historical import (unblocks calibration).** On first launch (after HealthKit auth), `HealthManager.backfill()` imports the **last 30 days** of sleep, HRV, RHR, respiratory rate, wrist temp, and active-kcal and runs `updateBaselines()` once, so `ScoreBaselines.sampleNights` can immediately reach ≥7 for users with existing history. Users with no prior HealthKit data still see "calibrating (n/7)" until 7 real nights accrue — but the common case (existing Apple Health history) is calibrated on day one rather than after 1–4 weeks.

### 4.2 Eating Score (0–100) + weekly weight projection

**Data model:** `EatingScore` cached on `Entry.eating` (`total`, sub-scores, `partial`, `netKcal`). `Targets` gains `ageYears/heightCm/sexMale/goal/sodiumLimitMg` (BMR/TDEE + goal-band). `AITotals` gains optional `sodiumMg/satFatG/addedSugarG/vegServings` (omit-safe). `NutritionRDA` reused unchanged for micro coverage.

```
EatingScore = round( Σ (weightᵢ · subᵢ) / Σ weightⱼ  over AVAILABLE sub-scores )
   weights: CalorieFit 0.25, Protein 0.20, Macro 0.15, Micro 0.15, Timing 0.10, Quality 0.15
   partial=true whenever any sub-score is unavailable and weights were renormalized.

BMR (Mifflin–St Jeor): male 10·kg+6.25·cm−5·age+5 ; female −161
TDEE = max( BMR · 1.10 + activeKcal , BMR · 1.15 )     // see resting-day floor below
```

**TDEE with a resting-day floor (removes the perverse rest-day surplus).** The naïve `BMR + activeKcal` under-counts TDEE on low-activity days (it omits the thermic effect of food and baseline NEAT), making maintenance intake read as a surplus. We therefore add a **+10% TEF/NEAT factor** on top of BMR **and** clamp TDEE to a **resting-day floor of `1.15·BMR`** so a true rest day (`activeKcal≈0`) never collapses to bare BMR. This keeps CalorieFit centered on genuine maintenance rather than punishing rest days.

```
CalorieFit: band center = maintain TDEE±5% / cut TDEE−400 / bulk TDEE+275;
   CalorieFit = 100 − min(100, 100·devBeyondBand/(0.35·TDEE));
   ×1.5 deficit penalty ONLY when intake < 1.2·BMR  (unchanged — but TDEE floor above means
     the floor and the penalty no longer both fire spuriously on low-activity maintenance days)
Protein  = 100·min(intake / (factor·kg), 1),  factor = 1.6 maintain / 2.0 bulk / 2.2 cut
           (fallback Targets.protein when weight unknown)
Macro    = mean of AMDR fit for carb 45–65% / protein 10–35% / fat 20–35% of energy (linear to 0 at ±15pp)
Micro    = 100·MAR = mean of min(intake_n/RDA_n, 1) over logged panel (available only when ≥5 nutrients known)
Timing   = gap≥3h ? 100 : linear→0 at 0h, steepest <1h  (mealTimes["dinner"] vs sleep.bedEpoch)
Quality  = see below — availability-gated HEI proxy
```

**Quality sub-score — explicitly availability-gated (fixes the illusory-weight problem).** Quality is a coarse HEI proxy needing fiber/veg/added-sugar/sat-fat/sodium, which are only *optionally* present on `AITotals`. Rule: **Quality is `available` only when at least 3 of its 5 inputs are present for the day** (typically structured/library-logged meals, not freeform restaurant guesses). When available:
```
Quality = 60-anchored: +≤15 fiber/veg, −≤15 added sugar, −≤10 sat fat, −≤10 sodium density
```
When **fewer than 3 inputs** are present, Quality is **omitted** (not zero), weights renormalize over the remaining five, and the day is marked `partial`. This makes the 0.15 weight *real on structured-logging days* and honestly absent otherwise — no silent zero, no illusory weight. (Q6 still asks the owner whether to keep Quality at all; this defines its behavior if kept.)

**Weekly projection & sodium caveat:**
```
netKcal_week = Σ_days(intake − TDEE);  projectedKg = netKcal_week / 7700
Flag "aggressive" if |projectedKg|/weekWeight > 1% or any day's deficit > 500 kcal
Weight shown as 7-day rolling mean (never raw). Sodium caveat when today/yesterday > sodiumLimitMg:
  a 0.5–1.5 kg overnight jump ≈ water (~0.31 L retained per excess g sodium), not fat.
```

**Views/services:** `EatingScorer.swift`, `AppStore.bmr()/tdee()/computeEatingScore()/weeklyEnergyBalance()/smoothedWeightTrend()/sodiumFlag()`, new `eating` module ring + sub-score chips + `partial` pill, `TrendsView.weeklyEatingCard`. Settings gains age/height/sex/goal/sodium inputs (or optionally read HealthKit characteristics read-only). `SharedSnapshot` gains `eatingScore`/`projectedWeeklyKg`. AI: optional `estimatePrompt` enrichment; the scorer never calls the AI.

### 4.3 Prayer-on-time (timed /10) + custom rings

**Data model:** `PrayerLog` refactored from 5 bools to `records: [String: PrayerRecord]` while **keeping bool get/set computed properties** so every call site (`togglePrayer` line 1382, `mark("prayer")` line 786, `isOn`, `count`) compiles unchanged. Legacy migration: a `true` bool → `PrayerRecord(markedEpoch: 0, band: .unknown)` (scores as valid-but-unknown = 5, never crashes). `PrayerBand` enum (`promptOnTime 10 / onTime 8 / lateValid 5 / qadha 2 / unknown 5 / notLogged`). `Entry` gains `focusMinutes` + `focusSessions`. `AppSettings` gains `prayerPenalties` (user-disableable) + `focusGoalMinutes`.

**Multi-prayer auto-closing goal.** The Prayer ring/goal spans **all five daily prayers** and **auto-closes**: as each prayer is marked, the ring fills by that prayer's band points; the goal is considered complete when all five have a non-`notLogged` band. On-time and qadha timing are surfaced per-prayer (band chips) and rolled into the day ring (scoring below).

**`PrayerClassifier.swift`** (pure enum) derives boundaries from the existing `PrayerTimes` port and classifies a marked timestamp per research. **Islamic midnight** (not 00:00 local) is used throughout: `midnight = sunset + (nextFajr − sunset)/2`.

| Prayer | On-time band | Late-but-valid (makruh) | Qadha threshold |
|---|---|---|---|
| **Fajr** | fajr → sunrise | — | after sunrise (+90s grace) |
| **Dhuhr** | dhuhr → asr onset | — | after asr onset (+90s grace) |
| **Asr** | asr → (sunset − 30min) | (sunset−30) → sunset (makruh) | after sunset (+90s grace) |
| **Maghrib** | sunset → +20min (prompt window) | +20min → **Isha (shafaq)** — **still fully valid** | after Isha onset (+90s grace) |
| **Isha** | isha → **Islamic midnight** (preferred) | Islamic midnight → next Fajr (permitted) | after next Fajr (+90s grace) |

**Corrections applied:**
- **Maghrib** is **valid until Isha onset** — the `+20min` boundary is only a **prompt bonus** cutoff, never a downgrade to qadha. Anything before Isha is at worst `lateValid`, never `qadha`.
- **Isha** "preferred" ends at **Islamic midnight** (explicitly the computed midnight, not clock midnight); "permitted" extends to true Fajr.
- **Consistent +90s grace on the qadha boundary for all five prayers** (previously only Fajr/Asr had it).
- **`asrFactor`** (2 = Hanafi, else 1) sets Asr onset, which is *also* the Dhuhr end boundary — so a Hanafi user's Dhuhr on-time window **intentionally** extends later. This is surfaced in the classifier UI ("Dhuhr window per your madhab setting") so the shift is visible, not silent. Uses the **same madhab toggle** that drives the times port, so scoring and displayed times never diverge.
- **High-latitude / astronomically-undefined times:** if `PrayerTimes` returns `nil` for a given prayer (Isha/Fajr may not occur at extreme latitudes) **or** coordinates are missing, that prayer classifies as `.unknown` (scores 5, valid-but-untimed) rather than crashing or mis-scoring. This is distinct from `notLogged`.

**Prompt bonus:** within the on-time band, the first `max(15min, 20% of window)` → `promptOnTime` (10). If `prayerPenalties == false`, any marked prayer scores 8.

**Unmarked-prayer scoring (explicit, fail-soft).** A prayer whose band is `notLogged` scores based on the **current time relative to its window**, so the ring is neither trivially 100% nor unfairly 0%:
- If the prayer's **valid window has not yet ended** at scoring time → **excluded from the average** (it's simply not due/late yet). The day ring shows out of however many prayers are *due so far*.
- If the prayer's **entire valid window has passed** and it was never marked → scored as **`qadha` (2)** (a genuinely missed prayer), consistent with "missed" — **not** 0 (which would over-penalize) and **not** omitted (which would let misses vanish).

```
Day ring = 10 · (Σ points over prayers that are DUE-so-far) / (10 · count of DUE-so-far prayers)
   where a "due-so-far" prayer is any prayer whose window has ended OR that has been marked.
   Unmarked-and-window-passed → 2 (qadha). Unmarked-and-window-open → not yet counted.
```
This satisfies fail-soft (nothing shows a misleading 0 mid-day) while still recording end-of-day misses.

Theological guardrails: never label "sinful," frame qadha neutrally as "made up / outside window," penalties are opt-out.

**Other custom-ring metrics** are thin fills over `RingContext`: `hydration = waterMl/target`, `study = studyHours/target`, `work = focusMinutes/focusGoalMinutes`, `protein = proteinG/proteinTarget`. **Availability note:** the `work` metric reads `focusMinutes`, which is only produced once **M9 (Focus mode)** ships. To avoid a ring that silently reads 0, the `.workHours` custom metric is **not offered in the ring-editor picker until M9 is present** (feature-flagged on `focusMinutes` availability); a `work` ring added before M9 renders `available=false`/grey rather than a misleading 0.

**ADHD focus screen** (its own manager, distinct from `StudyTimer`): `FocusManager` drives a full-screen `FocusScreenView` — hero **depleting ring** via `ProgressView(timerInterval: start...end, countsDown: true)` (ticks entirely on-device, no background exec), single **Now/Next** task view (WIP=1, cuts task-switching cost), **ADHD-friendly default 45–50min** presets (not classic 25/5), gentle **escalating non-shaming** nudge chain on pause. Extended Live Activity (Lock Screen ring + Pause/Stop/Next App-Intents); handle the `timerInterval` 00:00 freeze with `Activity.update()` to a "Session complete" state. Completed minutes → `Entry.focusMinutes`.

---

## 5. AI coach revamp — multi-chat + tool calling

**What changes:** The single `coach_chat_v1` transcript and the ~600-token `coachContext()` dump are replaced by **multi-conversation threads** and **on-demand tool calls**. The system prompt shrinks to ~5 lines ("you are Coach, call tools to read the user's live data, never invent numbers"). This fixes the frozen-snapshot and "only last 5 logged days" gaps. Both **multi-chat** and **tool-calling** are delivered.

**Data model:** `CoachThread` (tolerant Codable: `id/title/created/updated/messages/providerId/modelId`) persisted under new `coach_threads_v1`, **migrating the old single transcript exactly once** (wrap into one thread, delete the old key). `ChatMessage` gains `toolCallsJSON?`/`toolResultsJSON?` and an internal `"tool"` role (never rendered). `AppStore` keeps `chatMessages` as a passthrough of the active thread so `CoachChatView` needs minimal change.

**Services/views:** §2.3 (`CoachProvider` adapters, `AgentRunner`, capability gating, ordered/serial execution, `maxIterations` terminal behavior), `CoachToolRegistry` (§ tools below), `CoachChatListView` (new/rename/delete, swipe, auto-title from first message), `AIEstimator.coachTurn()`/`supportsTools()`. **`AIEstimator.complete()`/`estimate()`/`parse*()`/vision stay untouched** — only the chat path gains the tool loop.

**Tool set** (each → compact JSON over existing AppStore methods):
- **Read-only:** `getDay`, `getRecentDays`, `getWeekStats`, `getReadiness`, `getFoodLog`, `getPrayers`, `getHealthIndex`, `getTargets`.
- **Write (all confirm-before-commit):** `logFood`, `editEntry`, `setEntryQty`, `removeEntry`, `setMealText` (edit the “what you ate” section), `setMealTime`, `togglePrayer`.

**Write-tool safety (data-integrity — resolves Q4's open concern).** Because there's no backend and no chat-level undo, write tools are **not blind mutations**:
1. **Every** write tool executes as a **staged proposal**: it returns a `pendingWrite` descriptor that renders an **inline confirm/cancel card** in the chat (showing the exact meal text / food / quantity or prayer change); the mutation **commits only on the user's tap** — nothing is saved before confirmation. The model sees “awaiting user confirmation” as the tool result.
2. Every confirmed write is **journaled** (`coachWriteLog`) so the last N coach-originated mutations are **one-tap undoable** from a "Coach changes" sheet.
3. Write tools ship **enabled by default**, but the confirm-before-commit gate above means a hallucinated `logFood` can never silently mutate the record — it only ever surfaces a card the user can dismiss. A **settings toggle** still lets a user switch the coach to **fully read-only** if preferred.

Tool output is confined to `tool_result`/`role:tool`/`functionResponse` blocks (never spliced into system/user text) to limit prompt-injection surface.

**Fallback (all 8 providers, never empty):** `coachContext()` is **retained as the lean preamble** for Apple Intelligence and non-tool/failed-probe Ollama models — zero regression on any provider. Loop bounded at `maxIterations=6` with the forced-final-completion terminal behavior (§2.3) so the coach **never returns an empty bubble**. Per-thread history trimmed to ~60 msgs (drop old tool turns first) to respect the ~1MB UserDefaults ceiling; no photos in chat. **Coach threads are included in `BackupBundle`** (see §10) so chat history survives restore.

---

## 6. Weather revamp — compact tile + AI tips rotator

**What changes:** The full-width `weatherModule` (verified `moduleView` case `"weather"` → `weatherModule`, `TodayView:175`) becomes a `weatherTipsRow`: a **¼-width `WeatherMiniTile`** (icon + temp + one-word verdict, reusing `WeatherManager`) beside a **¾-width `TipsRotator`** — a carousel of 3–6 context-aware `DayTip`s.

**Data model:** `DayTip` (tolerant: `text ≤22 words`, `category`, `icon`) + `DayTipCache {slot, tips}`. `SharedSnapshot` gains one small `topTip: String`.

**Services/views:** `TipsManager` (`@MainActor ObservableObject`, injected where `WeatherManager` is created), `AIEstimator.suggestTips()` (batched, one JSON call, reuses `complete(jsonOnly:true)` + `sliceJSON`), `Content.fallbackTips()` (deterministic local generator so the panel is **never empty** — fail-open). Layout uses `1:3 layoutPriority` on two `maxWidth:.infinity` children for the ¼:¾ split.

**Budget gate (load-bearing):** `slot = "\(date)/\(timeSlot)"` (morning/midday/afternoon/evening/latenight). Two-level cache — in-memory `lastSlot` + persisted `DayTipCache.slot` — means **≤1 AI call per (date, slot)**, ≈5/day worst case, 0 on revisits. Auto-advance every 8s, paused while loading; manual refresh forces regeneration.

**AI (uniform JSON handling with deterministic fallback content):** `suggestTips`/`parseTips` request JSON, but **JSON mode is not guaranteed** on Apple Intelligence or small Ollama models. The parser therefore: (a) attempts strict JSON via `sliceJSON`; (b) on prose-instead-of-JSON, attempts a lenient line/bullet extraction; (c) on any remaining failure, returns **`Content.fallbackTips()` deterministic tips** — so the panel always renders. The **same three-step "JSON → lenient → deterministic-fallback" contract applies to `parseTips`, `parseEntries`, and `estimate`** (each has its own deterministic fallback: `fallbackTips` for tips; "keep the user's raw text as a single editable freeform row" for `parseEntries`/`estimate`), so no provider — Apple or otherwise — can produce an unusable result.

---

## 7. Sleep & readiness widget revamp + recommendations (Whoop-like sleep widget)

**What changes:** The single-ring `sleepModule` becomes an expandable **two-ring header** (Sleep quality + Readiness), stage timeline with latency/efficiency, a **14-day multi-night graph** (Readiness/Sleep-hrs/HRV toggles), and a **"tonight's plan" block with dinner timing**. Because factors now persist per-day, tapping a past bar **replays that day's factors** (closes a real gap).

**Data model:** `ReadinessBreakdown` + `SleepPlan` + `ReadinessFactorDTO` (Codable, no UUID — bridges to the Identifiable `ReadinessFactor`) cached on `Entry` (`readinessBreakdown`, `sleepPlan`, `readinessFactorsCache`; the Readiness number itself stays in `Entry.readiness`). `SleepBreakdown` gains `latencyMin` + computed `midSleepEpoch`. `AppSettings` gains `sleepTargetHours`, `birthYear` (maxHR), `dinnerGapHours`. `SharedSnapshot` gains `sleepNeedHours`, `recommendedBedEpoch` (readiness already present).

**`SleepPlanner.swift`** (pure enum) — **consumes the single strain `S` (§2.2.1); it does not define its own strain formula:**
```
needHours = baseline + strainAdd + min(debtCarry, 2.0h)
  strainAdd(h) = 1.7 / (1 + e^((17 − S)/3.5)),  S = ScoreEngine.strain(...) (§2.2.1, 0–21, kcal-derived)
recommendedWakeEpoch  = median recent wakeEpochs (or last)
recommendedBedEpoch   = wake − needHours·3600 − 20min buffer
dinnerCutoffEpoch     = bed − dinnerGapHours·3600   (default 3h; 3.5–4h reflux-prone)
```
There is now **one** strain definition shared by §4.1 Sleep-Need and §7 `SleepPlanner`, so both produce the **same** SleepNeed for a given night (resolves the prior double-definition). Dinner-to-bed <3h research: ~40% more nocturnal awakenings, higher reflux. Readiness banding: HRV z-dominant (`0.55·HRVsub + 0.25·RHRsub + 0.20·SleepSub`), **greys to "calibrating"** when HRV baseline is absent or <7 nights.

**Views/services:** `SleepReadinessCard.swift` (two rings, `StageTimelineBar`, `MultiNightGraph` guarded behind `if #available` for Swift Charts with a primitive-bar fallback, `TonightPlanRow` incl. dinner cutoff, factors list), `HealthManager.fetchHRVOvernightMedian()`/`sleepBaselineHours()`, `AppStore.sleepHistory(days:)`. Meals section shows an inline dinner-gap advisory deep-linking to `MealTimeSheet`. `coachContext()` + estimate prompt gain the dinner-gap fact (context only, no new tool).

---

## 8. Food / quick-log revamp (local DB + structured/editable entries + search + export + projection)

**What changes:** Flat day-wide `logged: [LoggedItem]` + free-text `Meals` → **per-meal structured, editable `LoggedEntry`** (carries `mealKey`, `qty: Double` for fractional servings, live-recomputing totals), backed by the four-tier lookup service (§2.4). Quick-log de-clutters to **one context-filtered chip strip** (driven by existing `mealNudge` time-of-day logic), with inline per-meal add. Search, export, and the weekly weight projection (§4.2) are all delivered here.

**Data model:** `LoggedEntry` (per-meal, tolerant, **editable** — qty/name/macros mutable inline), `Entry.entries2: [LoggedEntry]` alongside legacy `logged` (**forward-migrate** each `LoggedItem`→`entries2` with `mealKey="snacks"`; write **both** for one release for rollback). `FoodSource` enum (`user|usda|curated|computed|openfoodfacts|llm`). `CatalogItem` **extended** (rather than a parallel `FoodItem`) with `mealTags/favorite/lastUsedEpoch/useCount/excludeFromQuickAdd` for context filtering + recency sort. `Entry.eating` cached. Bundled DB stays **out of `AppData`** (read-only SQLite) so the JSON blob doesn't balloon.

**Services/views:** `FoodDBManager` (SQLite read + FTS5 **search** + `byBarcode`), `FoodLookupService` (the four-tier chain + `OFFRateLimiter`, §2.4), `AIEstimator.parseEntries()` (NL → editable structured rows, Kerala/South-Indian aware, told to reuse verified library values verbatim; deterministic fallback keeps raw text as one editable row), `EatingScorer` (§4.2), `FoodDatabaseView` (searchable, source badges, favorite/exclude, edit → writes to `data.catalog`), `FoodExporter` (per-meal + day-wise plain-text **export**; **excludes `.openfoodfacts` rows by default** per §2.4 licensing). `AppStore.logEntry/setEntryQty/editEntry/removeEntry/suggestedFoods(for:)`. `dayNutrients()` sums `entries2` (**single source of truth per day** — prefer `entries2`; treat `draft.ai?.total` only as a whole-day fallback when `entries2` is empty, never summed together, to avoid double-counting).

**AI fix:** `estimate()` now emits **editable `entries2` rows the user approves** instead of silently overwriting `draft.calories/proteinG` (closes a long-standing gap). `parseEntries` is the **last** lookup tier — verified foods skip the LLM entirely. **Search-as-you-type is served entirely from local tiers 1–2 and never calls OFF** (so there is no OFF search-rate concern to "respect"; only barcode scans reach OFF, behind `OFFRateLimiter`).

---

## 9. Phased rollout

Grouped into dependency-ordered, independently shippable milestones. Shared foundations land first because everything else consumes them.

| # | Milestone | Ships (independently valuable) | Depends on |
|---|---|---|---|
| **M1** | **Score engines + baselines + first-launch import** | `ScoreEngine` (Sleep/Readiness/Active, single strain `S`) + `EatingScorer` + `ScoreBaselines` + `HealthManager.backfill()` (30-day import); overnight-median HRV, resp, wrist-temp, active-kcal, mean+sd baselines; `ReadinessScorer` shim; Readiness recomputed in place into `Entry.readiness` (no new score field / no migration); `activeScore: Int?` added. | §2.2 |
| **M2** | **Prayer capture + classifier** | `PrayerLog`→records refactor (bool-compatible), `PrayerClassifier` (corrected bands, +90s grace all five, Islamic midnight, hi-lat `nil`→`.unknown`), timestamp capture on mark, unmarked-prayer scoring, multi-prayer auto-closing goal. UI-visible bands. | none |
| **M3** | **Ring registry + Today ring row + custom rings + Explain-this-ring** | `RingEngine`/`RingDef`/`RingGauge`, `RingRowView`, `RingDetailView` (with "Explain this ring"), `RingEditorView` (built-in + **custom** rings incl. Eating + Prayer), `"rings"` core module. `.workHours` metric feature-flagged off until M9. | M1, M2, §2.1 |
| **M4** | **Whoop-like sleep & readiness widget** | `SleepPlanner` (consumes shared `S`), `SleepReadinessCard` (two rings, stage timeline, **14-day graph**, tonight's plan, **dinner cutoff**), persisted factor replay, `CheckInSheet`. | M1 |
| **M5** | **Eating score + weekly projection** | `eating` module ring + sub-score chips (availability-gated Quality), `weeklyEatingCard` (7700-rule **projection**, aggressive-rate warning, sodium/water caveat, smoothed weight), resting-day-floor TDEE. Settings profile inputs. | M1 |
| **M6** | **Food/quick-log revamp** | `entries2` migration, context-filtered chips + inline per-meal **editable** logging, `FoodDBManager` + bundled USDA (Foundation+SR) SQLite + four-tier lookup chain + `OFFRateLimiter`, `parseEntries`, `FoodDatabaseView` (**search**), nutrition graphs, `FoodExporter` (**export**, OFF-excluded); **Indian/South-Indian coverage per §2.4.1** — hand-authored `curated` Kerala/S-Indian starter dishes + recipe-`computed` values from bundled USDA ingredients + OFF-India (`off`) live, **no IFCT-derived data bundled**. | M5, §2.4 |
| **M7** | **Coach: multi-thread + tools** | `CoachThread` + list UI + migration; neutral tool core + 3 adapters + ordered/serial `AgentRunner` + `maxIterations` terminal behavior + runtime tool-probe; **read tools first, then staged/confirmed/journaled write tools enabled by default (confirm-before-commit), incl. editing the “what you ate” section**; shrunk system prompt with text + deterministic fallback. | §2.3 **and M1, M4, M5, M6** (read tools return data only once those surfaces exist) |
| **M8** | **Weather tips rotator** | `weatherTipsRow` (**¼ tile + ¾ carousel**), `TipsManager`, `suggestTips`, three-step JSON→lenient→deterministic fallback. | none (independent; low risk; slot any time after M1) |
| **M9** | **Focus mode + work-hours ring + snapshot/widgets** | `FocusManager` + `FocusScreenView` + extended Live Activity; enables the **work-hours** custom ring metric (unflagged here); fill `SharedSnapshot.rings`/`readiness`/`eating`/`topTip`; ring-strip widget. | M3, M2 |

**Rationale & ordering fixes:** M1–M2 are pure engines with no UI risk and unblock the rings (M3) and widgets (M4). M5→M6 order the eating score before the food-logging surface that feeds it. **M7 now explicitly depends on M1/M4/M5/M6** — its read tools return empty until those data surfaces exist, so it cannot be scheduled earlier. The **`.workHours` custom ring is feature-flagged until M9** so no user can create a ring that reads 0 for lack of `focusMinutes`. M8 is orthogonal and can ship early as a quick win. M9 collects the Live-Activity + widget + snapshot work that depends on the rest.

---

## 10. Risks & decisions

- **HealthKit HRV is SDNN-only, sparse.** A clean nightly HRV does not exist — must take the **median of overnight-window samples**, and Readiness must fail-soft to a sleep-only "calibrating" score (never a misleading low ring) until `sampleNights ≥ 7`. `HealthManager.backfill()` imports 30 days on first launch so existing-history users calibrate immediately.
- **Free-signing / no-Watch devices** lack per-minute HR/HRV/respiratory rate, but **Active and Sleep-Need depend only on `activeEnergyBurned`-derived strain `S`**, which iPhone provides — so Active is a primary ring and never shows 0-for-lack-of-Watch. A Watch, when present, only sharpens Active. Sub-scores that truly lack inputs renormalize; if even active-kcal is absent, the ring greys (`available=false`), never 0.
- **Single strain source of truth.** `ScoreEngine.strain()` (§2.2.1) is the only strain definition; §4.1 Sleep-Need and §7 `SleepPlanner` both consume it, so SleepNeed is identical across the two surfaces.
- **`PrayerLog` refactor is the highest-risk change** (many call sites read the 5 bools). Mitigated by bool-compatible get/set computed properties and unit-testing the legacy→records tolerant decode. Classifying a *past* day needs `PrayerTimes.calculate` for that date + next-day Fajr (PrayerManager caches only `today`); an astronomically-`nil` prayer or missing coordinates → `.unknown` (5), never a crash.
- **No Readiness migration needed.** The Readiness score keeps the existing `Entry.readiness: Int` field and is recomputed in place — no new nullable field, no sentinel logic; a computed `0` (red band / illness) is a normal stored value. (The one new cached score field, `activeScore: Int?`, uses `nil`=not-computed so a real `0` survives.)
- **Backward-compat:** the Readiness score stays in `Entry.readiness`, so **old widget binaries keep working with zero changes**; new widgets additionally read `activeScore`/`eatingScore`. The user-facing label remains **“Readiness”** (owner decision, 2026-07-02).
- **UserDefaults ~1MB ceiling — including the App-Group snapshot.** Two finite blobs: the main `suhail_health_v2` blob **and** the App-Group `UserDefaults` written by `publishSnapshot()`. **`SharedSnapshot` is size-budgeted:** rings capped at ≤4; `SnapshotRing.title`/`display` truncated to ≤24 chars; `topTip` ≤120 chars; only scalar fields (readiness, activeScore, eatingScore, projectedWeeklyKg, sleepNeedHours, recommendedBedEpoch) — no arrays beyond the 4 rings. Main-blob mitigations unchanged: bundled food DB stays a read-only SQLite (out of `AppData`), per-thread chat history trimmed, factor DTOs small, no photos/base64 in chat.
- **AI tool-calling does not work uniformly across providers** — handled explicitly: Apple Intelligence and failed-probe Ollama route to the **text path**; JSON parsing everywhere uses the **JSON→lenient→deterministic-fallback** contract; the coach loop's terminal behavior guarantees non-empty output; Gemini call-ids are order-deterministic.
- **Coach concurrency:** tool execution is **serial on `@MainActor`** (no `TaskGroup`-parallel access to `AppStore`), which is both correct and compiler-accepted; any future off-main tool must pass `Sendable` snapshots.
- **Write-tool data integrity:** coach writes (incl. editing the “what you ate” section) are **enabled by default but staged → user-confirmed → journaled → undoable** — values commit only after the user taps confirm, so an LLM cannot silently mutate the health record. A toggle can force fully read-only.
- **Licensing (attribution + share-alike):** bundle **USDA Foundation + SR Legacy only** (public-domain compilation); **do not bundle branded names/marks/images** (third-party IP) — branded items arrive only via runtime OFF/USDA-search. OFF rows are **partitioned by `source`**, **excluded from `BackupBundle`/export by default**, and any opt-in "full export" carries the ODbL attribution + share-alike notice — so no ODbL-derived DB is silently redistributed.
- **OFF rate limiting is enforced by a real component** (`OFFRateLimiter` token buckets); **only barcode scans call OFF**; search never does.
- **Eating "Quality" sub-score** is **availability-gated** (needs ≥3 of 5 inputs) — omitted (not zeroed) when structurally absent, weights renormalize, day marked `partial` (Q6 still asks whether to keep it at all).
- **TDEE realism:** `TDEE = max(BMR·1.10 + activeKcal, BMR·1.15)` — the +10% TEF/NEAT factor and `1.15·BMR` resting-day floor prevent rest days from reading as surplus and stop the deficit penalty from firing spuriously.
- **Double-counting:** food day-total uses **`entries2` as the single source** (`ai` only as whole-day fallback when `entries2` empty).
- **Live Activity:** the widget-extension target must declare the Focus `ActivityConfiguration` or `Activity.request()` silently fails; `timerInterval` freezes at 00:00 → explicit `Activity.update()` on completion.

---

## 11. Open questions for the owner

1. **Resolved (2026-07-02):** ship **all** ring sources; the user chooses **3 or 4 visible** rings (and which, + order) via `AppSettings.visibleRingCount` + the ring editor.
2. **Resolved (2026-07-02):** keep the name **“Readiness”** (the WHOOP-style algorithm computes `Entry.readiness`); no rename to a separate label, no new field.
3. **`age`/DOB source:** add `birthYear` to Settings/onboarding for `maxHR = 208 − 0.7·age` (fallback 190), or pull HealthKit characteristics read-only?
4. **Resolved (2026-07-02):** ship coach write tools **enabled**, incl. editing the “what you ate” section, with **confirm-before-commit** (a toggle can force read-only). **Still open:** coach entry point — open a **thread list** first (cleaner) vs the most-recent thread with a switcher menu (fewer taps)?
5. **Resolved (2026-07-02):** yes — accept ~4–10MB for bundled USDA (Foundation + SR Legacy). **Plus Indian / South-Indian coverage — see §2.4.1.** (Live USDA search stays optional / user-supplied key.)
6. **Eating quality sub-score** is a coarse HEI proxy, availability-gated to structured-logging days (§4.2) — keep it labeled as an estimate, or omit "Quality" entirely until structured meal logging matures?
7. **Adaptive vs fixed strain reference** for Active (`Sref`/`typicalActiveKcal` from rolling median matches WHOOP but is less predictable than a fixed user goal)?
8. **Self-report journal / check-in:** a daily nudge notification, or purely opt-in from the sleep module?
9. **Legacy `sleepModule` readiness ring:** keep it as its own module, or fully subsume it into the new ring row to avoid duplication?
10. **HealthKit `mindfulSession` mirror (write):** should completed focus sessions be **written** to HealthKit as `mindfulSession`? (Deferred by default — write access needs its own entitlement + usage string; not in v1 scope unless you want it.)

---

## Appendix — Research sources

- Islam Q&A (IslamQA) #9940 — What Are the Times of the Five Daily Prayers? — https://islamqa.info/en/answers/9940
- Sahih Muslim 612 — the Jibril/Gabriel two-day prayer-timing hadith ('the time is between these two') — https://sunnah.com/muslim:612
- Sahih al-Bukhari 579 — 'Whoever catches one rak'ah of Fajr before sunrise / Asr before sunset has caught the prayer' — https://sunnah.com/bukhari:579
- Wikipedia — Salah times (astronomical/solar-angle definitions) — https://en.wikipedia.org/wiki/Salah_times
- PrayTimes.org — Prayer Times Calculation reference — https://praytimes.org/docs/calculation
- SeekersGuidance (Hanafi fiqh) — Delaying Isha until shortly before Fajr — https://seekersguidance.org/answers/hanafi-fiqh/delaying-isha-until-shortly-before-fajr/
- SeekersGuidance / IslamQA — The Hanafi Asr time and the shadow-factor difference — https://seekersguidance.org/answers/hanafi-fiqh/the-hanafi-asr-time/
- Islam Q&A (IslamQA) #48998 — Forbidden/disliked times for prayer — https://islamqa.info/en/answers/48998
- Islam Q&A (IslamQA) #39818 & IslamWeb #275422 — ruling on delaying prayer to end of / past its time — https://islamqa.info/en/answers/39818
- WHOOP Recovery — official support (inputs: RHR, HRV, respiratory rate, sleep, skin temp, SpO2; Green/Yellow/Red bands; personal baseline) — https://support.whoop.com/s/article/WHOOP-Recovery?language=en_US
- WHOOP 101 — WHOOP for Developers (Recovery inputs & bands; Strain 0-21 with Light/Moderate/High/All-Out; Sleep stages Light/REM/SWS + Sleep Debt) — https://developer.whoop.com/docs/whoop-101/
- WHOOP API reference — exact field names & units (recovery_score, hrv_rmssd_milli, resting_heart_rate, spo2_percentage, skin_temp_celsius, strain, kilojoule, sleep_performance/consistency/efficiency_percentage, sleep_needed.baseline/need_from_sleep_debt/need_from_recent_strain/need_from_recent_nap, stage millis, respiratory_rate, user_calibrating) — https://developer.whoop.com/api
- WHOOP Recovery: How It Works, Key Metrics, and Tips (HRV weighted across the night, more weight to slow-wave sleep & later night; RHR & respiratory rate secondary; personal baseline) — https://www.whoop.com/us/en/thelocker/how-does-whoop-recovery-work-101/
- WHOOP Sleep Performance — Locker (Sufficiency vs Sleep Need, Consistency over ~4 days, Efficiency = asleep/in-bed x100, Sleep Stress; Sleep Need learned) — https://www.whoop.com/us/en/thelocker/how-well-whoop-measures-sleep/
- WHOOP Sleep Planner / How much sleep do you need (Sleep Need = Baseline + f(strain) + f(debt) - naps model) — https://www.whoop.com/us/en/thelocker/how-much-sleep-do-i-need/
- WHOOP Strain Explained — Locker (0-21 log scale ~ Borg RPE; cardiovascular load from HR zones via heart rate reserve; muscular load from accelerometer/gyroscope; recovery-aware) — https://www.whoop.com/us/en/thelocker/how-does-whoop-strain-work-101/
- WHOOP Strain zones & calculation breakdown (per-second HR sampling; 80-90% HR-max weighted far more than 50-60%; non-linear cardiovascular scaling; log progression) — https://whoopal.com/whoop-strain
- Apple HealthKit API: What Data You Can Access (HRV = SDNN only, captured during Breathe/Mindfulness not continuous sleep; sleep stages watchOS 9+/S3+; respiratory rate, wrist temp, SpO2, energy, steps, VO2max, workouts) — https://openwearables.io/blog/apple-healthkit-api-what-data-you-can-access-and-how
- How wearables measure HRV: SDNN vs RMSSD (HKQuantityTypeIdentifierHeartRateVariabilitySDNN is the only HRV type Apple exposes; Apple uses ~60s SDNN spot-checks vs WHOOP/Oura continuous RMSSD; AFib History enables denser overnight capture) — https://www.empirical.health/blog/how-wearables-measure-hrv/
- An Overview of Heart Rate Variability Metrics and Norms (Frontiers/Shaffer & Ginsberg) — SDNN/RMSSD definitions, right-skew, natural-log transform for normal distribution — https://pmc.ncbi.nlm.nih.gov/articles/PMC5624990/
- Readiness Score Explained (Livity) — universal inputs HRV/RHR/sleep/activity; WHOOP ~60% of Recovery from morning HRV vs baseline; Oura 28-day HRV balance + 2-week sleep balance; RHR +5-10 bpm drift signals incomplete recovery — https://livity-app.com/en/blog/readiness-score-explained
- Open Wearables — open health-score algorithms (Sleep Score example weighting Duration/Efficiency/Consistency; MIT-licensed, forkable) — https://openwearables.io/health-scores
- Validation of nocturnal RHR and HRV in consumer wearables (Physiological Reports, 2025) — https://pmc.ncbi.nlm.nih.gov/articles/PMC12367097/
- USDA FoodData Central — API Guide (key, endpoints, rate limits, CC0 license, citation) — https://fdc.nal.usda.gov/api-guide/
- USDA FoodData Central — Downloadable Datasets (formats, sizes, update cadence) — https://fdc.nal.usda.gov/download-datasets/
- Open Food Facts — Data, API and SDKs (exports, ODbL license, dump sizes) — https://world.openfoodfacts.org/data
- Open Food Facts — API documentation (rate limits, User-Agent, bulk guidance) — https://openfoodfacts.github.io/openfoodfacts-server/api/
- Open Food Facts product database — Parquet on Hugging Face — https://huggingface.co/datasets/openfoodfacts/product-database
- Open Food Facts — Wikipedia (4M+ products, coverage, history) — https://en.wikipedia.org/wiki/Open_Food_Facts
- FatSecret Platform — API Editions & Pricing (Basic free tier vs Premier) — https://platform.fatsecret.com/api-editions
- FatSecret Platform — OAuth 2.0 Documentation (proxy/IP whitelist requirement) — https://platform.fatsecret.com/docs/guides/authentication/oauth2
- Nutritionix — Nutrition API (no usable free tier, pricing, NL endpoint) — https://www.nutritionix.com/api
- Nutrola — Open Nutrition Datasets Compared (USDA vs OFF vs FatSecret coverage/quality) — https://nutrola.app/en/blog/open-nutrition-datasets-compared-usda-openfoodfacts-nutrola
- Caltopia — offline iOS calorie tracker bundling a USDA subset (real-world precedent) — https://caltopia.org/
- alyssaq/usda-sqlite — USDA files → SQLite import scripts — https://github.com/alyssaq/usda-sqlite
- littlebunch/fdc-api — REST API + utilities over USDA FDC CSV datasets — https://github.com/littlebunch/fdc-api
- Effectiveness of time-related interventions in children with ADHD aged 9–15 years: a randomized controlled study (Wennberg et al., PMC5852175) — https://pmc.ncbi.nlm.nih.gov/articles/PMC5852175/
- Effectiveness of a gamified educational application on attention and academic performance in children with ADHD: an 8-week randomized controlled trial (Frontiers in Education, 2025) — https://www.frontiersin.org/journals/education/articles/10.3389/feduc.2025.1668260/full
- You Are Not Alone: Designing Body Doubling for ADHD in Virtual Reality (arXiv 2509.12153, 2025) — https://arxiv.org/pdf/2509.12153
- Remembering the Future: How ADHD Affects Prospective Memory (and How to Work with It) — CHADD — https://chadd.org/attention-article/remembering-the-future-how-adhd-affects-prospective-memory-and-how-to-work-with-it/
- Helping Students Improve Their Working Memory — CHADD — https://chadd.org/adhd-weekly/helping-students-improve-their-working-memory/
- Time Blindness and ADHD / visual timers (Time Timer, progress ring) — https://pomodorotimer.vip/blog/time-blindness-adhd/
- ADHD Body Doubling: What It Is and How It Works — Psych Central — https://psychcentral.com/adhd/adhd-body-doubling
- How Body Doubling Helps With ADHD — Cleveland Clinic — https://health.clevelandclinic.org/body-doubling-for-adhd
- Task Switching in ADHD: Examples, Why It's Hard, What Helps — NeuroSpark Health — https://neurosparkhealth.com/executive-functioning/task-switching-and-adhd
- Gentle Accountability: The ADHD-Friendly Way to Follow Through — Work Brighter — https://workbrighter.co/gentle-accountability-guide/
- ActivityKit | Apple Developer Documentation — https://developer.apple.com/documentation/activitykit
- Displaying live data with Live Activities | Apple Developer Documentation — https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- NSSupportsLiveActivitiesFrequentUpdates | Apple Developer Documentation — https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates
- Animated Timer in SwiftUI Part 2: LiveActivity — Marwa Diab (Medium) — https://medium.com/@marwa.diab/animated-timer-in-swiftui-part-2-e1245d7ebe7f
- Defining your app's Focus filter | Apple Developer Documentation (SetFocusFilterIntent) — https://developer.apple.com/documentation/appintents/setfocusfilterintent
- Meet Focus filters — WWDC22 (Session 10121), Apple Developer — https://developer.apple.com/videos/play/wwdc2022/10121/
- Screen Time Technology Frameworks | Apple Developer Documentation — https://developer.apple.com/documentation/screentimeapidocumentation
- HKCategoryTypeIdentifier.mindfulSession | Apple Developer Documentation — https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/mindfulsession
- Workouts and activity rings | Apple Developer Documentation — https://developer.apple.com/documentation/healthkit/workouts-and-activity-rings
- HEI-2020 & HEI-Toddlers-2020 Dietary Components and Scoring Standards (Table 1) — National Cancer Institute — https://epi.grants.cancer.gov/hei/hei-2020-table1.html
- How the HEI Is Scored — USDA Food and Nutrition Service — https://www.fns.usda.gov/cnpp/how-hei-scored
- Healthy Eating Index-2020: Review and Update Process to Reflect the Dietary Guidelines for Americans 2020-2025 — J Acad Nutr Diet — https://www.jandonline.org/article/S2212-2672(23)00246-0/fulltext
- ISSN Position Stand: Protein and Exercise (Jäger et al., 2017) — J Int Soc Sports Nutr / PMC5477153 — https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/
- Using Dietary Reference Intakes for Nutrient Assessment of Individuals — DRI, NCBI Bookshelf — https://www.ncbi.nlm.nih.gov/books/NBK222891/
- Narrative review of nutrient-based indexes (NAR/MAR, Total Nutrient Index) — PMC8888777 — https://pmc.ncbi.nlm.nih.gov/articles/PMC8888777/
- Quantification of the effect of energy imbalance on bodyweight (Hall et al.) — PMC3880593 — https://pmc.ncbi.nlm.nih.gov/articles/PMC3880593/
- Why is the 3500 kcal per pound weight loss rule wrong? — Int J Obes / PMC3859816 — https://pmc.ncbi.nlm.nih.gov/articles/PMC3859816/
- Energy Content of Weight Loss: Kinetic Features During Voluntary Caloric Restriction — PMC3810417 — https://pmc.ncbi.nlm.nih.gov/articles/PMC3810417/
- Weight Loss Composition is One-Fourth Fat-Free Mass — PMC3970209 — https://pmc.ncbi.nlm.nih.gov/articles/PMC3970209/
- Manipulate Sodium for Safest Rapid Weight Loss — Human Kinetics (excerpt) — https://us.humankinetics.com/blogs/excerpt/manipulate-sodium-for-safest-rapid-weight-loss
- Water and Sodium Balance — Merck Manual Professional — https://www.merckmanuals.com/professional/endocrine-and-metabolic-disorders/fluid-metabolism/water-and-sodium-balance
- High dietary sodium chloride consumption may not induce body fluid retention in humans — Am J Physiol Renal — https://journals.physiology.org/doi/full/10.1152/ajprenal.2000.278.4.F585
- Does the Proximity of Meals to Bedtime Influence the Sleep of Young Adults? — PMC7215804 — https://pmc.ncbi.nlm.nih.gov/articles/PMC7215804/
- Association Between Dinner-to-Bed Time and Gastro-Esophageal Reflux Disease — PubMed 16393212 — https://pubmed.ncbi.nlm.nih.gov/16393212/
- Chronobiological perspectives: Association between meal timing and sleep quality — PLOS One / PMC11293727 — https://pmc.ncbi.nlm.nih.gov/articles/PMC11293727/
- Comparison of predictive equations for RMR (Mifflin-St Jeor validation) — summarized; and Mifflin-St Jeor formula references — https://reference.medscape.com/calculator/846/mifflin-st-jeor-equation
- NATA Position Statement: Safe Weight Loss and Maintenance Practices in Sport and Exercise — PMC3419563 — https://pmc.ncbi.nlm.nih.gov/articles/PMC3419563/
- Tool use with Claude — overview (Anthropic/Claude Platform Docs) — https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview
- Handle tool calls — parse tool_use, format tool_result, is_error (Claude Platform Docs) — https://platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls
- Function calling — OpenAI API guide — https://developers.openai.com/api/docs/guides/function-calling
- Function calling with the Gemini API (Google AI for Developers) — https://ai.google.dev/gemini-api/docs/function-calling
- generateContent REST reference (Gemini API) — https://ai.google.dev/api/generate-content
- Tool support — Ollama Blog — https://ollama.com/blog/tool-support
- OpenAI compatibility — Ollama Docs — https://docs.ollama.com/api/openai-compatibility
- Tool Calls — DeepSeek API Docs — https://api-docs.deepseek.com/guides/tool_calls
- Tool & Function Calling — OpenRouter Documentation — https://openrouter.ai/docs/guides/features/tool-calling
- Expanding generation with tool calling — Apple Developer Documentation (FoundationModels) — https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling
- Exploring the Foundation Models framework — createwithswift.com — https://www.createwithswift.com/exploring-the-foundation-models-framework/
- Mastering SwiftData: Building Persistent Memory for Your Next AI Chatbot — DEV Community — https://dev.to/programmingcentral/mastering-swiftdata-building-persistent-memory-for-your-next-ai-chatbot-4ka9
- Defining data relationships with enumerations and model classes — Apple Developer Documentation (SwiftData) — https://developer.apple.com/documentation/swiftdata/defining-data-relationships-with-enumerations-and-model-classes

### Indian / South-Indian food-data licensing (added 2026-07-02)

- IFCT 2017 official free e-book PDF — ICMR-National Institute of Nutrition (copyright page is in the front matter) — https://www.nin.res.in/ebooks/IFCT2017.pdf
- ICMR-NIN Food Composition research division (publisher of IFCT / NVIF; contact point for permissions) — https://www.nin.res.in/researchdivision/foodcomposition.html
- Development of an Indian Food Composition Database (INDB) — PMC / Current Developments in Nutrition 2024 (1,095 foods + 1,014 recipes; CC BY article; IFCT 2017-derived) — https://pmc.ncbi.nlm.nih.gov/articles/PMC11277795/
- INDB dataset GitHub repo (lindsayjaacks/Indian-Nutrient-Databank-INDB-) — Excel data + Stata .do; note: no LICENSE file present — https://github.com/lindsayjaacks/Indian-Nutrient-Databank-INDB-
- Anuvaad Solutions — Indian Nutrient Databank (INDB) portal (open-access recipe database, 1,014 recipes) — https://www.anuvaad.org.in/indian-nutrient-databank/
- nodef/ifct2017 — machine-readable IFCT 2017 reproduction (README: data from the NIN book; license moved MIT → AGPL-3.0 on 2025-04-18) — https://github.com/ifct2017/ifct2017
- ifct2017 on Zenodo (record 7088653) — 'Other (Open)'; 'Food composition values were measured by National Institute of Nutrition, Hyderabad' — https://zenodo.org/records/7088653
- ifct2017.github.io — third-party IFCT 2017 web query interface / text API — https://ifct2017.github.io/
- IFCT 2017 dataset mirror on Kaggle (gijoe707/ifct2017) — license shown as 'Other (Open)' — https://www.kaggle.com/datasets/gijoe707/ifct2017
- Nutritive Value of Indian Foods (Gopalan et al.), ICMR-NIN — full scans on Internet Archive (reading copy; NIN copyright, not public domain) — https://archive.org/details/nutritive-value-of-indian-foods-e-c.-gopalan
- PIB Govt. of India press release — launch of IFCT 2017 by NIN/ICMR (context/authority) — https://www.pib.gov.in/newsite/PrintRelease.aspx?relid=157486
- FSSAI Labelling & Display regulation compendium (regulatory reference; nutrient values trace to IFCT, not an independent bundleable dataset) — https://fssai.gov.in/upload/uploadfiles/files/Comp_Labelling%20Display_Version%20VIII_09_09_2025.pdf
- ifct2017/ifct2017 LICENSE file (confirms AGPL-3.0 text) — https://github.com/ifct2017/ifct2017/blob/master/LICENSE
- @ifct2017/compositions on npm (data package) — https://www.npmjs.com/package/@ifct2017/compositions
- Kaggle batthulavinay/indian-food-nutrition — 'Indian Food Nutritional Values Dataset (2025)' (CC BY-SA 4.0, INDB-derived) — https://www.kaggle.com/datasets/batthulavinay/indian-food-nutrition
- Kaggle kashyap077 — 'Indian Recipes: Nutrition & Cooking method (2026)' (CC BY-NC-SA 4.0, 725 dishes, regional labels) — https://www.kaggle.com/datasets/kashyap077/indian-recipes-ingredients-nutrition-and-cooking
- Kaggle syedkhalid076/indian-food-nutrition (license Unknown; per-100g, branded-food schema) — https://www.kaggle.com/datasets/syedkhalid076/indian-food-nutrition
- Hugging Face adarshzolekar/foods-nutrition-dataset (CC BY 4.0; 1,028 items incl. Indian dishes) — https://huggingface.co/datasets/adarshzolekar/foods-nutrition-dataset
- Hugging Face bharat-raghunathan/indian-foods-dataset (CC0; images only, no nutrition) — https://huggingface.co/datasets/bharat-raghunathan/indian-foods-dataset
- News-Medical: 'New open-access resource reveals nutrient content of Indian foods' (INDB context) — https://www.news-medical.net/news/20240616/New-open-access-resource-reveals-nutrient-content-of-Indian-foods.aspx
- Open Food Facts — India database reaches 10K products (product count, packaged-only, data-completeness caveats) — https://blog.openfoodfacts.org/en/news/open-food-facts-india-database-reaches-10k-product-milestone
- Open Food Facts — Terms of use, contribution and re-use (ODbL 1.0 + DbCL 1.0 data; CC BY-SA 3.0 images; attribution + commercial-use permission) — https://world.openfoodfacts.org/terms-of-use
- Open Food Facts Knowledge Base — Are there conditions to use the API? (attribution + share-alike apply to the database) — https://support.openfoodfacts.org/help/en-gb/12-api-data-reuse/94-are-there-conditions-to-use-the-api
- Open Data Commons — ODbL v1.0 full text (Produced Work vs Derivative Database; closed-source Produced Works allowed, DB share-alike on request) — https://opendatacommons.org/licenses/odbl/1-0/
- INDB paper — Current Developments in Nutrition full text (data sources, recipe manuals, methodology) — https://cdn.nutrition.org/article/S2475-2991(24)01724-4/fulltext
- National Institute of Nutrition (ICMR-NIN), Hyderabad — original IFCT 2017 publisher/copyright holder — https://www.nin.res.in/
