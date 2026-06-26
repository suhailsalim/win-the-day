# Sleep & readiness

## Sleep detail (HealthKit)
- `HealthManager.fetchSleepDetail(nightEnding:)` reads `HKCategoryType.sleepAnalysis` over a
  ~6pm→noon window and produces `SleepBreakdown` (asleep/inBed/deep/REM/core/awake minutes, bed/wake
  times, efficiency). Degrades gracefully when stages aren't recorded (only total asleep).
- Per-day HRV / resting-HR fetchers + 30-day baselines: `fetchHRV`, `fetchRestingHR`,
  `hrvBaseline()`, `rhrBaseline()`.

## Readiness score (the algorithm layer)
`ReadinessScorer.compute(_:)` → `(readiness 0–100, sleepScore 0–100, factors)`:
- **Sleep sub-score**: duration vs ~7.5h target + efficiency + (deep+REM) proportion.
- **Readiness** = sleep base, adjusted by **HRV vs baseline** (±12), **resting HR vs baseline** (±8),
  **prior-day load** (high active energy → slight deload), and a **late-dinner penalty** (dinner
  close to bedtime, from [meal times](logging-and-meals.md)).
- `ReadinessFactor`s give an explainable +/- breakdown.

## Wiring
- `AppStore.computeReadiness(for:health:)` runs on day load (`TodayView.task(id:store.date)`), caches
  `Entry.sleep/readiness/sleepScore`, and publishes `readiness`/`sleepScore` to the
  [snapshot](widgets-watch.md).
- UI: the **Sleep & readiness** Today module (ring + stage bars + factors) and a Trends readiness
  chart. Optional **sleep habit** via `HabitLinkType.sleep`.

> Caveat: sleep stages / HRV depend on what the user's Apple Watch records.

## Key files
`HealthManager.swift`, `ReadinessScorer.swift`, `Models.swift` (`SleepBreakdown`, `ReadinessFactor`,
`Entry.sleep/readiness/sleepScore`), `TodayView.swift` (`sleepModule`), `TrendsView.swift`.
