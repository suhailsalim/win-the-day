# PLAN: Verify, harden, and commit the uncommitted workouts + occasion-refine WIP

## Goal
There are ~308 uncommitted lines across 8 files (a nearly-finished feature batch). Ship it: fix the
small holes listed below, build green on device, verify, and commit. Until this lands, every other
piece of work risks conflicting with or clobbering this WIP.

What the WIP contains (already written, do NOT redo):
- `HealthWorkout` struct + `HealthManager.loadWorkouts(for:maxHR:)` + `fetchHRStats` + HR-zone buckets
  ([HealthManager.swift](WinTheDay/Managers/HealthManager.swift), new code around line 404).
- Today "From Apple Fitness" card with HR-zone bar + `AppStore.autofillJog(from:)`
  ([TodayView.swift](WinTheDay/Today/TodayView.swift) ~line 636, [AppStore.swift](WinTheDay/Core/AppStore.swift) ~line 1808).
- Occasion `context` field + AI plan **refine** flow (`planOccasion(_:pasted:refine:)`), editable
  checklist/itinerary rows ([OccasionEditorView.swift](WinTheDay/Plan/OccasionEditorView.swift), Models.swift, AIEstimator.swift).
- HistoryView date-picker self-dismiss guard; RootView `.id(store.tab)` scroll reset.
- `loadStepsHistory` default 14 → 90 days.

## Files to touch
- `WinTheDay/Managers/HealthManager.swift` (small fixes only)
- `WinTheDay/Today/TodayView.swift` (task keying fix)
- `WinTheDay/Core/AppStore.swift` (autofillJog guard)
- Everything else in the diff: review, do not rewrite.

## Steps, in order
1. `git diff` — read the whole diff once so you know exactly what is in flight.
2. **Fix stale workouts on day change.** In `TodayView`, the `.task` that calls
   `health.loadWorkouts(for: store.date, ...)` must re-run when the user navigates to another day.
   Find the `.task` block containing `loadWorkouts`; if it is a plain `.task {}` (runs once per view
   identity), change it to `.task(id: store.date) { ... }` so browsing History → past day reloads
   that day's workouts instead of showing today's. If a `.task(id:)` already exists, confirm the id
   includes `store.date` and move on.
3. **maxHR sanity.** `TodayView` calls `loadWorkouts(for:maxHR: 208 - 0.7 * store.targets.ageYears)`.
   When `ageYears` is 0/unset this yields 208 and skews HR zones low. Compute
   `let mhr = store.targets.ageYears > 0 ? 208 - 0.7 * store.targets.ageYears : 190` and pass `mhr`.
   (`fetchHRStats` already falls back to 190 only when maxHR ≤ 0 — 208 passes that guard, hence
   this call-site fix.)
4. **`autofillJog` numeric guard.** `Double(draft.run) ?? 0` — `draft.run` is a free-text field;
   this is already nil-safe. Just confirm the `guard isToday` line is present (it is) and that the
   function is actually called from `TodayView` `.task` after `loadWorkouts` (it is). No change
   expected; verify only.
5. **Occasion `context` encode check.** `Occasion` has a hand-written tolerant `init(from:)` and the
   diff adds `context` decoding (Models.swift ~line 658). Confirm the struct has NO explicit
   `CodingKeys` enum (synthesized keys then include `context` automatically for encode). If an
   explicit `CodingKeys` enum exists in `Occasion`, add `case context` — otherwise the field decodes
   but is silently dropped on save (data loss on every edit). Search within the `struct Occasion`
   block only.
6. **Build** (device destination, strict concurrency, since HealthManager — a manager — was touched):
   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
     -project WinTheDay.xcodeproj -scheme WinTheDay -configuration Debug \
     -destination 'generic/platform=iOS' -allowProvisioningUpdates \
     SWIFT_STRICT_CONCURRENCY=complete -derivedDataPath build/dd build
   ```
   Fix any strict-concurrency errors per AGENTS.md (snapshot @MainActor state into locals before
   escaping closures; `withCheckedContinuation` blocks in `HealthManager` capture `store` — this is
   fine because `HKHealthStore` is Sendable-safe here, but if the compiler complains, capture the
   query locally first).
7. Install on device if one is connected (`xcrun devicectl list devices`); otherwise a green build
   suffices. Sanity: open Today (Fitness card appears if any workout logged today), open History →
   pick a past date (sheet must NOT auto-dismiss on open), edit an occasion → add context → Plan it.
8. Commit everything as one commit:
   `feat: Apple Fitness workout card + jog autofill, occasion AI refine, history picker fix`.

## Edge cases a weaker model would miss
- `.task` without `id:` runs once per view lifetime — day navigation silently shows the wrong day's
  workouts (step 2). This is the one real bug in the WIP.
- `Occasion.context` decode-without-encode is invisible until a user edits and reopens an occasion —
  tolerant decoding masks the wipe (step 5).
- `HealthManager` is `@MainActor`; `workoutsForDay` is `@Published`. Do not move `loadWorkouts` off
  the main actor to "optimize" — the HK queries already run off-main inside continuations.
- `hrZoneBar` divides by `total = max(1, ...)` — already safe; don't "fix" it.
- `w.id != workouts.last?.id` hairline logic breaks if two HKWorkouts share a UUID — they can't
  (HK UUIDs unique); leave it.
- `mark("prayer")`, RootView `.id(store.tab)`: the `.id` change resets scroll AND any `@State` in
  the scroll content when switching tabs. That is the intended behavior; don't remove it if some
  state resets look surprising.

## Acceptance criteria
- [ ] `xcodebuild` command in step 6 exits 0 with `SWIFT_STRICT_CONCURRENCY=complete`.
- [ ] `git status` shows a clean tree after commit; commit contains all 8 previously-modified files.
- [ ] `grep -n "task(id" WinTheDay/Today/TodayView.swift` shows the workouts load keyed on `store.date`.
- [ ] `Occasion` encodes `context`: either no explicit CodingKeys enum exists in the struct, or it
      contains `case context`.
- [ ] Opening History's date picker does not immediately dismiss the sheet (code guard present at
      [HistoryView.swift:32](WinTheDay/Trends/HistoryView.swift)).
