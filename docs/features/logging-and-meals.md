# Logging & meals

## Meals + AI estimate
- Five meal fields (breakfast/snacks/lunch/dinner/drinks) on Today → `Entry.meals` (`Meals`).
- **Estimate my day** calls `AIEstimator.estimate(meals:knownFoods:settings:)` → `AIResult`
  (per-meal + day totals incl. macros, fiber, micros). Auto-fills `calories`/`proteinG`.
- The estimator is given the user's **catalog** ("known foods") so it reuses verified values.
- Time-of-day nudge highlights the current meal (`AppStore.mealNudge`).

## Meal times
- `Entry.mealTimes: [String: Double]` (meal key → epoch). **Auto-stamped** the first time a meal gets
  content today (in `TodayView.mealBinding` setter); editable via the clock chip → `MealTimeSheet`
  (`AppStore.setMealTime`). Feeds the late-dinner factor in [readiness](sleep-readiness.md) and the
  coach context.

## Quick log (catalog)
- A library of supplements & foods (`CatalogItem`, `CatalogView`), built by hand or via AI from a
  **photo / barcode / text** (`AIEstimator.parseItem`, `BarcodeScanner` → Open Food Facts lookup).
  Captures calories/macros/fiber + **micronutrients** (`Micro`).
- Today shows tappable chips. Tapping logs **1 serving**; a logged chip becomes a stepper
  `[− Name ×N +]` for **multiple doses** (e.g. 2 scoops of whey). Backed by `LoggedItem.qty`
  (per-serving values × qty). Methods: `addServing` / `removeServing` / `setLoggedQty` / `toggleLogged`.

## Micronutrient aggregation
- `AppStore.dayNutrients()` merges quick-logged items (× qty) **and** the AI estimate's micros into
  carbs/fat/fiber + a summed micro list. Shown under Quick Log and as RDA progress on
  [Trends](habits-scoring.md) via `microProgress()` against `NutritionRDA`.

## Key files
`Models.swift` (`Meals`, `CatalogItem`, `LoggedItem`, `Micro`, `AIResult`, `NutritionRDA`),
`AppStore.swift` (quick-log + aggregation), `AIEstimator.swift`, `CatalogView.swift`,
`BarcodeScanner.swift`, `TodayView.swift` (`mealsCard`, `chip`, `microsSummary`).
