import Foundation

/// How a ring's fraction reads at a glance — drives the arc color when no custom color is set,
/// and the caption text, so a bright custom color never contradicts what the ring is actually saying.
enum RingBand { case low, mid, high }

/// The rendered state of one ring for one day — never persisted, recomputed on demand.
struct RingResult {
    var fraction: Double        // 0...1, clamped
    var displayValue: String    // big number in the ring
    var caption: String         // small text under the ring / in the detail sheet
    var band: RingBand
    var available: Bool         // false → render a dim placeholder instead of a misleading 0
    var factors: [ReadinessFactor] = []
}

/// Computes `RingResult`s from a `RingDef` + the day's `Entry` + local app context. Pure & deterministic —
/// no I/O. Built-ins delegate to ScoreEngine (Sleep/Readiness/Active) or PrayerClassifier (Prayers);
/// `.custom` rings read straight off the entry/targets via `Context`.
enum RingEngine {
    /// Everything a ring might need beyond the day's `Entry` itself — built once per render by the caller
    /// (AppStore has the targets/hydration-target; the view supplies today's prayer times).
    struct Context {
        var waterTargetMl: Double = 3000
        var studyGoalHours: Double = 4
        var proteinTargetG: Double = 120
        var quranDailyTarget: Double = 0    // today's khatmah ask in pages (0 = no active plan)
        var stepsTarget: Double = 8000
        var calorieTarget: Double = 2000
        var habitsDone: Int = 0             // satisfied non-negotiables today (AppStore precomputes)
        var habitsTotal: Int = 0            // 0 = no habits configured → ring shows unavailable
        var prayerTimes: PrayerTimes?
        var nextFajr: Date?
    }

    static func compute(_ def: RingDef, entry: Entry, ctx: Context) -> RingResult {
        switch def.source {
        case .sleep:
            return scoreResult(entry.sleepScore, available: entry.sleep != nil, goal: def.goal, caption: "Sleep")
        case .readiness:
            return scoreResult(entry.readiness, available: entry.sleep != nil, goal: def.goal, caption: "Readiness")
        case .active:
            return scoreResult(entry.activeScore ?? 0, available: entry.activeScore != nil, goal: def.goal, caption: "Active")
        case .eating:
            return scoreResult(entry.eatingScore ?? 0, available: entry.eatingScore != nil, goal: def.goal, caption: "Eating")
        case .prayer:
            return prayerResult(entry: entry, ctx: ctx)
        case .custom:
            return customResult(def, entry: entry, ctx: ctx)
        }
    }

    private static func band(_ frac: Double) -> RingBand { frac < 0.34 ? .low : (frac < 0.67 ? .mid : .high) }

    private static func scoreResult(_ raw: Int, available: Bool, goal: Double, caption: String) -> RingResult {
        guard available else { return RingResult(fraction: 0, displayValue: "—", caption: "No data yet", band: .mid, available: false) }
        let frac = goal > 0 ? min(1, max(0, Double(raw) / goal)) : 0
        return RingResult(fraction: frac, displayValue: "\(raw)", caption: caption, band: band(frac), available: true)
    }

    private static func prayerResult(entry: Entry, ctx: Context) -> RingResult {
        guard let times = ctx.prayerTimes else {
            return RingResult(fraction: 0, displayValue: "—", caption: "No prayer times yet", band: .mid, available: false)
        }
        let (points, outOf) = PrayerClassifier.dayScore(prayers: entry.prayers, today: times, nextFajr: ctx.nextFajr)
        guard outOf > 0 else {
            return RingResult(fraction: 0, displayValue: "—", caption: "None due yet", band: .mid, available: false)
        }
        let frac = Double(points) / Double(outOf)
        return RingResult(fraction: frac, displayValue: String(format: "%.1f", Double(points) / 10),
                          caption: "\(entry.prayers.count)/5 marked", band: band(frac), available: true)
    }

    private static func customResult(_ def: RingDef, entry: Entry, ctx: Context) -> RingResult {
        switch def.metric {
        case .hydrationPct:
            let target = ctx.waterTargetMl > 0 ? ctx.waterTargetMl : 3000
            let frac = min(1, max(0, Double(entry.waterMl) / target))
            return RingResult(fraction: frac, displayValue: "\(entry.waterMl)", caption: "of \(Int(target))ml", band: band(frac), available: true)
        case .studyGoalPct:
            let goal = ctx.studyGoalHours > 0 ? ctx.studyGoalHours : 4
            let frac = min(1, max(0, entry.studyHours / goal))
            return RingResult(fraction: frac, displayValue: String(format: "%.1f", entry.studyHours),
                              caption: String(format: "of %.1fh", goal), band: band(frac), available: true)
        case .proteinPct:
            let target = ctx.proteinTargetG > 0 ? ctx.proteinTargetG : 120
            let logged = Double(entry.proteinG) ?? 0
            let frac = min(1, max(0, logged / target))
            return RingResult(fraction: frac, displayValue: "\(Int(logged))", caption: "of \(Int(target))g", band: band(frac), available: true)
        case .quranPages:
            // Target comes from the active khatmah (it moves as the plan redistributes), with a
            // one-juz'-a-day fallback when no plan is running. Surplus reading caps the ring at
            // 100% but is still credited to the plan itself.
            let target = ctx.quranDailyTarget > 0 ? ctx.quranDailyTarget : Double(QuranProgress.pagesInOneJuz)
            let frac = min(1, max(0, Double(entry.quranPages) / target))
            return RingResult(fraction: frac, displayValue: "\(entry.quranPages)",
                              caption: "of \(Int(target)) pages", band: band(frac), available: true)
        case .stepsPct:
            let target = ctx.stepsTarget > 0 ? ctx.stepsTarget : 8000
            let steps = Double(entry.steps) ?? 0
            guard steps > 0 else {
                return RingResult(fraction: 0, displayValue: "—", caption: "No steps yet", band: .mid, available: false)
            }
            let frac = min(1, max(0, steps / target))
            let display = steps >= 10000 ? String(format: "%.1fk", steps / 1000) : "\(Int(steps))"
            return RingResult(fraction: frac, displayValue: display,
                              caption: "of \(Int(target)) steps", band: band(frac), available: true)
        case .caloriesPct:
            // Budget semantics: full ring = budget used up; staying under keeps the band healthy,
            // blowing past the budget flags low — the one custom ring where more isn't better.
            let target = ctx.calorieTarget > 0 ? ctx.calorieTarget : 2000
            let kcal = Double(entry.calories) ?? 0
            guard kcal > 0 else {
                return RingResult(fraction: 0, displayValue: "—", caption: "Nothing logged yet", band: .mid, available: false)
            }
            let frac = min(1, max(0, kcal / target))
            let over = kcal > target * 1.05
            return RingResult(fraction: frac, displayValue: "\(Int(kcal))",
                              caption: over ? "over \(Int(target)) kcal" : "of \(Int(target)) kcal",
                              band: over ? .low : .high, available: true)
        case .habitsPct:
            guard ctx.habitsTotal > 0 else {
                return RingResult(fraction: 0, displayValue: "—", caption: "No habits set up", band: .mid, available: false)
            }
            let frac = min(1, max(0, Double(ctx.habitsDone) / Double(ctx.habitsTotal)))
            return RingResult(fraction: frac, displayValue: "\(ctx.habitsDone)",
                              caption: "of \(ctx.habitsTotal) done", band: band(frac), available: true)
        case .unknown:
            return RingResult(fraction: 0, displayValue: "—", caption: "Not configured", band: .mid, available: false)
        }
    }
}
