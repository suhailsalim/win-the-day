import Foundation

/// Milestones — earned records of the long arc, computed from what already happened.
///
/// Deliberately **not** gamification pressure: nothing here is a goal you're nagged towards, there
/// are no expiring badges and no "you're about to lose it" prompts. A milestone is a receipt. That
/// ethos is why `AppData.earnedMilestones` is *persisted* rather than recomputed — deleting old
/// entries, or a half-finished import, must never revoke something you actually did.
///
/// Same shape as `ScoreEngine`/`RingEngine`: pure, Foundation-only, deterministic. The caller
/// (`AppStore`) does the aggregation and the persistence; this file only knows stats in → catalog out.

// MARK: - Persisted record

/// One earned milestone. `id` points at a `MilestoneDef` in the catalog; unknown ids (a milestone
/// removed in a later build) are simply ignored when rendering, never dropped from storage.
struct EarnedMilestone: Codable, Equatable, Identifiable, Sendable {
    var id: String = ""
    var earnedEpoch: Double = 0

    init(id: String, earnedEpoch: Double) {
        self.id = id
        self.earnedEpoch = earnedEpoch
    }

    /// Tolerant decoding (AGENTS.md convention 1).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        earnedEpoch = (try? c.decode(Double.self, forKey: .earnedEpoch)) ?? 0
    }

    var earnedDate: Date? { earnedEpoch > 0 ? Date(timeIntervalSince1970: earnedEpoch) : nil }
}

// MARK: - Catalog types

/// What a milestone counts. Adding a milestone that reuses one of these is a one-line catalog entry.
enum MilestoneMetric: String, CaseIterable, Sendable {
    case daysLogged, daysWon, longestStreak, perfectDays, longestPerfectRun
    case prayersOnTime, prayersMarked, workouts, waterGlasses, studyHours, photos, sleepNights
}

/// Purely presentational weight — early / consistent / rare. No points, no levels.
enum MilestoneTier: String, CaseIterable, Sendable {
    case early, steady, rare
    var label: String {
        switch self {
        case .early: return "Early"
        case .steady: return "Steady"
        case .rare: return "Rare"
        }
    }
    /// Tint for the badge (hex, so this file stays Foundation-only).
    var tintHex: UInt {
        switch self {
        case .early: return 0x6470A6     // Theme.accent
        case .steady: return 0x2FA36B    // Theme.sage
        case .rare: return 0x3B4A7C      // Theme.accentDark
        }
    }
}

struct MilestoneDef: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String       // what it took, e.g. "100 days logged"
    let line: String         // the calm one-liner shown when it lands
    let symbol: String       // SF Symbol
    let tier: MilestoneTier
    let metric: MilestoneMetric
    let threshold: Double
}

// MARK: - Engine

enum MilestoneEngine {

    /// Lifetime totals, aggregated once from every logged day. All `Double` so thresholds,
    /// progress bars and formatting share one representation.
    struct Stats: Equatable, Sendable {
        var daysLogged: Double = 0
        var daysWon: Double = 0
        var currentStreak: Double = 0
        var longestStreak: Double = 0
        var perfectDays: Double = 0          // every active habit satisfied
        var longestPerfectRun: Double = 0    // consecutive perfect days (7 = a perfect week)
        var prayersMarked: Double = 0
        var prayersOnTime: Double = 0        // prompt or on-time bands only
        var workouts: Double = 0
        var waterMl: Double = 0
        var studyHours: Double = 0
        var photos: Double = 0
        var sleepNights: Double = 0          // nights with a real sleep breakdown

        /// A "glass" is 250 ml — the same unit the hydration module talks in.
        var waterGlasses: Double { (waterMl / 250).rounded(.down) }

        func value(_ m: MilestoneMetric) -> Double {
            switch m {
            case .daysLogged: return daysLogged
            case .daysWon: return daysWon
            case .longestStreak: return longestStreak
            case .perfectDays: return perfectDays
            case .longestPerfectRun: return longestPerfectRun
            case .prayersOnTime: return prayersOnTime
            case .prayersMarked: return prayersMarked
            case .workouts: return workouts
            case .waterGlasses: return waterGlasses
            case .studyHours: return studyHours
            case .photos: return photos
            case .sleepNights: return sleepNights
            }
        }
    }

    /// One logged day as the streak rules see it — built by `AppStore` so the app's existing
    /// `dayWon` / `effectiveStatus` semantics stay the single source of truth.
    struct DayFact: Equatable, Sendable {
        var key: String          // yyyy-MM-dd
        var won: Bool
        var perfect: Bool
        var isProtected: Bool    // sick / travel / rest — pauses the chain without breaking it

        init(key: String, won: Bool, perfect: Bool = false, isProtected: Bool = false) {
            self.key = key; self.won = won; self.perfect = perfect; self.isProtected = isProtected
        }
    }

    // MARK: Catalog

