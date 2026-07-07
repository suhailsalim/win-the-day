# PLAN: Biology section — structured lab/InBody data, per-analyte history graphs, correlations

## Goal
Lab and InBody imports already parse into structured data (`AppData.labs: [LabRecord]` with flat
`LabItem {name, value, unit}` per report — [Models.swift:704–717](WinTheDay/Core/Models.swift); InBody →
`AppData.bodyComps: [BodyComp]`), but the data is only browsable report-by-report. Build a
**Biology** section that pivots this from *reports* to *measurements*:

1. A **canonical analyte catalog** (base set of known labels with aliases, units, categories,
   reference ranges); parsed items normalize onto it, and **unknown analytes keep the report's
   name** as a dynamic label — nothing is dropped.
2. A **Biology browser** in the Health tab: every measurement the user has ever had, grouped by
   category, with latest value, in/out-of-range dot, and trend arrow.
3. Tap an item → **detail view**: all entries over time as a graph with a reference band, plus
   every reading listed with its source report.
4. **Correlations**: deterministic on-device Pearson correlations between analytes and against
   app metrics (weight, readiness, sleep), shown honestly with sample-size gates.

## Files to touch
- `WinTheDay/Engines/BiologyCatalog.swift` — NEW: canonical analyte definitions + normalization + series
  building + correlation math (pure, Foundation-only, unit-testable — the ScoreEngine pattern).
- `WinTheDay/Health/BiologyView.swift` — NEW: browser + analyte detail views.
- `WinTheDay/Core/Models.swift` — `LabItem` gains `canonicalId: String? = nil` and
  `LabRecord` gains `collectedDate: String = ""` (tolerant decode lines; see
  `.claude/skills/add-persisted-field`).
- `WinTheDay/Health/ImportReportView.swift` + `AppStore` save path — normalize on import + dedup guard.
- `WinTheDay/AI/AIEstimator.swift` — `parseLabs` prompt additionally extracts the **collection date**
  printed on the report.
- `WinTheDay/Health/HealthView.swift` — "Biology" entry card (latest counts + navigation).
- `WinTheDay/AI/CoachTools.swift` — extend `getHealthIndex` with per-analyte latest + trend.
- `EngineTests/` — normalization, series, and correlation tests.

## Step 1 — Canonical catalog (`BiologyCatalog.swift`)

```swift
struct AnalyteDef {
    let id: String            // stable identifier, e.g. "hba1c" — never localized, never renamed
    let name: String          // display, "HbA1c"
    let aliases: [String]     // lowercase match keys: ["hba1c", "glycated hemoglobin", "a1c"]
    let category: String      // "metabolic" | "lipids" | "cbc" | "thyroid" | "vitamins"
                              // | "liver" | "kidney" | "hormones" | "inflammation" | "body"
    let unit: String          // canonical display unit, e.g. "%"
    let altUnits: [String: Double]  // reported-unit → multiplier to canonical (e.g. mmol/L→mg/dL)
    let range: ClosedRange<Double>? // general adult reference range in canonical unit (nil = none)
    let direction: Direction  // .inRange | .lowerBetter | .higherBetter (drives trend arrows)
}
```

Base set (~60 analytes, hand-authored as a static array — this is data entry, be exhaustive):
- **Metabolic:** fasting glucose, HbA1c, fasting insulin, uric acid.
- **Lipids:** total cholesterol, LDL, HDL, triglycerides, VLDL, non-HDL, Lp(a), ApoB.
- **CBC:** hemoglobin, hematocrit, RBC, WBC, platelets, MCV, MCH, MCHC, RDW, neutrophils,
  lymphocytes, eosinophils, monocytes, basophils, ESR.
- **Thyroid:** TSH, free T4, free T3, total T4, total T3, anti-TPO.
- **Vitamins/minerals:** vitamin D (25-OH), B12, folate, ferritin, iron, TIBC, transferrin
  saturation, calcium, magnesium, phosphorus, sodium, potassium, chloride, zinc.
