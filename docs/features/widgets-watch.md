# Widgets, watch & Live Activities

## Shared snapshot (the data bridge)
`Shared/SharedSnapshot.swift` defines `SharedSnapshot` (a small Codable payload) and `SharedStore`
(read/write to the two App Groups). Surfaces include score/prayers/water, next prayer, fasting, week
progress, workouts, next session/occasion, readiness/sleep, day status, and weather.

**To add a field:** add a defaulted property to `SharedSnapshot`, write it in the relevant
`publishSnapshot()` (`AppStore` for app state; `PrayerManager`/`FastingManager`/`WeatherManager` for
theirs — each writes to **both** app groups), then read it in the widget/complication. New `Shared/`
files must be added to all consuming targets in `project.pbxproj`.

## iOS widgets (`PrayerWidgetExt`)
- Home (`HomeWidgets.swift`): NextPrayer, NonNegotiables ring, Summary, Fasting, WeekProgress,
  Readiness, Weather, NextSession, UpcomingEvent.
- Lock (`LockWidgets.swift`): accessory variants (non-negotiables gauge, next prayer, summary,
  fasting, week, readiness, weather).
- Registered in `PrayerWidgetBundle.swift`. Timeline refresh ~15 min.

## Live Activities
- Prayer (`PrayerLiveActivityWidget` + `Shared/PrayerActivityAttributes.swift`) — 20-min post-adhan
  window.
- Study (`StudyLiveActivityWidget` + `Shared/StudyActivityAttributes.swift`) — `StudyTimer` session.

## Watch app (`WinTheDayWatch`)
`WatchView` shows score, next prayer, week ring, fasting (start/end), readiness + weather, next
session, water (+250 ml), and prayer toggles. Syncs via `WatchSync` ↔ `PhoneSync`
(WatchConnectivity): phone pushes the snapshot, watch sends actions back
(`AppStore.applyWatchAction`: water/prayer/fast_start/fast_end/workout_quick).

## Watch complications (`WatchWidgetExt`)
`WatchComplications.swift`: score, next prayer, week, fasting, next session, readiness, weather,
summary. Registered in `WatchWidgetBundle.swift`; read the watch App Group.

> The watch binary often needs a manual reinstall from the iPhone Watch app (wireless install
> error 4000). It's unaffected by phone-only builds.

## Key files
`Shared/SharedSnapshot.swift`, `PrayerWidgetExt/*`, `WatchWidgetExt/*`, `WinTheDayWatch/*`,
`WinTheDay/PhoneSync.swift`, publishers in `AppStore`/`PrayerManager`/`FastingManager`/`WeatherManager`.