    /// ~two dozen records across the app's surfaces. Ids are permanent — renaming one would
    /// orphan somebody's earned record, so add a new id instead of editing an old one.
    static let catalog: [MilestoneDef] = [
        // Showing up
        MilestoneDef(id: "days-7", title: "First week", detail: "7 days logged",
                     line: "A week of showing up. That\u{2019}s where it starts.",
                     symbol: "calendar", tier: .early, metric: .daysLogged, threshold: 7),
        MilestoneDef(id: "days-30", title: "A month in", detail: "30 days logged",
                     line: "Thirty days of paying attention.",
                     symbol: "calendar.badge.clock", tier: .early, metric: .daysLogged, threshold: 30),
        MilestoneDef(id: "days-100", title: "A hundred days", detail: "100 days logged",
                     line: "100 days logged. That\u{2019}s discipline.",
                     symbol: "checkmark.seal", tier: .steady, metric: .daysLogged, threshold: 100),
        MilestoneDef(id: "days-365", title: "A year of it", detail: "365 days logged",
                     line: "A full year on the record.",
                     symbol: "laurel.leading", tier: .rare, metric: .daysLogged, threshold: 365),

        // Days won
        MilestoneDef(id: "won-25", title: "Twenty-five wins", detail: "25 days won",
                     line: "Twenty-five days cleared the bar.",
                     symbol: "flag", tier: .early, metric: .daysWon, threshold: 25),
        MilestoneDef(id: "won-100", title: "A hundred wins", detail: "100 days won",
                     line: "A hundred days you did the work.",
                     symbol: "flag.checkered", tier: .steady, metric: .daysWon, threshold: 100),
        MilestoneDef(id: "won-300", title: "Three hundred wins", detail: "300 days won",
                     line: "Three hundred won days. Quietly enormous.",
                     symbol: "trophy", tier: .rare, metric: .daysWon, threshold: 300),

        // Streaks (rest / sick / travel days pause the chain, they don't break it)
        MilestoneDef(id: "streak-7", title: "Seven in a row", detail: "7-day streak",
                     line: "Seven days running. The chain is real.",
                     symbol: "flame", tier: .early, metric: .longestStreak, threshold: 7),
        MilestoneDef(id: "streak-30", title: "Thirty in a row", detail: "30-day streak",
                     line: "A month without dropping the chain.",
                     symbol: "flame.fill", tier: .steady, metric: .longestStreak, threshold: 30),
        MilestoneDef(id: "streak-100", title: "A hundred in a row", detail: "100-day streak",
                     line: "A hundred consecutive days. Very few get here.",
                     symbol: "medal", tier: .rare, metric: .longestStreak, threshold: 100),

        // Perfect days
        MilestoneDef(id: "perfect-1", title: "A perfect day", detail: "every habit, one day",
                     line: "Every single habit, done.",
                     symbol: "sparkles", tier: .early, metric: .perfectDays, threshold: 1),
        MilestoneDef(id: "perfect-week", title: "A perfect week", detail: "7 perfect days in a row",
                     line: "Seven perfect days back to back.",
                     symbol: "star.circle", tier: .rare, metric: .longestPerfectRun, threshold: 7),
        MilestoneDef(id: "perfect-25", title: "Twenty-five perfect days", detail: "25 perfect days",
                     line: "Twenty-five days with nothing left on the table.",
                     symbol: "star", tier: .steady, metric: .perfectDays, threshold: 25),

        // Faith
        MilestoneDef(id: "prayer-100", title: "A hundred on time", detail: "100 prayers on time",
                     line: "A hundred prayers inside their window.",
                     symbol: "moon.stars", tier: .steady, metric: .prayersOnTime, threshold: 100),
        MilestoneDef(id: "prayer-500", title: "Five hundred on time", detail: "500 prayers on time",
                     line: "Five hundred on time. Steady as anything.",
                     symbol: "moon.stars.fill", tier: .rare, metric: .prayersOnTime, threshold: 500),
        MilestoneDef(id: "prayer-marked-1000", title: "A thousand prayers", detail: "1,000 prayers marked",
                     line: "A thousand marked. That is a lot of turning up.",
                     symbol: "hands.and.sparkles", tier: .rare, metric: .prayersMarked, threshold: 1000),

        // Training
        MilestoneDef(id: "workouts-10", title: "Ten sessions", detail: "10 workouts logged",
                     line: "Ten sessions in the book.",
                     symbol: "figure.run", tier: .early, metric: .workouts, threshold: 10),
        MilestoneDef(id: "workouts-50", title: "Fifty sessions", detail: "50 workouts logged",
                     line: "Fifty workouts. The body knows.",
                     symbol: "dumbbell", tier: .steady, metric: .workouts, threshold: 50),
        MilestoneDef(id: "workouts-150", title: "A hundred and fifty sessions", detail: "150 workouts logged",
                     line: "150 sessions. This is who you are now.",
                     symbol: "dumbbell.fill", tier: .rare, metric: .workouts, threshold: 150),

        // Hydration
        MilestoneDef(id: "water-500", title: "Five hundred glasses", detail: "500 glasses of water",
                     line: "Five hundred glasses, one sip at a time.",
                     symbol: "drop", tier: .steady, metric: .waterGlasses, threshold: 500),
        MilestoneDef(id: "water-10000", title: "Ten thousand glasses", detail: "10,000 glasses of water",
                     line: "Ten thousand glasses. Genuinely absurd.",
                     symbol: "drop.fill", tier: .rare, metric: .waterGlasses, threshold: 10_000),

        // Focus / study
        MilestoneDef(id: "focus-50", title: "Fifty hours deep", detail: "50 focus hours",
                     line: "Fifty hours of real work.",
                     symbol: "book", tier: .early, metric: .studyHours, threshold: 50),
        MilestoneDef(id: "focus-250", title: "Two-fifty hours deep", detail: "250 focus hours",
                     line: "250 hours. Skills are built in units like this.",
                     symbol: "book.closed", tier: .steady, metric: .studyHours, threshold: 250),
        MilestoneDef(id: "focus-1000", title: "A thousand hours deep", detail: "1,000 focus hours",
                     line: "A thousand hours of focus.",
                     symbol: "graduationcap", tier: .rare, metric: .studyHours, threshold: 1000),

        // Sleep + photos
        MilestoneDef(id: "sleep-30", title: "A month of nights", detail: "30 nights of sleep data",
                     line: "Thirty nights measured — your baselines are yours now.",
                     symbol: "bed.double", tier: .steady, metric: .sleepNights, threshold: 30),
        MilestoneDef(id: "photos-25", title: "Twenty-five photos", detail: "25 progress photos",
                     line: "Twenty-five photos. Better proof than any scale.",
                     symbol: "camera", tier: .early, metric: .photos, threshold: 25)
    ]

