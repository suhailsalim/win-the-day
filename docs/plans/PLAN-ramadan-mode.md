# PLAN: Ramadan mode

## Goal
The pieces exist separately — prayer times (which already yield Fajr/Maghrib), a fasting tracker,
`ramadan-` notification ids reserved, faith habits — but Ramadan is a month-long *mode*, not a
daily toggle. Ship: auto-detected Ramadan dates, suhoor/iftar countdowns driven by actual
Fajr/Maghrib, the fasting window auto-set from them, a taraweeh habit, and adjusted meal-time
expectations so Eating/Timing scores don't punish fasting.

## Files to touch
- `WinTheDay/Managers/RamadanManager.swift` — NEW manager (follow HydrationManager pattern: `@MainActor`
  ObservableObject, own `ramadan_*` keys, injected in `WinTheDayApp.swift`).
- `WinTheDay/Managers/FastingManager.swift` — accept an externally-set window.
- `WinTheDay/Today/TodayView.swift` — Ramadan module (countdown card).
- `WinTheDay/Core/Models.swift` — `ModulePrefs` new key `"ramadan"` (follow AGENTS.md convention 2
  exactly: var, defaultOrder, label/enabled/setEnabled switches) + settings fields.
- `WinTheDay/Engines/EatingScorer.swift` — timing sub-score Ramadan awareness.
- `Shared/SharedSnapshot.swift` + widgets — iftar countdown field (defaulted; snapshot pipeline
  per convention 4).

## Steps, in order
1. Hijri dates via `Calendar(identifier: .islamicUmmAlQura)` — detect month == 9. Offer a ±1 day
   manual adjustment setting (moon-sighting differences are real; default Umm al-Qura).
2. `RamadanManager`: `isRamadan`, `suhoorEnd` (= today's Fajr from PrayerManager), `iftar`
   (= Maghrib), day N of the month. Schedule `ramadan-` notifications: suhoor wake (configurable
   lead), iftar time, and optionally 10 min before iftar.
3. Auto-drive `FastingManager`: at Fajr start the fast, at Maghrib end it (only when Ramadan mode
   on and the user enables auto-fast; manual override always wins).
4. Today module: during Ramadan, a card with day N, countdown to iftar (or to suhoor end before
   Fajr), and the fast ring. Outside Ramadan the module hides itself even when enabled.
5. Scoring adjustments: when a day is Ramadan-fasting, the Eating Timing sub-score must judge
   dinner-to-bed from iftar reality, and the "protein by 18:00" style logic (if the smart-reminders
   plan shipped) shifts to post-iftar. Gate via a flag on the day, not wall-clock guesses.
6. Taraweeh: seed an optional manual habit (spirituality pillar) when Ramadan mode first activates,
   once — respect deletion (don't reseed every launch; persist a `ramadan_seeded_year` key).
7. Snapshot + widget: `iftarCountdownEpoch` defaulted field; render in the fasting widget slot.
8. Build strict (managers touched), verify against a known Ramadan date by temporarily overriding
   "today" in a debug hook, then commit.

## Edge cases a weaker model would miss
- **Umm al-Qura vs local sighting**: the ±adjustment setting is essential; a hardcoded calendar is
  wrong somewhere every year.
- Suhoor notification fires **before Fajr of day N**, i.e. it must schedule against tomorrow's
  Fajr each evening — off-by-one-day is the classic bug here.
- High latitude: Fajr/Maghrib can be nil (existing PrayerTimes behavior) — Ramadan mode must
  degrade to manual fast times, not crash.
- The Hijri day flips at sunset religiously but the app's day key is Gregorian — keep everything
  keyed to the app's `yyyy-MM-dd` convention and simply display "Ramadan day N"; do not attempt a
  sunset-keyed data model.
- Travelers/sick users don't fast: the auto-fast toggle must be per-day skippable (a "not fasting
  today" action) without disabling the whole mode.

## Acceptance criteria
- [ ] With the device date set inside Ramadan, the module appears with correct day N and a live
      iftar countdown that matches the prayer screen's Maghrib.
- [ ] Fast auto-starts/stops at Fajr/Maghrib when auto-fast is on; manual stop wins.
- [ ] Suhoor + iftar notifications fire (test with near-future times); ids all start `ramadan-`.
- [ ] Timing sub-score does not penalize a Ramadan-fasting day for a late dinner.
- [ ] Outside Ramadan the app is 100% unchanged; old data loads (tolerant decode on all new fields).