- **Liver:** ALT, AST, ALP, GGT, total bilirubin, direct bilirubin, albumin, total protein.
- **Kidney:** creatinine, eGFR, urea/BUN, cystatin C.
- **Hormones:** testosterone (total/free), estradiol, cortisol, DHEA-S, prolactin, SHBG.
- **Inflammation:** hs-CRP, homocysteine.
- **Body (from `BodyComp` + entries):** weight, body fat %, lean mass, skeletal muscle, BMI,
  visceral fat — so InBody series appear in the same browser with zero extra storage.

Reference ranges: general adult values, sex-split only where it matters (ferritin, hemoglobin,
testosterone — add `rangeFemale: ClosedRange<Double>?` and pick by `Targets.sexMale`). Every range
is labeled "general reference range — your lab's range may differ" in the UI.

Normalization: `BiologyCatalog.match(name: String) -> AnalyteDef?` — lowercase, strip
punctuation/parentheticals, longest-alias-first `contains` matching (so "total cholesterol"
matches before "cholesterol"; "free t3" before "t3"). Unknown → `nil`, and the item's own name
becomes its dynamic series key.

## Step 2 — Normalize on import (and backfill)
1. In the lab-save path (follow `ImportReportView` → wherever `store.data.labs.append` happens):
   set `item.canonicalId = BiologyCatalog.match(item.name)?.id` for each item before saving.
2. **One-time backfill**: on first launch of this version, walk existing `data.labs` and fill
   missing `canonicalId`s (idempotent — only touches nil ids), then persist.
3. `parseLabs` prompt: add "Also return `collectedDate` (yyyy-MM-dd) as printed on the report; if
   absent return empty string." Save into `LabRecord.collectedDate`; when empty, fall back to the
   existing `date` (import day). All series use `collectedDate.isEmpty ? date : collectedDate`.
4. **Dedup guard:** re-uploading the same report is common. Before appending a new `LabRecord`,
   check for an existing record with the same effective date and ≥80% identical (canonicalId,
   value) pairs — if found, show "This looks like a report you already imported on <date>" with
   Replace / Keep both / Cancel.

## Step 3 — Series building (pure, in `BiologyCatalog`)
`func series(for key: SeriesKey, labs: [LabRecord], bodyComps: [BodyComp]) -> [(date, value)]`
where `SeriesKey` is `.canonical(id)` or `.reportName(String)`:
- Collect matching items across all records; convert values to the canonical unit via `altUnits`
  when the reported unit differs (unknown units: keep raw value but tag the point "unit?" — never
  silently mix scales, see edge cases).
- Sort by date; same-day duplicates: keep the later record's value.
- Body analytes read from `bodyComps` (and weight can also merge the entry-level smoothed weight —
  v1: bodyComps only, one source, no mixing).

## Step 4 — Biology browser + detail (`BiologyView.swift`)
- **Entry point:** a "Biology" card in `HealthView` (house style, mirrors the existing imports
  section) showing counts ("34 measurements · last report May 12") → pushes `BiologyView`.
- **Browser:** sections by category (unknown analytes under "Other — from your reports"), each row:
  name, latest value + unit, date, colored dot (in/out of general range; grey when no range),
  small trend arrow using `direction` (e.g. LDL ↓ = green). A search field filters by name/alias.
- **Detail (tap a row):** large graph of the full series — reuse `LineChartView`
  ([ChartsView.swift](WinTheDay/Trends/ChartsView.swift)) with a shaded reference band when a range
  exists; below it, every reading as a list row (date, value, source report title; tapping opens
  that `LabRecord`'s existing report card). A single point renders as a dot + "one reading — trends
  appear after your next report", not an empty chart.
- **Correlations block** (detail view, below the readings): see step 5.

## Step 5 — Correlations (deterministic, honest)
In `BiologyCatalog`: Pearson correlation over **paired-by-nearest-date** points:
- For analyte×analyte: pair readings within ±14 days of each other (labs from the same panel pair
  naturally); require **n ≥ 5 pairs** to show anything.
- For analyte×app-metric (weight trend, avg readiness, avg sleep hours, protein): pair the lab
  date against the app metric's **trailing 30-day mean** ending that date (single-day app values
  vs quarterly labs is noise; the window is the honest comparison).
