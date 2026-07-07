# PLAN: Qur'an reading tracker (khatmah planner)

## Goal
The faith pillar tracks prayer and fasting but not the third daily practice: Qur'an reading. Add a
lightweight **reading tracker**: log today's reading (surah/page/juz'), a **khatmah planner**
("finish in 30 days → 20 pages/day", Ramadan preset: 1 juz'/day), a linkable habit, and an optional
custom ring. No Qur'an text is bundled — this tracks progress, it is not a mushaf app.

## Files to touch
- `WinTheDay/Core/Models.swift` — `Entry.quranPages: Int = 0` (+ tolerant decode);
  `AppData.khatmah: KhatmahPlan?` (`{startEpoch, targetDays, startPage, currentPage}`; tolerant).
- `WinTheDay/Engines/QuranProgress.swift` — NEW: static surah/juz'/page tables (604-page standard Madani
  layout: juz' boundaries by page are public factual data — hand-author the 30-entry table) + pure
  plan math.
- `WinTheDay/Today/TodayView.swift` — module `"quran"` (AGENTS.md convention 2: ModulePrefs var,
  defaultOrder, label/enabled/setEnabled, `moduleView` case, `moduleColor`, colorableModules).
- `WinTheDay/Today/RingEditorView.swift`/`RingEngine.swift` — `.quranPages` custom ring metric
  (pagesRead/dailyTarget).
- `WinTheDay/Today/HabitsEditorView.swift` context — new `HabitLinkType.quran` (auto-satisfied when
  daily target met) — follow how `studyHours` link type is implemented end to end.

## Steps, in order
1. Module UI: a compact card — today's pages stepper (+1/+5), current position ("Juz' 12 · p. 231"),
   plan progress bar, days remaining vs. pace ("on pace" / "3 pages behind"). Logging N pages
   advances `khatmah.currentPage` and sets `Entry.quranPages`.
2. Plan math (pure, in `QuranProgress`): `pagesPerDay = ceil(remainingPages / remainingDays)`,
   recomputed daily so missed days redistribute forward (never guilt about the past — the plan
   heals itself).
3. Khatmah setup sheet: target duration presets (30/60/90 days, "by end of Ramadan" when Ramadan
   mode knows the date), starting position (default: continue from `currentPage`).
4. Habit link + custom ring metric wiring (mirror `studyHours` in both registries).
5. EngineTests: plan math (redistribution, completion, day-0, past-target-date).
6. Build, verify, commit.

## Edge cases a weaker model would miss
- Editing a **past day's** pages must adjust `currentPage` by the delta, not re-add — store pages
  per-entry and derive `currentPage = startPage + Σ entries since startEpoch` instead of mutating
  a counter (single source of truth; the counter WILL drift otherwise).
- Completing a khatmah: celebrate once (ties into PLAN-milestones if shipped), archive the plan
  (`completedEpochs` list), offer restart — don't just freeze at 604.
- Reading beyond the daily target is normal (weekends); the ring caps at 100% but the plan math
  must credit the surplus.
- Juz'-based loggers vs page-based loggers both exist: the stepper logs pages, but show the juz'
  equivalent; a settings toggle for "log by juz'" just multiplies by ~20 — don't build two data
  models.
- No Qur'anic text, no translations bundled — zero licensing surface. Position labels only.

## Acceptance criteria
- [ ] 30-day khatmah started today shows 21 pages/day (ceil 604/30 = 21); missing two days
      raises the daily ask correctly.
- [ ] Logging on a past day keeps `currentPage` consistent (derived, verified by test).
- [ ] Habit auto-satisfies on target; custom ring fills proportionally.
- [ ] Module obeys all of convention 2 (reorderable, colorable, toggleable); old data loads.
- [ ] EngineTests green.
