# AUTH-02 — App's Face ID "App lock" does not cover the Siri/Shortcuts surface — score, prayers, water and location-derived next-prayer time are readable, and the day log is writable, on an unlocked-but-app-locked device

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | App lock & auth |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | Shortcuts / AppIntents surface |
| **Location(s)** | `WinTheDay/App/AppIntentsSupport.swift`, `WinTheDay/Managers/AppLock.swift`, `WinTheDay/App/WinTheDayApp.swift` |

## Summary

The app advertises a Privacy → App lock (Face ID/Touch ID) feature, but the six auto-registered AppShortcuts read and mutate the same persisted day data with no lock check and no `authenticationPolicy`, so anyone holding an unlocked device can voice/Spotlight/Shortcuts their way past the lock to hear health/prayer data or corrupt the log while the app itself sits behind Face ID.

## Details

`AppLock` is, by its own documentation, purely a UI shield — nothing more:

```swift
// AppLock.swift:4-6
/// Optional Face ID / Touch ID gate over the whole app, plus the privacy cover the app switcher
/// screenshots. Local-only: nothing leaves the device, the lock is purely a UI shield over
/// `RootView` (widgets, the watch app and notifications are governed by iOS, not by this).
```

It publishes `locked`/`covered` flags that `WinTheDayApp` draws a cover over the tab UI with (WinTheDayApp.swift:42-47). It performs no gating of data access — `DayStore` and the intents never consult it. Note the doc comment lists the surfaces iOS governs (widgets, watch, notifications) but never mentions Shortcuts/App Intents, so this gap appears unconsidered rather than an intentional documented exclusion.

Every intent in `AppIntentsSupport.swift` reads/writes the persisted blob directly with zero auth:

- `DayStatusIntent` (AppIntentsSupport.swift:219-233) speaks a summary built from stored data — score, `e.prayers.count`, `Double(e.waterMl)/1000` litres, and `DayStore.nextPrayerText()`. The last is derived from the stored `prayer_lat`/`prayer_lon` coordinates via `prayerContext()` (AppIntentsSupport.swift:75-95), i.e. it discloses a location-derived value.
- `TodayScoreIntent` (172-180) speaks the score via `DayStore.loadData()`.
- `LogWaterIntent` (136-147), `MarkPrayerIntent` (149-170), `LogWeightIntent` (183-200) all mutate today's `Entry` through `DayStore.mutateToday` (AppIntentsSupport.swift:44-56), which writes `suhail_health_v2` unconditionally (`saveData` at line 24-26) and reloads widget timelines.
- `StartFocusIntent` (202-217) sets `openFocusKey`; it does set `openAppWhenRun = true` (line 206), so it alone would surface the lock — the other five do not.

Confirmed via grep that **no** intent in the app sets `authenticationPolicy` (only `WidgetActionIntents.swift` sets `isDiscoverable = false`, unrelated). These intents are registered as user-facing `AppShortcuts` in `WinTheDayShortcuts` (AppIntentsSupport.swift:236-263), so they are invocable from Siri, the Shortcuts app, and Spotlight without ever entering the app's locked UI.

Scope note on severity: the deeper *device* lock is still enforced by iOS (the default intent authentication behaviour requires the device to be unlocked before an intent performs), so this is not a bypass of the passcode. What it bypasses is the app's own advertised Face ID lock: on an unlocked device where the user relies on that per-app lock to shield this data (exactly threat model a — a briefly-handed-over unlocked phone), the shield does not apply to this surface. The exposed read surface is also narrow — a 5-field daily summary plus a next-prayer time, not the full health index (conditions/meds/injuries), and no biometric or key material — which is why this is Medium rather than High.

## Failure / exploit scenario

**Threat model (a): unlocked device handed over briefly, user relying on the app's Face ID lock.** The owner has enabled Privacy → App lock, so opening "Win the Day" shows the Face ID shield. The borrower instead says "Hey Siri, how's my day going in Win the Day" (or runs the "Day Status" shortcut from Spotlight) and hears: "Today: you're at 3 of 5, 2 to go, 4 of 5 prayers, 1.2 litres of water, next up Maghrib at 8:41 pm" — health and a location-derived prayer time, spoken past the lock. They then say "Log my weight 250 in Win the Day" or "Mark Isha prayed", silently corrupting the persisted record via `DayStore.mutateToday`. The app never unlocked; the owner sees nothing until later.

## Impact

The app's advertised per-app Face ID lock provides no protection for the Shortcuts/Siri/Spotlight surface. On an unlocked device, an attacker with brief physical access can (a) read a daily health summary including a location-derived next-prayer time, and (b) mutate the day log — falsify weight, water, and prayer marks — while the app sits behind Face ID. This is a confidentiality and integrity gap against the specific defense (app lock) the user opted into. It is not a device-passcode bypass and does not expose the full health index or any credentials, which bounds the impact.

## Recommendation

For read intents that surface personal data (DayStatusIntent, TodayScoreIntent), gate on appLockEnabled and require authentication (set the intent's authenticationPolicy / return a needs-to-continue-in-app result when locked), or at minimum exclude them from lock-screen Siri. Consider requiring device unlock for mutating intents when app lock is on. Document that Shortcuts are outside the lock if this is intended.

## References

- CWE-306: Missing Authentication for Critical Function
- Apple Developer: AppIntent authenticationPolicy / IntentAuthenticationPolicy


---

_Finding AUTH-02. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._