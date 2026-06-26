# Architecture

## Stack
- **SwiftUI**, iOS 17+ (watchOS app + widgets included), built with **Xcode 26**, Swift 6 / strict
  concurrency `complete`.
- **No backend.** All state is local. AI calls go directly from device to the chosen provider.

## Targets
| Target | Folder | Bundle id | Purpose |
|---|---|---|---|
| WinTheDay | `WinTheDay/` | `com.suhail.WinTheDay` | the iOS app |
| PrayerWidgetExt | `PrayerWidgetExt/` | `…WinTheDay.PrayerWidgetExt` | home/lock widgets + Live Activities |
| WinTheDayWatch | `WinTheDayWatch/` | `…WinTheDay.watchkitapp` | watchOS app |
| WatchWidgetExt | `WatchWidgetExt/` | `…watchkitapp.cx` | watch complications |

Xcode **file-system-synchronized groups**: any file dropped in a target's folder auto-joins that
target. **Exception:** `Shared/` files are added to targets manually in `project.pbxproj`.

App Groups: `group.com.suhail.WinTheDay` (app ↔ iOS widgets) and `group.com.suhail.WinTheDay.watch`
(watch app ↔ watch complications).

## Layers

```
Views (TodayView, PlanView, TrendsView, HealthView, SettingsView, editors…)
   │  @EnvironmentObject
   ▼
Managers (@MainActor ObservableObject, own UserDefaults)
   AppStore ........... the hub: data, scoring, trends, AI orchestration, snapshot
   HealthManager ...... HealthKit read/write, sleep detail, baselines
   PrayerManager ...... prayer times, qibla source, Ramadan, notifications
   HydrationManager ... water target + reminders
   FastingManager ..... fasting window + streak
   CalendarManager .... EventKit + Contacts (read/write calendar & reminders)
   WeatherManager ..... Open-Meteo forecast + outdoor advice
   StudyTimer ......... study/focus Live Activity timer
   │
   ▼
Services
   AIEstimator ........ provider routing + prompts + JSON parsing
   Keychain ........... API-key storage
   PhotoStore ......... progress photos in Documents/photos
   SharedStore ........ snapshot read/write to App Groups (Shared/)
   PhoneSync / WatchSync  WatchConnectivity bridge
```

All managers are constructed and injected in `WinTheDayApp.swift`.

## Data model (Models.swift)
- `AppData` — top-level document: `entries [date:Entry]`, `catalog`, `bodyComps`, `labs`, `habits`,
  `subjects`, `countdowns`, `routine`, `sessions`, `occasions`, `healthNotes`.
- `Entry` — one day: meals (+ `mealTimes`), `nn`/`habitState`, prayers, water, study, `workouts`,
  `logged` (quick-log items w/ `qty`), `sleep`/`readiness`/`sleepScore`, `status` (normal/sick/travel/rest),
  photos, AI result.
- Config: `AppSettings` (provider/model/keys flags, calendar/reminders sync), `Targets` (calorie/
  protein/steps/study + the personal "prize" metric), `ModulePrefs` (Today modules + order),
  `Personalization` (pillar names + module colors).

## Persistence
- `AppData` → JSON in `UserDefaults` key `suhail_health_v2`.
- Settings/targets/modules/personalization → their own keys; manager settings → their own keys.
- API keys → Keychain (per provider). Photos → `Documents/photos`. Auto-backup JSON → Documents +
  manual export/import. See [persistence](features/data-persistence.md).
- **Every persisted struct uses a tolerant `init(from:)`** so new fields never break old saves.