    static func def(_ id: String) -> MilestoneDef? { catalog.first { $0.id == id } }

    // MARK: Evaluation (pure)

    /// Every milestone the stats currently satisfy, in catalog order. Deterministic: same stats in,
    /// same list out — which is what makes re-evaluating on every edit safe.
    static func evaluate(stats: Stats) -> [MilestoneDef] {
        catalog.filter { stats.value($0.metric) >= $0.threshold }
    }

    /// The subset of `evaluate` not already on record. Idempotent by construction: feed the result
    /// back in as `already` and the next call returns nothing.
    static func newlyEarned(stats: Stats, already: [EarnedMilestone]) -> [MilestoneDef] {
        let have = Set(already.map(\.id))
        return evaluate(stats: stats).filter { !have.contains($0.id) }
    }

    /// Progress towards a not-yet-earned milestone (for the Trends card). Never shown as pressure —
    /// it's context for what the next record happens to be.
    struct Progress: Identifiable, Equatable, Sendable {
        var def: MilestoneDef
        var current: Double
        var id: String { def.id }
        var fraction: Double { def.threshold > 0 ? min(1, max(0, current / def.threshold)) : 0 }
        var remaining: Double { max(0, def.threshold - current) }
    }

    /// The nearest unearned milestones — closest to done first.
    static func upcoming(stats: Stats, earned: [EarnedMilestone], limit: Int = 3) -> [Progress] {
        let have = Set(earned.map(\.id))
        return catalog
            .filter { !have.contains($0.id) && stats.value($0.metric) < $0.threshold }
            .map { Progress(def: $0, current: stats.value($0.metric)) }
            .sorted { ($0.fraction, -$0.def.threshold) > ($1.fraction, -$1.def.threshold) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Streak helpers (pure)

    /// Longest run of won days, mirroring `AppStore.streak()`: protected days (sick / travel / rest)
    /// are skipped without breaking or extending the chain, and a calendar day with no entry breaks it.
    static func longestStreak(_ days: [DayFact]) -> Int { longestRun(days) { $0.won } }

    /// Longest run of *perfect* days (every active habit satisfied) — 7 is a perfect week.
    static func longestPerfectRun(_ days: [DayFact]) -> Int { longestRun(days) { $0.perfect } }

    private static func longestRun(_ days: [DayFact], where pass: (DayFact) -> Bool) -> Int {
        var byIndex: [Int: DayFact] = [:]
        for d in days { if let i = dayIndex(d.key) { byIndex[i] = d } }
        guard let lo = byIndex.keys.min(), let hi = byIndex.keys.max() else { return 0 }
        var best = 0, run = 0
        for i in lo...hi {
            let day = byIndex[i]
            if day?.isProtected == true { continue }        // pause, don't break
            if let day, pass(day) { run += 1; best = max(best, run) } else { run = 0 }
        }
        return best
    }

    /// Days since 1970-01-01 for a `yyyy-MM-dd` key — pure integer arithmetic (days-from-civil), so
    /// no `Calendar`/`TimeZone` can shift a day boundary and silently split someone's streak.
    static func dayIndex(_ key: String) -> Int? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400                                   // [0, 399]
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1   // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy            // [0, 146096]
        return era * 146_097 + doe - 719_468
    }
}

/// What the celebration surface should show next: one record, or a single summary for a backfill.
/// (First launch after milestones ship can earn a dozen at once — that gets one calm sheet, not a
/// stack of them.)
enum MilestoneEvent: Identifiable, Equatable, Sendable {
    case earned(MilestoneDef)
    case batch(Int)

    var id: String {
        switch self {
        case .earned(let d): return d.id
        case .batch(let n): return "batch-\(n)"
        }
    }
}
