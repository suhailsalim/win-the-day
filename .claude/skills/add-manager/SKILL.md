---
name: add-manager
description: Create a new manager (ObservableObject service like HydrationManager/FastingManager) following the house pattern. Use when a feature needs its own lifecycle, persistence keys, or notifications.
---

# Add a manager

Pattern examples to copy: `HydrationManager` (simplest), `FastingManager`, `PrayerManager`,
`CalendarManager`, `WeatherManager`.

## The shape
```swift
@MainActor
final class ThingManager: ObservableObject {
    @Published var stateA: ...        // UI-facing state
    // Owns its OWN UserDefaults keys, prefix "thing_" — NOT inside AppSettings
    // (keeps AppSettings' Codable migration surface small).
    private func persist() { ... }    // read/write its keys directly
}
```

## Wiring
1. New file in `WinTheDay/` (auto-joins the target).
2. `WinTheDayApp.swift`: `@StateObject private var thing = ThingManager()` →
   `.environmentObject(thing)` on the root.
3. Views: `@EnvironmentObject var thing: ThingManager`.
4. Notifications: pick ONE id prefix per concern (existing: `prayer-`, `ramadan-`, `hydration-`,
   `session-`, `weekly-review`). Always clear-by-prefix before rescheduling.
5. Widget data: if widgets need its state, the manager writes `SharedSnapshot` fields itself
   (see add-snapshot-field skill).

## Strict concurrency (managers are the hot zone)
- Build with `SWIFT_STRICT_CONCURRENCY=complete` (see build skill) — mandatory for manager PRs.
- `UNUserNotificationCenter` / `CLLocationManager` / HK continuation closures: snapshot
  `@MainActor` state into `let` locals BEFORE the closure; hop back via `Task { @MainActor in }`.
- Pure helpers → `nonisolated static func`.

## Persistence
Manager settings/state use their own keys with primitive/JSON encoding and tolerant decoding
(defaults on missing). Never store manager state inside `AppData` unless it's per-day (then it
belongs on `Entry` — see add-persisted-field skill).
