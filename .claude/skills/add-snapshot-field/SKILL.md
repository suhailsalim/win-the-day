---
name: add-snapshot-field
description: Surface a new value in widgets, watch app, or complications via SharedSnapshot — the App-Group data pipeline. Use when a widget/watch/complication needs data it doesn't have.
---

# Add a widget/watch data field

Data flows app → `SharedSnapshot` (App Groups `group.com.suhail.WinTheDay` + `…watch`) → widget.
Widgets never import app code; they render only snapshot scalars.

## Procedure
1. **`Shared/SharedSnapshot.swift`**: add a **defaulted** property (tolerant by construction —
   old widget binaries and old snapshots keep working). Keep it scalar/short: the snapshot shares
   the ~1MB UserDefaults budget. Strings ≤ ~24 chars, arrays capped (rings ≤ 4).
2. **Write it** in the owning `publishSnapshot()`:
   - App state → `AppStore.publishSnapshot()`
   - Prayer → `PrayerManager` · Fasting → `FastingManager` · Weather → `WeatherManager`
   Each writes to **both** app groups.
3. **Read it** in the consumer: `PrayerWidgetExt/HomeWidgets.swift` (home/lock),
   `WatchWidgetExt/WatchComplications.swift` (complications), watch app views.
4. Refresh: confirm `WidgetCenter.shared.reloadAllTimelines()` runs after the publish path.

## Target-membership rules (the classic trap)
- New files in `WinTheDay/`, `PrayerWidgetExt/`, `WinTheDayWatch/`, `WatchWidgetExt/`
  **auto-join** their target (filesystem-synchronized groups). ✅
- New files in **`Shared/`** must be added to EVERY consuming target by hand in
  `project.pbxproj` (mirror `SharedSnapshot.swift`'s PBXBuildFile entries). Prefer extending
  SharedSnapshot.swift over creating new Shared files.
- Widget code keeps its own local colors/hex helpers — never import `Theme` or app models.

## Verify
- Build the full scheme (widgets compile as part of it).
- On device: change the value in-app, background, check the widget updates.
- Old-snapshot tolerance: the widget renders sensibly when the field is absent (fresh default).
