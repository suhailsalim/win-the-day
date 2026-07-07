# PLAN: Medication & supplement schedule tracking

## Goal
The catalog knows *what* supplements are, and health notes record conditions/meds as prose — but
nothing tracks **adherence**: "did I take my vitamin D / medication today?" Add scheduled
regimens with per-day check-off, reminder notifications, adherence history, and coach visibility
(read-only). High value for exactly the users who log labs and body comp.

## Files to touch
- `WinTheDay/Core/Models.swift` — `Regimen` struct (`{id, name, dose, timesOfDay: [String],
  daysOfWeek: Set<Int>, withFood: Bool, kind: med|supplement, active, startEpoch}`; tolerant) in
  `AppData.regimens`; `Entry.regimenTaken: [String: [String]] = [:]` (regimen id → times taken;
  tolerant decode).
- `WinTheDay/Today/RegimenEditorView.swift` — NEW editor (list + add/edit sheet).
- `WinTheDay/Today/TodayView.swift` — module `"regimen"` (convention 2 checklist, full wiring).
- `WinTheDay/Core/AppStore.swift` — take/untake methods + `regimen-` notification scheduling.
- `WinTheDay/AI/CoachTools.swift` — extend `getDay`/`getHealthIndex` output with adherence (no new
  tool needed).

## Steps, in order
1. Models + tolerant decodes; editor view (mirror `HabitsEditorView` structure and style).
2. Today module: grouped by time slot (morning/midday/evening from `timesOfDay`), tap to mark
   taken (records the actual timestamp in the entry — reuse the epoch-recording pattern prayers
   use), "with food" chip links visually to the nearest meal.
3. Notifications: prefix `regimen-`, one per regimen×time, repeating on scheduled weekdays;
   clear-and-reschedule by prefix whenever regimens change (convention 6).
4. Adherence in Trends: 30-day adherence % per regimen (simple: taken-slots / scheduled-slots),
   flag <80%.
5. Coach: append "Supplements/meds today: taken X of Y (missed: name)" to the `getDay` tool JSON.
6. Build strict, verify, commit.

## Edge cases a weaker model would miss
- **This is not a medical device**: no dosage advice, no interaction warnings, no "you should
  take" language anywhere — including from the coach (its system prompt already forbids inventing
  numbers; adherence is factual reporting only). Keep App Store health-app review guidelines in
  mind: tracking is fine, advising is not.
- Deleting a regimen must keep historical `regimenTaken` entries renderable (store the name
  snapshot in the entry? No — keep a `retiredRegimens` archive of `{id, name}` so history renders
  without dangling ids).
- Past-day marking works (traveling users backfill); notifications only ever schedule for
  today/future.
- Weekday scheduling uses the user's calendar — `Calendar.current.firstWeekday` varies; store
  weekdays as 1–7 Sunday-based (matching `DateComponents.weekday`) and convert only in UI.
- The module hides itself when no active regimens exist (like the fitness card), so non-users
  never see it.

## Acceptance criteria
- [ ] Create "Vitamin D, morning, daily, with food" → appears on Today each morning, reminder
      fires, tap records with timestamp, adherence chart reflects it.
- [ ] Editing times reschedules cleanly (no duplicate notifications — inspect pending requests).
- [ ] Deleting a regimen preserves past days' history display.
- [ ] Coach `getDay` includes adherence; no advisory language anywhere.
- [ ] Old data loads; build green strict.
