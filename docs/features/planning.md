# Planning: Plan tab, routine, sessions, events, calendar, weather

The **Plan tab** (`PlanView`) is the home for winning the week.

## Week outlook
`AppStore.refreshWeekOutlook(eventsText:)` → an AI look-ahead (via `estimator.suggest`) built from
weekly stats, insights, upcoming sessions/occasions, and the user's real **calendar** events. Cached
in UserDefaults (`week_outlook`). Plus a Mon–Sun **week grid** (won/logged/today) from `weekProgress()`.

## Routine → sessions
- `RoutineBlock` (in `AppData.routine`): a recurring weekly template (weekday/time/kind/duration/PT).
  Edited in `RoutineEditorView`.
- `ScheduledSession` (in `AppData.sessions`): concrete one-off **or** routine-materialised sessions
  (`generateWeekFromRoutine`). Kinds include pt/strength/cardio/run/walk/fitnessplus/mobility/stretch/
  cooldown/winddown/work/focus/meal. `SessionEditorView` to add/edit.
- On save: a `session-` reminder is scheduled and (if `calendarSync`) an event + reminder are written
  via `CalendarManager`. Completing a session satisfies the movement habit.

## Calendar & Reminders (`CalendarManager`, EventKit + Contacts)
- iOS-17 full-access requests. Reads `upcomingEvents`/`eventsOn` to plan around real commitments;
  writes to a dedicated **"Win the Day"** calendar + reminders list. Toggles in Settings
  (`AppSettings.calendarSync`/`remindersSync`).
- Imports birthdays/anniversaries from Contacts + the system Birthdays calendar.

## Events & travel (`Occasion`)
- `Occasion` (birthday/anniversary/wedding/travel/custom, recurring-annual) in `AppData.occasions`,
  edited in `OccasionEditorView`. **Plan it with AI** (`AIEstimator.planOccasion`) generates gift
  ideas + a prep checklist, and for travel a day-by-day itinerary (can parse a pasted booking).
- Travel occasions auto-flag those days as `travel` ([day status](habits-scoring.md)).

## AI week plan generator
`AIEstimator.generateWeekPlan` → `[PlanBlock]` (workouts, work/focus, stretch/cooldown/wind-down,
walk + meal reminders), balanced around calendar, readiness, health profile and **flagged days**.
Review in `WeekPlanReviewView`, then `applyWeekPlan` materialises enabled blocks into sessions
(auto-skipping hard sessions on sick/travel/rest days). `clearAIPlan` removes a prior AI plan.

## Weather (`WeatherManager`, Open-Meteo — free, no key)
- Current + 7-day + hourly from the cached location. `outdoorAdvice()` (walk/run vs indoor based on
  precip/temp/thunder) + `bestOutdoorWindow()`. Weather Today module; summary fed into the planner
  and daily suggestion. (WeatherKit needs a paid membership, hence Open-Meteo.)

## Key files
`PlanView.swift`, `RoutineEditorView.swift`, `SessionEditorView.swift`, `OccasionEditorView.swift`,
`WeekPlanReviewView.swift`, `CalendarManager.swift`, `WeatherManager.swift`,
`AppStore.swift` (routine/session/occasion CRUD, `generateAIWeekPlan`/`applyWeekPlan`),
`AIEstimator.swift` (`generateWeekPlan`, `planOccasion`), `Models.swift`.
