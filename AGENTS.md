# AGENTS.md — Working on Win the Day

Single source of truth for AI agents and contributors. Read this first; it exists so you **don't
re-derive the project from scratch each session** (token optimization). Deep dives live in [`docs/`](docs/).

## What this is

**Win the Day** is a native **SwiftUI iOS 17+** personal health & discipline tracker (meals, habits,
faith, study/work, fasting, sleep/readiness, planning). Built with Xcode 26. **Local-only**: no
backend, no accounts. Data is JSON in `UserDefaults`; API keys live in the **Keychain**; widgets/watch
read a shared snapshot via **App Groups**.

It ships **4 targets** (see [docs/architecture.md](docs/architecture.md)):

| Target | Folder | Notes |
|---|---|---|
| `WinTheDay` (app) | `WinTheDay/` | the iOS app |
| `PrayerWidgetExt` | `PrayerWidgetExt/` | home + lock widgets, Live Activities |
| `WinTheDayWatch` | `WinTheDayWatch/` | watchOS app |
| `WatchWidgetExt` | `WatchWidgetExt/` | watch complications |

Shared types are in `Shared/` (members of multiple targets).

## Build / run / install

`xcode-select` points at CommandLineTools, so **always pass `DEVELOPER_DIR`** explicitly:

```bash
# Build for a real device
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project WinTheDay.xcodeproj -scheme WinTheDay -configuration Debug \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -derivedDataPath build/dd build

# Install on a connected iPhone (find the id with: xcrun devicectl list devices)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun devicectl device install app --device <DEVICE_ID> \
  build/dd/Build/Products/Debug-iphoneos/WinTheDay.app
```

- **Strict concurrency is `complete`** (Xcode 26 default). Build green under it. Common fix: in
  `UNUserNotificationCenter`/`CLLocationManager`/escaping closures, **snapshot `@MainActor` state into
  locals before the closure**; mark pure helpers `nonisolated`; `@preconcurrency import UserNotifications`.
- A plain `xcodebuild ... build` (Swift 5 mode) can pass while Xcode (Swift 6) fails — verify with
  `SWIFT_STRICT_CONCURRENCY=complete` when touching managers.
- Free Apple signing: **App Groups work**, but **iCloud/CloudKit and WeatherKit do NOT** (paid-only).
  Weather uses Open-Meteo (no key). Watch wireless installs are flaky (error 4000) — reinstall from
  the iPhone Watch app.

## Conventions — follow these exactly

1. **Tolerant Codable (the data-loss fix).** Every persisted struct (`Entry`, `AppData`,
   `AppSettings`, `ModulePrefs`, …) has a hand-written `init(from:)` using
   `(try? c.decode(...)) ?? default`. **When you add a stored field, add a tolerant decode line for
   it.** Never rely on synthesized Codable for persisted models — a missing key would wipe user data.

2. **Add a Today module** (`ModulePrefs` in `Models.swift`): add the `var`, add the key to
   `defaultOrder`, and the `label`/`enabled`/`setEnabled` switches; render it in
   `TodayView.moduleView(_:)`; give it a color in `AppStore.moduleColor(_:)` and add the key to
   `SettingsView.colorableModules`.

3. **Managers** are `@MainActor final class … : ObservableObject`, own their `UserDefaults` keys, and
   are injected in `WinTheDayApp.swift` via `@StateObject` → `.environmentObject`. Pattern examples:
   `HydrationManager`, `FastingManager`, `PrayerManager`, `CalendarManager`, `WeatherManager`.

4. **Widgets/watch data** flows through `Shared/SharedSnapshot.swift` (`SharedStore`, app groups
   `group.com.suhail.WinTheDay` + `…watch`). To surface a new value: add a defaulted field to
   `SharedSnapshot`, write it in the relevant `publishSnapshot()` (AppStore / PrayerManager /
   FastingManager / WeatherManager), then read it in the widget/complication. **New files in `Shared/`
   must be added to each target manually in `project.pbxproj`** (mirror `SharedSnapshot.swift`'s
   `PBXBuildFile` entries). New files in `WinTheDay/`, `PrayerWidgetExt/`, `WinTheDayWatch/`,
   `WatchWidgetExt/` **auto-join** their target (file-system-synchronized groups).

