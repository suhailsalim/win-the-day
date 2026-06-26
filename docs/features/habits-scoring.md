# Habits, scoring & day status

## Configurable habits
- `HabitDef` (in `AppData.habits`) with a `Pillar` (health/spirituality/work/custom) and a
  `HabitLinkType`: `manual`, `protein`, `prayer`, `steps`, `activeEnergy`, `water`, `studyHours`,
  `sleep`. Auto-linked habits read entry/Health data; manual ones are tapped.
- Edited in `HabitsEditorView`. Starter habits are seeded per area during onboarding
  (`HabitDef.starters`).

## Scoring & streak
- `AppStore.isSatisfied(_:_:)` evaluates each active habit for a day; `score(_:)` = count satisfied;
  `dayWon(_:)` = ≥60% of active habits.
- `streak()` = consecutive winning days ending today, but **protected days (sick/travel/rest) pause
  the streak** instead of breaking it.
- `weeklyStats()` and rule-based `insights()` power the Trends cards. `score`/`dayWon` also feed the
  week grid and widgets.

## Day status (sick / travel / rest)
- `Entry.status` (normal|sick|travel|rest) set via the "Mark day" chip under the Today header
  (`setDayStatus`). `effectiveStatus(for:)` returns the manual status, or auto-**travel** if a travel
  [occasion](planning.md) covers the date.
- Protected days: pause the streak, keep the coach gentle, and make the [AI planner](planning.md)
  skip hard sessions.

## Trends
`TrendsView` cards: weekly AI review, insights ("what's working"), the personal **prize** metric,
stat grid, readiness, micronutrients, training, body-comp & metric charts (week/30d/all range).

## Key files
`Models.swift` (`HabitDef`, `Pillar`, `HabitLinkType`, `DayStatus`, `Targets`),
`AppStore.swift` (`isSatisfied`/`score`/`dayWon`/`streak`/`insights`/`weeklyStats`/`setDayStatus`/
`effectiveStatus`), `TodayView.swift` (`habitsSection`, `scoreCard`, `statusChip`), `TrendsView.swift`.
