# PLAN: Daily check-in sheet — wire up the DayCheckIn model that nothing can edit

## Goal
`DayCheckIn` (soreness/stress/mood/alcohol/lateCaffeine/illness, [Models.swift:~765](WinTheDay/Core/Models.swift))
is persisted on every `Entry` ([Models.swift:80](WinTheDay/Core/Models.swift)) and `ScoreEngine` already
applies its `selfReportMultiplier` to Readiness ([ScoreEngine.swift:117,164](WinTheDay/Engines/ScoreEngine.swift))
— but **no UI anywhere sets it**, so it is always the default and the multiplier is dead code.
Build the small check-in sheet (the master plan's "CheckInSheet", milestone M1 leftover) and surface
the sensor-only vs adjusted Readiness transparency line.

## Files to touch
- `WinTheDay/Today/CheckInSheet.swift` — NEW (auto-joins the app target; no pbxproj edit needed).
- `WinTheDay/Today/TodayView.swift` — entry point button + sheet presentation.
- `WinTheDay/Core/AppStore.swift` — one mutation method + recompute hook.
- (Read-only reference: `WinTheDay/Engines/ScoreEngine.swift`, `WinTheDay/Core/Models.swift`.)

## Steps, in order
1. Read `DayCheckIn` in Models.swift for the exact field names/ranges (0–3 ints, bools). Read how
   `TodayView` presents other sheets (e.g. `MealTimeSheet`) and copy that presentation idiom.
2. `AppStore`: add
   ```swift
   func updateCheckIn(_ c: DayCheckIn) {
       mutate { $0.checkIn = c }
   }
   ```
   Follow the exact pattern of neighboring mutate-based setters (find `mutate {` call sites and
   mirror one). After mutating, trigger the same recompute path TodayView uses:
   `await computeReadiness(for: date, health: ...)` is called from the view layer — so instead have
   the sheet's Save closure call `store.updateCheckIn(c)` and then the view re-runs its existing
   readiness task (easiest: make the readiness `.task` in TodayView keyed on
   `store.draft.checkIn` too, or call the compute explicitly from the sheet's onDismiss).
3. `CheckInSheet.swift`: a small sheet in house style (GlassCard/`glassList()`, `Theme.*`,
   `SectionHeader`) with:
   - Three 0–3 segmented rows: Soreness, Stress, Mood (labels "None/Mild/Moderate/High"; for mood
     "Low/Meh/Good/Great" — mood is positive-coded, check how ScoreEngine consumes it before
     labeling; if ScoreEngine ignores `mood`, still record it).
   - Alcohol stepper 0–3 ("drinks"), toggles for "Caffeine after ~2pm" and "Feeling ill".
   - Optional bedtime-intent time picker ONLY if `DayCheckIn` has a `bedtimeIntentEpoch`-like field
     (check the struct; if absent, skip — do not add fields).
   - Save button → `store.updateCheckIn(local)` → dismiss.
   Initialize `@State private var local: DayCheckIn` from `store.draft.checkIn` in `init`/onAppear.
4. Entry point: in `TodayView`'s sleep/readiness module (search `readiness` in TodayView to find
   the ring/card), add a small "Check-in" pill button (with a filled variant when
   `store.draft.checkIn != DayCheckIn()` so the user sees it's been done). Present the sheet.
5. Transparency line: where the Readiness factors are listed (the readiness detail/ring sheet —
   find where `factors` from the score result are rendered), if the check-in multiplier < 1.0 show
   one caption: `"Sensor-only readiness: NN · adjusted by your check-in"`. Compute the sensor-only
   number by re-running the engine with `DayCheckIn()` — ScoreEngine is pure and cheap, so calling
   it twice is fine. If plumbing the second number through is invasive, an acceptable v1 is the
   caption "Adjusted down by today's check-in" with no number — prefer the number if ≤ ~15 lines.
6. Build (device destination; no manager touched, plain build OK), install, verify: set alcohol 3 +
   illness → Readiness drops (multiplier ≥ 0.85 floor), reopen app → check-in persists, past days
   unaffected.
7. Commit: `feat: daily check-in sheet wiring DayCheckIn into Readiness`.

## Edge cases a weaker model would miss
- **Editing past days:** `store.draft` is the currently-viewed day (History navigation changes it).
  Writing through `mutate {}` edits the viewed day's entry — that is correct and intended (you can
  backfill yesterday's check-in), but the sheet must read its initial state from `store.draft`
  each presentation, not cache today's. Use `.sheet(isPresented:)` + set `local` in `.onAppear`.
- **Readiness is cached on the entry** and recomputed by the existing compute path. If you only
  mutate `checkIn` and never re-run the compute, the ring won't move until the next app foreground
  — hence step 2's recompute hook. Verify the ring changes immediately after Save.
- `DayCheckIn()` equality check for the "done" pill needs `DayCheckIn: Equatable` — check the
  declaration; if not Equatable, add the conformance (it's Foundation-only, safe).
- Tolerant decode already exists for `checkIn` (Models.swift:119) — do NOT add new stored fields;
  if you must, every new field needs its tolerant decode line (AGENTS.md convention 1).
- The multiplier floor (0.85) means maxed-out penalties change Readiness modestly — don't "fix"
  the small delta; it's by design (trust guardrail).
- Sheet is a form on the main actor; no async needed except the recompute — keep Save synchronous
  and fire the recompute as a `Task { await ... }`.

## Acceptance criteria
- [ ] A check-in button is visible on the Today readiness/sleep module; tapping opens the sheet.
- [ ] Saving alcohol=3 + illness=true visibly lowers today's Readiness immediately (no relaunch).
- [ ] Kill + relaunch: the check-in values reopen exactly as saved (tolerant decode round-trip).
- [ ] Navigating to a past day and saving a check-in there changes only that day's readiness.
- [ ] A day with a non-default check-in shows the transparency caption in the readiness detail.
- [ ] Build green: standard device xcodebuild command from AGENTS.md exits 0.