5. **AI** goes through `AIEstimator.swift` (`complete`/`suggest`/`chat` + `parseObject`/`sliceJSON`
   for structured JSON). Providers: Anthropic, OpenAI, Gemini, OpenRouter, DeepSeek, Ollama (local),
   Ollama Cloud, Apple. Keys are per-provider in the **Keychain** — never hardcode or log them.

6. **Notifications** use one id-prefix per concern: `prayer-`, `ramadan-`, `hydration-`, `session-`,
   `weekly-review`. Reuse the prefix to clear/reschedule.

7. **Secrets / privacy.** No keys in the repo. Don't commit `build/`, `.wolf/`, or personal data.
   The user's health notes/labs are sent to the selected AI provider by design (the UI says so).

## Where things live

`WinTheDay/` is organized into feature folders (all auto-join the target — filesystem-synchronized
groups include subfolders; new files go in the matching folder):

| Folder | Contents |
|---|---|
| `App/` | `WinTheDayApp` (entry + DI), `RootView` (tab bar), `OnboardingView`, `AppIntentsSupport`, `PhoneSync` |
| `Core/` | `Models.swift` (all data models + `ModulePrefs`), `AppStore.swift` (the `@MainActor` hub), `Keychain`, `PhotoStore` |
| `Engines/` | Pure Foundation-only enums: `ScoreEngine`, `EatingScorer`, `ReadinessScorer`, `RingEngine`, `PrayerClassifier`, `SleepPlanner`, `PrayerTimes` |
| `Managers/` | `@MainActor ObservableObject` services: Health, Hydration, Fasting, Prayer, Calendar, Weather, StudyTimer |
| `AI/` | `AIEstimator` (provider routing + prompts), `AppleIntelligence`, `CoachTools` |
| `Food/` | Food DB + lookup chain, `FoodDB.json`, food log/catalog views, barcode, meal-time sheet |
| `Today/` `Plan/` `Health/` `Trends/` `Coach/` `Faith/` `Study/` `Settings/` | One folder per feature surface/tab |
| `UI/` | Shared components (`Components`, `Theme`, `ImagePicker`), `Fonts/` |

`Assets.xcassets` and `WinTheDay.entitlements` stay at `WinTheDay/` root (the entitlements path is
referenced in build settings — do not move it). High-traffic files: `Core/Models.swift`,
`Core/AppStore.swift`, `AI/AIEstimator.swift`, `Managers/HealthManager.swift`, `Today/TodayView.swift`.

Plans live in `docs/plans/`; project skills in `.claude/skills/`; user docs in `docs/guide/`
(MkDocs, `mkdocs.yml` at root).

## Verify before you're done

1. Build green (device destination; add `SWIFT_STRICT_CONCURRENCY=complete` if you touched a manager).
2. Install on device; sanity-check the touched screen.
3. Confirm prior data still loads (tolerant decoding) — open the app, check past entries.
4. `cd EngineTests && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   (pure-engine + codable-tolerance suite — a missing tolerant decode line fails the round-trip tests).

## Feature docs

See [`docs/`](docs/): [architecture](docs/architecture.md) ·
[logging & meals](docs/features/logging-and-meals.md) ·
[habits & scoring](docs/features/habits-scoring.md) ·
[sleep & readiness](docs/features/sleep-readiness.md) ·
[faith](docs/features/faith.md) · [planning](docs/features/planning.md) ·
[coach & AI](docs/features/coach-ai.md) · [health data](docs/features/health-data.md) ·
[widgets & watch](docs/features/widgets-watch.md) · [persistence](docs/features/data-persistence.md).