- Detail view shows the top 3 |r| ≥ 0.5 as plain sentences: "When your average sleep was higher,
  ferritin tended to be higher (r = 0.72, 6 readings)". Always footnoted:
  "Correlation, not causation — discuss with your doctor."
- A "Correlations" summary card at the bottom of the browser lists the strongest 5 overall.
- No AI in the math. The coach may *explain* a correlation via existing chat (its `getHealthIndex`
  tool gains the latest values + trends), but never computes one.

## Step 6 — Tests + build
- EngineTests: alias matching (longest-first wins; "cholesterol, total" → total cholesterol),
  unit conversion (mmol/L glucose ×18.016 → mg/dL), series ordering + same-day dedup, Pearson
  against a hand-computed fixture, n<5 gate, tolerant decode round-trip for the two new fields.
- Device build (plain — no manager logic changed unless HealthManager was touched), install,
  verify with 2–3 real reports imported months apart.

## Edge cases a weaker model would miss
- **Unit chaos is the #1 real-world failure.** Indian labs report glucose in mg/dL, European in
  mmol/L; vitamin D in ng/mL vs nmol/L; hemoglobin g/dL vs g/L. Series MUST convert via
  `altUnits` before graphing; a point whose unit is unrecognized gets excluded from the graph line
  and listed with a "unit not recognized" badge — mixing scales silently would draw garbage
  trends and destroy trust.
- **`LabItem.value` is `Double`** — qualitative results ("Negative", "Trace") never reached
  storage. Fine, but the parse prompt should be told to skip non-numeric results explicitly
  rather than emit 0 (verify current prompt behavior; 0 would poison every series).
- **Import date ≠ collection date.** Old records only have import dates; after this ships both
  exist. Series must use the effective-date fallback everywhere, and the backfill must NOT
  invent collection dates for old records.
- **Alias collisions:** "T3" matches "free T3" text; "iron" appears inside "iron binding
  capacity". Longest-alias-first matching plus word-boundary checks on short aliases (≤4 chars
  must match as whole words) — test both cases.
- **Trend arrows need `direction`:** a rising value is good for HDL, bad for LDL, neutral for
  sodium. Never color a trend without it; unknown analytes get neutral styling.
- **Reference-range liability:** ranges vary by lab, age, sex, pregnancy. General ranges are a
  courtesy visualization — the out-of-range dot must never say "abnormal", only "outside general
  range", and the app gives no interpretation or advice (same guardrail as
  PLAN-medication-supplements: tracking yes, advising no).
- **Sparse data is the norm** — most users have 1–3 reports. Every surface needs a designed
  n=1 state (browser still useful as "latest values" table; correlations simply absent). Do not
  gate the whole section on having trends.
- **Canonical ids are persisted identifiers** — never localize or rename them once shipped
  (same trap as module keys).
- The correlation pairing must use the app's `yyyy-MM-dd` key conventions and POSIX date parsing
  (see localization plan's formatter warning) — no `Date()` arithmetic across DST/timezones.

## Acceptance criteria
- [ ] Importing a lab PDF produces items with `canonicalId` set for known analytes; a made-up
      analyte name ("Foobarase") still appears in the browser under "Other" with its report name.
- [ ] Existing (pre-update) lab records appear in the browser after the backfill, untouched
      otherwise; old data loads (tolerant round-trip green in EngineTests).
- [ ] Two reports with glucose in mg/dL and mmol/L graph as one coherent series in mg/dL.
- [ ] Tapping HbA1c shows all readings over time with the reference band and per-reading source;
      one-reading analytes show the designed single-point state.
- [ ] Re-uploading the same report triggers the dedup prompt; "Replace" leaves counts unchanged.
- [ ] Correlations appear only with ≥5 pairs, with r, n, and the causation disclaimer; the
      InBody weight series correlates against a lab analyte when enough data exists.
- [ ] `getHealthIndex` coach tool includes latest values + trend directions; asking the coach
      "how's my vitamin D trending?" answers from real data.
- [ ] EngineTests green; device build green.
