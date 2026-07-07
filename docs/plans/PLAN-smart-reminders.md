# PLAN: Smart reminder engine (streak-at-risk, dinner cutoff, bedtime, habit nudges)

## Goal
Notifications today are per-concern schedules (prayer, hydration, sessions, weekly review). Add a
small deterministic **reminder engine** that fires the *right* nudge at the right moment based on
the day's actual state: "3 habits left and it's 8pm — your streak is at risk", "dinner by 7:40pm
protects tonight's sleep plan", "recommended bedtime in 30 min", "you're 40g short on protein with
one meal left". No AI calls; pure rules over data already computed.

## Files to touch
- `WinTheDay/Engines/ReminderEngine.swift` — NEW: pure enum producing `[PlannedReminder]` from a value
  snapshot (mirrors the ScoreEngine pattern: testable, non-isolated).
- `WinTheDay/Core/AppStore.swift` — build the snapshot + schedule on every `persistData()`-adjacent
  mutation (debounced) and on app background.
- `WinTheDay/Settings/SettingsView.swift` + `Models.swift` — `AppSettings.smartReminders` master toggle +
  per-rule toggles (tolerant decode lines!).

## Steps, in order
1. Read the existing notification code first (grep `UNUserNotificationCenter` — hydration and
   session scheduling show the house pattern, including the id-prefix convention). New prefix:
   `smart-` (AGENTS.md convention 6: one prefix per concern, clear-and-reschedule by prefix).
2. Define rules (each returns at most one reminder, with a fire date and text):
   - **Streak risk**: day not yet won, ≥2 habits pending, fire at a user-set evening hour
     (default 20:00) — skip if day status is rest/sick/travel.
   - **Dinner cutoff**: from the sleep plan's dinner-cutoff epoch, fire 30 min before, only if
     dinner meal is still empty.
   - **Bedtime**: 30 min before recommended bed time, only if enabled.
   - **Protein gap**: at 18:00 if protein < 70% of target.
   - **Prayer follow-up** is explicitly NOT here — prayer notifications already exist.
3. Scheduling: on each recompute, remove all pending `smart-` requests, then add the current set
   (≤4/day). Never schedule into the past; never schedule for non-today.
4. Settings UI: master toggle + one toggle per rule, plus the evening-hour picker.
5. Build with strict concurrency (notification-center closures: snapshot MainActor state into
   locals first — this exact pitfall is called out in AGENTS.md).
6. Verify on device: set targets so a rule triggers, background the app, receive the nudge.

## Edge cases a weaker model would miss
- Rescheduling on **every** mutation spams the notification center — debounce (e.g. schedule on
  `scenePhase == .background` plus at most once per minute in-app).
- Day rollover: reminders computed yesterday must not fire today — include the date in the
  request id (`smart-streak-2026-07-07`) and clear by prefix on schedule.
- Respect the quiet case: if the user never granted notification permission, the engine should
  no-op silently, not re-prompt.
- Tone: nudges must match the app's non-shaming voice ("Your streak's within reach — 2 quick
  habits left"), not guilt-trips. Keep copy in one place (the engine) for easy revision.
- All-toggles-off must cancel any already-scheduled `smart-` requests, not just stop adding.

## Acceptance criteria
- [ ] With a losing day at the configured hour, exactly one streak nudge fires; a won day fires
      none; a "sick" day fires none.
- [ ] Empty dinner + sleep plan → dinner-cutoff reminder at cutoff−30min; logging dinner first
      cancels it.
- [ ] `smart-` requests visible via a debug dump contain the date in their ids; no duplicates
      after repeated app foreground/background cycles.
- [ ] Engine covered by unit tests in EngineTests (pure function: state in → reminders out).
- [ ] Build green under `SWIFT_STRICT_CONCURRENCY=complete`.
