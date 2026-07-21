import Foundation

/// One nudge the engine decided today deserves: when it fires and exactly what it says.
/// `rule` doubles as the id stem, so a day can never hold two of the same nudge.
struct PlannedReminder: Equatable, Sendable, Identifiable {
    var rule: String            // "streak" | "dinner" | "bedtime" | "protein"
    var fireDate: Date
    var title: String
    var body: String

    var id: String { rule }

    /// `smart-streak-2026-07-07` — the `smart-` prefix is what the scheduler clears before re-adding
    /// (AGENTS.md convention 6, one prefix per concern) and the date makes a request left over from
    /// yesterday impossible to mistake for today's.
    func identifier(dayKey: String) -> String { ReminderEngine.idPrefix + rule + "-" + dayKey }
}

/// Decides which of a handful of *deterministic* nudges tonight's data earns — no AI, no network,
/// no persistence. Callers gather a value `State` (AppStore) and hand the result to
/// `UNUserNotificationCenter`. Pure & testable, same shape as `ScoreEngine`/`SleepPlanner`.
///
/// All the user-facing copy lives here on purpose: the app's voice is "within reach", never
/// "you failed", and keeping every string in one file makes that easy to keep honest.
enum ReminderEngine {

    /// Shared id prefix for everything this engine schedules.
    static let idPrefix = "smart-"

    /// A day's state, flattened to values. Defaults are the "nothing known" case, which produces
    /// no reminders at all.
    struct State: Equatable {
        var now = Date()
        var dayKey = ""                    // yyyy-MM-dd of `now`, for the request ids

        // Settings (AppSettings.smart*)
        var enabled = true
        var streakRule = true
        var dinnerRule = true
        var bedtimeRule = true
        var proteinRule = true
        var eveningHour = 20               // when the streak nudge fires

        // The day
        var dayStatus = "normal"           // normal | rest | sick | travel
        var habitsTotal = 0
        var habitsDone = 0
        var dinnerLogged = false
        var dinnerCutoffEpoch: Double = 0  // SleepPlanner.Plan.dinnerCutoffEpoch (0 = no plan yet)
        var recommendedBedEpoch: Double = 0
        var proteinG: Double = 0
        var proteinTargetG: Double = 0
    }

    /// Fixed hour for the protein check — late enough that lunch is in, early enough to act on.
    static let proteinHour = 18

    /// At most one reminder per rule, soonest first, all of them strictly in the future and tonight.
    static func plan(_ s: State) -> [PlannedReminder] {
        guard s.enabled else { return [] }
        let candidates = [streak(s), dinner(s), bedtime(s), protein(s)].compactMap { $0 }
        let cutoff = horizon(after: s.now)
        return candidates
            .filter { $0.fireDate > s.now && $0.fireDate <= cutoff }
            .sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Rules (each returns at most one reminder)

    /// The day hasn't cleared the bar and there's still real evening left. Protected days
    /// (rest/sick/travel) pause expectations, so they never get this one.
    private static func streak(_ s: State) -> PlannedReminder? {
        guard s.streakRule, s.habitsTotal > 0, !DayStatus.isProtected(s.dayStatus) else { return nil }
        let pending = max(0, s.habitsTotal - s.habitsDone)
        guard pending >= 2 else { return nil }
        guard Double(s.habitsDone) / Double(s.habitsTotal) < 0.6 else { return nil }   // already won
        guard let fire = clockTime(hour: s.eveningHour, on: s.now) else { return nil }
        let body = pending <= 3
            ? "\(pending) quick habits left — plenty of evening to take the day."
            : "\(pending) habits left. Pick the two easiest and the day still counts."
        return PlannedReminder(rule: "streak", fireDate: fire,
                               title: "Your streak\u{2019}s within reach", body: body)
    }

    /// Half an hour before tonight's dinner cutoff, and only while dinner is still unlogged —
    /// logging it before then simply removes the reminder on the next recompute.
    private static func dinner(_ s: State) -> PlannedReminder? {
        guard s.dinnerRule, !s.dinnerLogged, s.dinnerCutoffEpoch > 0 else { return nil }
        let cutoff = Date(timeIntervalSince1970: s.dinnerCutoffEpoch)
        return PlannedReminder(rule: "dinner", fireDate: cutoff.addingTimeInterval(-30 * 60),
                               title: "Dinner window",
                               body: "Eating by \(clock(cutoff)) leaves tonight\u{2019}s sleep plan a clean run.")
    }

    /// Half an hour before the recommended bed time from `SleepPlanner`.
    private static func bedtime(_ s: State) -> PlannedReminder? {
        guard s.bedtimeRule, s.recommendedBedEpoch > 0 else { return nil }
        let bed = Date(timeIntervalSince1970: s.recommendedBedEpoch)
        return PlannedReminder(rule: "bedtime", fireDate: bed.addingTimeInterval(-30 * 60),
                               title: "Wind down",
                               body: "Lights out around \(clock(bed)) covers tonight\u{2019}s sleep need.")
    }

    /// Still under 70% of the protein target with a meal or two left in the day.
    private static func protein(_ s: State) -> PlannedReminder? {
        guard s.proteinRule, s.proteinTargetG > 0 else { return nil }
        guard s.proteinG < 0.7 * s.proteinTargetG else { return nil }
        guard let fire = clockTime(hour: proteinHour, on: s.now) else { return nil }
        let gap = Int((s.proteinTargetG - s.proteinG).rounded())
        return PlannedReminder(rule: "protein", fireDate: fire,
                               title: "Protein check",
                               body: "\(gap)g to go — one solid meal covers most of that.")
    }

    // MARK: - Time helpers

    /// Today's `hour`:00 in the user's calendar.
    private static func clockTime(hour: Int, on day: Date) -> Date? {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        comps.hour = min(23, max(0, hour))
        comps.minute = 0
        return Calendar.current.date(from: comps)
    }

    /// Reminders belong to *tonight*. The window closes at 4am so a recommended bedtime just past
    /// midnight still gets its nudge, while anything further out is left to the next recompute —
    /// which clears the whole `smart-` prefix first, so nothing stale ever survives a day rollover.
    private static func horizon(after now: Date) -> Date {
        let start = Calendar.current.startOfDay(for: now)
        return start.addingTimeInterval(28 * 3600)
    }

    private static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}
