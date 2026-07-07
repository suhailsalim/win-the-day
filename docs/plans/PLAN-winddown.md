# PLAN: Evening wind-down flow — close today, set up tomorrow

## Goal
The app opens strong in the morning (scores, rings) but has no evening ritual, and evenings are
where days are actually won or lost. Add a 60-second guided **wind-down**: review today (what's
done, what's left), do the sleep check-in, see tonight's bedtime/dinner plan, and set tomorrow's
one **main focus**. Fired from a gentle notification at a user-chosen time (default: recommended
bedtime − 45 min).

## Files to touch
- `WinTheDay/Today/WindDownView.swift` — NEW: a paged sheet (3 short pages).
- `WinTheDay/Today/TodayView.swift` — "Tomorrow's focus" chip on the header when set + entry point.
- `WinTheDay/Core/AppStore.swift` — `Entry.tomorrowFocus` passthrough + schedule the `winddown-`
  notification.
- `WinTheDay/Core/Models.swift` — `Entry.mainFocus: String = ""` (the day's own focus, set the night
  before onto TOMORROW's entry) + `AppSettings.windDownHour` override (+ tolerant decode lines).
- Depends on: PLAN-checkin-sheet.md (reuses `CheckInSheet` content as page 2 — build that first
  or inline the same fields).

## Steps, in order
1. Page 1 — "Today": day score, habits still open (tappable to complete right there), water/protein
   gaps. Reuse existing module row components; no new data.
2. Page 2 — "Body": the daily check-in fields (soreness/stress/alcohol/caffeine/illness) writing
   through the same `updateCheckIn` path.
3. Page 3 — "Tomorrow": recommended bedtime + dinner-cutoff recap (from the sleep plan), plus one
   text field: "Tomorrow's main focus". Saving writes `mainFocus` onto **tomorrow's** entry
   (create it if absent — check how AppStore creates future/other-day entries; follow `goTo`'s
   pattern) and schedules nothing else.
4. Tomorrow morning, TodayView shows the focus as a header chip; tapping toggles it done (a
   completed focus can satisfy a linked manual habit if one is named identically — v2; keep v1
   display-only).
5. Notification: id `winddown-<date>`, scheduled when the sleep plan computes bedtime; user hour
   override wins. Deep-link the notification to open the wind-down sheet (check how existing
   notifications route taps — if no routing exists, add the minimal `UNUserNotificationCenter`
   delegate hook in `WinTheDayApp`).
6. Build strict, verify the full evening → morning loop on device, commit.

## Edge cases a weaker model would miss
- **Tomorrow's entry may not exist yet** — creating it must go through the same tolerant creation
  path the date navigator uses, or the next morning's load will overwrite it. Verify by setting a
  focus, then logging normally the next day.
- After Islamic-midnight-adjacent bedtimes: "tomorrow" means calendar-tomorrow relative to the
  moment of the wind-down, which after midnight is *today* — compute the target day as
  "the day the user is about to wake into": if `now.hour < 4`, target today's date, else
  tomorrow's. State this rule in a comment.
- The wind-down must be skippable and never nag twice a night (`winddown-` id includes date).
- Don't double-schedule with PLAN-smart-reminders' bedtime nudge: if both ship, wind-down replaces
  the plain bedtime reminder (guard on the setting).
- Page 1's "complete habit" taps mutate today's entry while the sheet is open — the sheet must
  render from live store state, not a snapshot taken at open.

## Acceptance criteria
- [ ] Notification arrives at bedtime−45 (or override), opens the wind-down directly.
- [ ] Completing the three pages: check-in saved on today, focus saved on tomorrow, and next
      morning the chip shows it.
- [ ] Post-midnight run targets the correct "tomorrow".
- [ ] Skipping the flow entirely has zero side effects.
- [ ] Old data loads (new fields tolerant); build green strict.
