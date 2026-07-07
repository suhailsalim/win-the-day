# PLAN: App Intents expansion — Siri/Shortcuts verbs + interactive widgets

## Goal
`AppIntentsSupport.swift` already gives App Intents persisted-data access that works while the app
is closed. Build the obvious verb set on top so the fastest log is voice or a widget tap:
"log a glass of water", "mark Dhuhr", "start a focus session", "how's my day going?",
"log weight 78.5". Then make the water and prayer widgets **interactive** (iOS 17 Button intents)
so logging happens without opening the app.

## Files to touch
- `WinTheDay/App/AppIntentsSupport.swift` — extend the existing lightweight store access; add intents.
- `PrayerWidgetExt/HomeWidgets.swift` — interactive buttons on water/prayer widgets.
- `WinTheDay/Core/AppStore.swift` — reload-from-disk hook so an intent's background write is visible
  when the app foregrounds.

## Steps, in order
1. Read `AppIntentsSupport.swift` end-to-end: how it loads/saves persisted data without AppStore,
   and which intents already exist. Extend that mechanism — do NOT import AppStore into intents.
2. Intents to add (all `AppIntent`, with `AppShortcutsProvider` phrases):
   - `LogWaterIntent(glasses: Int = 1)` — increments today's water; donates "Log water".
   - `MarkPrayerIntent(prayer: PrayerEnum)` — marks with the current timestamp so on-time banding
     still works (reuse the exact persistence shape the app writes; check how prayer marks are
     stored before writing).
   - `LogWeightIntent(kg: Double)` — sets today's weight.
   - `StartFocusIntent(minutes: Int = 45)` — opens the app into the focus screen (this one needs
     the app: `openAppWhenRun = true`).
   - `DayStatusIntent` — returns a spoken/dialog summary: score, habits left, next prayer, water.
     Read-only, works app-closed.
3. Widget interactivity: water widget gets a `Button(intent: LogWaterIntent())` "+1"; the
   prayer widget gets a mark button for the *current* pending prayer. After an intent mutates
   data, call `WidgetCenter.shared.reloadAllTimelines()` from the intent.
4. Foreground reconciliation: intents write to the same UserDefaults keys the app owns. On
   `scenePhase == .active`, AppStore must re-read the blob if a flag key (`intents_dirty_v1`)
   is set — find the existing foreground refresh path and hook there. Without this, opening the
   app after a Siri log shows stale data and the next in-app save **overwrites the intent's
   write**. This reconciliation is the heart of the plan; do it first, not last.
5. Build all targets, verify: run each shortcut from the Shortcuts app with Win the Day
   force-quit, then open the app and confirm the data is present and survives an in-app edit.

## Edge cases a weaker model would miss
- **Write-write race** in step 4 is the whole ballgame: AppStore caches `AppData` in memory and
  persists the cache. An intent write that lands while the app is suspended is silently lost on
  next in-app mutation unless the app re-reads first. Set the dirty flag in every mutating intent.
- Intents run in their own process — no `@MainActor` AppStore, no managers, no environment
  objects. Only the `AppIntentsSupport` persisted-data path.
- `MarkPrayerIntent` must record the mark **timestamp** in whatever structure PrayerClassifier
  reads; a bare bool would bypass on-time scoring (same trap as coach write tools).
- App Group vs standard UserDefaults: check which suite each key lives in before reading from the
  widget process — widgets can only see the App Group.
- Shortcut phrases must include the app name token (`\(.applicationName)`) or they won't register.

## Acceptance criteria
- [ ] "Hey Siri, log water in Win the Day" works with the app force-quit; reopening shows the
      glass, and logging another in-app keeps both.
- [ ] Widget +1 water button updates the widget within seconds, app closed.
- [ ] Marking a prayer via Siri produces the same on-time band as an in-app mark at that moment.
- [ ] DayStatus reads back a correct summary with the app closed.
- [ ] All targets build; no intent imports app-module-only types.
