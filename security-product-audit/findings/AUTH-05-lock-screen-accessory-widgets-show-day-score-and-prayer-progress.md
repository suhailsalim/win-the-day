# AUTH-05 — Lock-screen accessory widgets show day score and prayer progress on a locked device, outside app-lock control (by-design iOS behavior; report's calorie/protein/water claim is inaccurate)

| Field | Value |
|---|---|
| **Severity** | Informational |
| **Category** | Privacy & compliance |
| **Status** | PLAUSIBLE |
| **Confidence** | high |
| **Area** | Lock coverage boundary |
| **Location(s)** | `WinTheDay/App/AppIntentsSupport.swift`, `WinTheDay/Managers/AppLock.swift`, `PrayerWidgetExt/LockWidgets.swift`, `PrayerWidgetExt/HomeWidgets.swift`, `Shared/SharedSnapshot.swift` |

## Summary

User-opt-in iOS lock-screen (accessory) widgets render the day's non-negotiables score, prayers-done count, next prayer, readiness, fasting and week progress on a locked phone; the app's Face ID lock cannot and does not govern them. This is standard, disclosed, glanceable-widget behavior, not a code defect — and the reported claim that calories/protein/water appear on the lock screen is wrong (those are home-screen-only widgets that require an unlocked device).

## Details

The exposure surface is real but narrower than reported.

`AppIntentsSupport.swift:115-123` `publishSnapshot` writes the App-Group `SharedSnapshot`:

```
s.score = score(e); s.nnDone = s.score
s.prayersDone = e.prayers.count
s.waterMl = e.waterMl
s.caloriesText = e.calories.isEmpty ? "—" : e.calories
s.proteinText  = e.proteinG.isEmpty ? "—" : e.proteinG
```

All five fields land in the shared store, but **what actually renders on the lock screen** is only what the *accessory* widgets read. In `PrayerWidgetExt/LockWidgets.swift` the accessory families are:
- `LockSummaryWidget` (`.accessoryRectangular`, line 41-58): `"\(s.score)/5 today · \(s.prayersDone)/5 prayers"` plus next prayer name/time.
- `LockNonNegotiablesWidget` (`.accessoryCircular`, line 6-22): score gauge `nnDone`.
- `LockNextPrayerWidget` (`.accessoryInline`, line 24-39), `LockFastingWidget`, `LockWeekProgressWidget`, `LockReadinessWidget`, `LockWeatherWidget`.

None of the lock-screen widgets read `caloriesText`, `proteinText`, or `waterMl`. Those three are consumed only by the **home-screen** families in `PrayerWidgetExt/HomeWidgets.swift` (`.supportedFamilies([.systemSmall])` / `.systemMedium`, e.g. water at HomeWidgets.swift:404/428/465), which are not visible on a locked device. So the report's "calories/protein/water … on the lock screen" is factually incorrect; only aggregate score, prayer count, next-prayer time, readiness, fasting and days-won are lock-screen-visible.

`AppLock.swift:4-6` documents the boundary accurately and honestly:

```
/// Local-only: nothing leaves the device, the lock is purely a UI shield over
/// `RootView` (widgets, the watch app and notifications are governed by iOS, not by this).
```

This comment is correct, not a defect. An app **cannot** make iOS lock-screen widgets respect its own in-app Face ID gate — accessory widgets are rendered by the OS specifically to be glanceable on the Lock Screen, which is exactly what the user opts into when adding one. The watch mirror (`PhoneSync.swift`) and the reminder notifications (`PrayerManager.swift:280-281`, `HydrationManager.swift:60-61`, `AppStore.swift:724-725`, `FocusScreenView.swift:168-169`) carry only generic reminder copy ("It's time for Fajr", "Hydrate 💧", session name + minutes) — no numeric health values or medical detail (conditions/meds/labs never reach any widget snapshot).

Net: the underlying observation (a day summary is visible on a locked screen if the user adds the widget) is confirmed, but it is intentional, user-controlled OS behavior with no sensitive-medical content and honest in-code disclosure — Informational, not Medium.

## Failure / exploit scenario

Threat model (a), brief physical access to a locked device: the user has voluntarily added the "Day Summary" accessory widget to their Lock Screen. A passerby glancing at the locked phone sees e.g. "3/5 today · 4/5 prayers" and the next prayer time. They cannot see calories, protein, water, weight, conditions, meds, or any labs — none of those reach lock-screen widgets. The Face ID app lock (`AppLock`) never applies because iOS, not the app, renders accessory widgets; this is inherent to the widget the user chose to add and matches how every Lock Screen widget (Fitness rings, Health, etc.) behaves.

## Impact

Low-sensitivity, aggregate discipline/prayer metrics (a 0-5 score and an X/5 prayer count) can be read from a locked screen only if the user explicitly installs the app's accessory widget. No medical, dietary-detail, biometric, or location data is exposed via this path. The reported blast radius (calories/protein/water on the lock screen) does not exist in the code. The main residual is expectation-alignment: a user who enabled in-app Face ID may not realize a widget they separately added is outside that lock.

## Recommendation

Document clearly that widgets/watch/notifications are outside the lock, and consider redacting or omitting sensitive numbers from lock-screen-eligible widget snapshots when app lock is enabled. At minimum align marketing copy with this reality (see the overpromise finding).

## References

- Apple Developer: WidgetKit accessory families (accessoryCircular/Rectangular/Inline) render on the Lock Screen by design
- CWE-200: Exposure of Sensitive Information to an Unauthorized Actor (low applicability here)


---

_Finding AUTH-05. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._