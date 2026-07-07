# PLAN: Milestones & earned achievements (non-gimmick gamification)

## Goal
The app has streaks and "day won" but nothing that celebrates the long arc. Add a deterministic,
local **achievements system** aligned with the app's non-shaming ethos: milestones are *earned
records*, never dark-pattern pressure. Examples: 7/30/100-day streaks, first perfect week, 100
prayers on time, 50 workouts, 10k glasses of water, first month of complete sleep baselines,
"Ramadan completed". Plus a lifetime stats sheet ("since you started: N days logged, …").

## Files to touch
- `WinTheDay/Engines/Milestones.swift` — NEW: `MilestoneDef` catalog (static) + pure
  `MilestoneEngine.evaluate(stats:) -> [EarnedMilestone]`.
- `WinTheDay/Core/Models.swift` — `AppData.earnedMilestones: [EarnedMilestone] = []`
  (`{id, earnedEpoch}`; tolerant decode line).
- `WinTheDay/Core/AppStore.swift` — `lifetimeStats()` aggregation + evaluate-on-mutation (debounced,
  compare against already-earned to find new ones) + a `@Published var justEarned: MilestoneDef?`.
- `WinTheDay/Trends/TrendsView.swift` — "Milestones" card (earned grid + lifetime stats + next-up
  progress).
- `WinTheDay/Today/TodayView.swift` — one-time celebration banner/sheet when `justEarned` fires.

## Steps, in order
1. `lifetimeStats()`: single pass over `data.entries` producing counts (days logged, days won,
   longest streak, prayers by band, workouts, water glasses, study hours, photos). Cache per
   launch; entries are already in memory.
2. Catalog ~20 milestones as data (`id`, title, subtitle, SF Symbol, tier, `threshold`,
   `metric` keypath into the stats struct) — adding future milestones must be a one-line catalog
   entry, not code.
3. Engine: `evaluate` returns every milestone whose threshold the stats meet. AppStore diffs
   against `earnedMilestones`, appends new ones with today's epoch, sets `justEarned` (one at a
   time; queue if multiple land together).
4. UI: celebration is a small confetti-free sheet (house style — calm, serif, "100 days logged.
   That's discipline.") with a share button (renders the milestone card as an image via
   `ImageRenderer`). Trends card shows earned + the nearest 3 unearned with progress bars.
5. Unit-test the engine in EngineTests (stats in → milestones out; idempotence: re-evaluating
   never duplicates).
6. Build, verify by lowering one threshold in debug, commit.

## Edge cases a weaker model would miss
- **Retroactive earning:** first launch after this ships must grant historical milestones in one
  batch WITHOUT 15 celebration sheets — show a single "You've already earned N milestones" summary
  when the diff exceeds 2.
- Earned milestones are permanent: deleting old entries (or a failed import) must never revoke
  them — that's why `earnedMilestones` is persisted rather than recomputed.
- Streak milestones must respect the existing rest/sick/travel streak-protection semantics — reuse
  the app's streak function, don't reimplement.
- Time zones: use the app's existing `yyyy-MM-dd` day keys for all counting; no Date arithmetic.
- Keep it out of the day score: milestones observe, they must not feed back into scoring.

## Acceptance criteria
- [ ] Crossing a threshold live (e.g. logging the 7th consecutive win) triggers exactly one
      celebration; relaunching does not repeat it.
- [ ] Historical data grants a batch summary, not sheet spam.
- [ ] Trends shows earned milestones + progress toward the next three.
- [ ] EngineTests cover evaluate + idempotence + streak-protection interplay.
- [ ] Old saves load; milestone data survives round-trip.
