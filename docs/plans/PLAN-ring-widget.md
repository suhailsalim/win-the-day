# PLAN: Home-screen ring-strip widget + tip (consume the snapshot data the app already publishes)

## Goal
`AppStore.publishSnapshot()` already writes the ring row and the top tip into the App-Group
snapshot ([AppStore.swift:595–600](WinTheDay/Core/AppStore.swift): `s.rings = visibleRings.map…`,
`s.topTip = …`), and `SharedSnapshot`/`SnapshotRing` define the payload
([SharedSnapshot.swift:3–7,55](Shared/SharedSnapshot.swift) — the comment literally says
"for a future" widget). No widget renders any of it. Ship the M9 ring-strip widget: a systemMedium
home-screen widget showing up to 4 score rings + the rotating tip, and a systemSmall single-ring
variant, plus a watch corner complication for Readiness.

## Files to touch
- `PrayerWidgetExt/HomeWidgets.swift` — new widget views + timeline (reuse the existing
  `SnapshotProvider` in this file).
- `PrayerWidgetExt/PrayerWidgetBundle.swift` — register the new widget(s).
- `WatchWidgetExt/WatchComplications.swift` — readiness ring complication (there is already a
  "Score ring — circular & corner" section at line 28 to mirror).
- `WinTheDay/Core/AppStore.swift` — only if verification shows `WidgetCenter.shared.reloadAllTimelines()`
  isn't called after `publishSnapshot()`; check first.

## Steps, in order
1. **Read first:** all of `HomeWidgets.swift` (note: it deliberately keeps local color definitions
   so the widget doesn't depend on the app module — follow that), `SharedSnapshot.swift` (exact
   `SnapshotRing` fields: `title`, `pct`?, `display`, `colorHex` — read the struct, don't guess),
   and how `SnapshotProvider` loads the snapshot from the App Group.
2. **RingStripWidget (systemMedium).** New `Widget` in HomeWidgets.swift:
   - HStack of up to 4 rings from `snapshot.rings` (already capped ≤4 by the app). Each ring:
     `Circle().trim(to: pct)` stroke over a track circle, `display` text centered, `title` caption
     below (font ~10, lineLimit 1). Color: `Color(hex: colorHex)` if nonzero via a LOCAL hex
     initializer in this file (copy the pattern the file already uses — do not import app code);
     else band color by pct (<0.34 coral, <0.67 amber, else sage — use the file's local palette).
   - Below the rings: `snapshot.topTip` in a single 2-line caption, only if non-empty.
   - Empty state: `rings.isEmpty` → "Open Win the Day to set up rings" placeholder text.
3. **Single-ring widget (systemSmall).** Same ring view at large size showing `rings.first`
   (that's the user's #1 ring by their own ordering). Reuse the ring subview — write it once.
4. Register both in `PrayerWidgetBundle.swift` (mirror existing entries). Add
   `.containerBackground(for: .widget)` handling exactly as the existing widgets do (iOS 17 API).
5. **Watch complication.** In `WatchComplications.swift`, extend the existing score-ring section
   with an `accessoryCircular` readiness/first-ring gauge (`Gauge` with `.gaugeStyle(
   .accessoryCircularCapacity)`), reading the same snapshot fields the watch snapshot already
   carries — verify the watch App-Group snapshot includes rings; if it does NOT (watch uses
   `group.…watch`), fall back to the `readiness` scalar that is already in the snapshot and keep
   scope to a readiness complication only.
6. **Refresh path.** Verify the app calls `WidgetCenter.shared.reloadAllTimelines()` (or targeted
   `reloadTimelines(ofKind:)`) after `publishSnapshot()` — grep `WidgetCenter` in the app. If
   missing, add one call at the end of `publishSnapshot()` (it's cheap and debounced by the system).
   Widget timeline: a single entry `.after(now + 30min)` policy is fine — the data only changes
   when the app writes it and reloads.
7. **Build all targets** (the widget extension builds as part of the app scheme):
   standard AGENTS.md device build command. Then install on device, add the widget from the
   gallery, log something that moves a ring (e.g. water), reopen home screen → ring moved.
8. Commit: `feat: home-screen ring-strip + single-ring widgets, readiness complication`.

## Edge cases a weaker model would miss
- **Widget target membership:** new code goes INSIDE existing files of `PrayerWidgetExt/` /
  `WatchWidgetExt/`, which auto-join their targets. If you create a NEW file under `Shared/`, you
  must hand-edit `project.pbxproj` for every target (AGENTS.md convention 4) — avoid by not
  creating shared files; everything you need is already in `SharedSnapshot`.
- **No app-module imports in the extension.** `Theme`, `RingDef`, `RingEngine` are app-target-only.
  The widget renders purely from `SnapshotRing` scalars. If you're tempted to import something,
  you're doing it wrong.
- **`colorHex == 0` means "no custom color"** (band coloring applies), not black. Check how
  `publishSnapshot` populates it before rendering.
- **Old snapshots:** a user who hasn't opened the app since the update has a snapshot whose
  `rings` decodes as `[]` (tolerant default). The empty state in step 2 covers this — don't crash
  or show 0% rings.
- **`display` strings are pre-truncated (≤24 chars) by the app** — still set `lineLimit(1)` +
  `minimumScaleFactor(0.6)` because "calibrating" style strings can appear.
- **Unavailable rings:** the app may publish a ring with a "—" display / zero pct for
  no-data days; render the track grey with the display text rather than a 0% colored arc if the
  snapshot distinguishes it (check whether `SnapshotRing` has an `available`-like field; if it
  only has pct/display, grey the arc when `display == "—"`).
- **Free signing:** App Groups work; nothing here needs iCloud/WeatherKit. Watch wireless install
  is flaky (error 4000) — reinstall from the iPhone Watch app rather than debugging "the code".
- Widget gallery caches previews; if the new widget doesn't appear, reboot the device or
  re-install — not a code bug.

## Acceptance criteria
- [ ] Widget gallery offers "Rings" in small + medium; medium shows up to 4 rings matching the
      app's Today ring row order, values, and colors, plus the current tip.
- [ ] Logging water (or any ring input) in the app and returning to the home screen updates the
      ring within a system refresh (immediately if reloadTimelines was wired).
- [ ] Fresh-install state (before first app launch of the new snapshot) shows the placeholder,
      not a crash or 0% arcs.
- [ ] Watch shows a readiness circular complication with the current value.
- [ ] Full scheme build green; existing prayer/lock widgets unchanged and still render.
