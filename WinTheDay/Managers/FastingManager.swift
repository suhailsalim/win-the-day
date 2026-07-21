import Foundation
import WidgetKit

/// Intermittent-fasting window tracker. Owns its own UserDefaults (mirrors HydrationManager).
@MainActor
final class FastingManager: ObservableObject {
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "fast_on"); publishSnapshot() } }
    @Published var protocolName: String { didSet { d.set(protocolName, forKey: "fast_protocol"); applyProtocol() } }
    @Published var targetHours: Double { didSet { d.set(targetHours, forKey: "fast_target"); publishSnapshot() } }
    /// Epoch of the currently-running fast, or 0 when not fasting.
    @Published var fastStartEpoch: Double { didSet { d.set(fastStartEpoch, forKey: "fast_start"); publishSnapshot() } }

    private let d = UserDefaults.standard
    private let historyKey = "fast_history"   // [yyyy-MM-dd: completed hours]

    /// Preset windows → fasting hours.
    static let protocols: [(id: String, label: String, hours: Double)] = [
        ("14:10", "14:10", 14), ("16:8", "16:8", 16), ("18:6", "18:6", 18),
        ("20:4", "20:4", 20), ("omad", "OMAD", 23), ("custom", "Custom", 16)
    ]

    init() {
        enabled = d.object(forKey: "fast_on") as? Bool ?? false
        protocolName = d.string(forKey: "fast_protocol") ?? "16:8"
        targetHours = d.object(forKey: "fast_target") as? Double ?? 16
        fastStartEpoch = d.object(forKey: "fast_start") as? Double ?? 0
    }

    private func applyProtocol() {
        if let p = Self.protocols.first(where: { $0.id == protocolName }), p.id != "custom" {
            targetHours = p.hours
        }
    }

    /// Write fasting state into both app groups so widgets & complications can render it.
    func publishSnapshot() {
        for suite in [SharedStore.appGroup, SharedStore.watchAppGroup] {
            var s = SharedStore.load(suite: suite)
            s.fastingActive = enabled && fastStartEpoch > 0
            s.fastStartEpoch = fastStartEpoch
            s.fastTargetHours = targetHours
            SharedStore.save(s, suite: suite)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Active fast

    var isFasting: Bool { fastStartEpoch > 0 }
    var fastStart: Date? { fastStartEpoch > 0 ? Date(timeIntervalSince1970: fastStartEpoch) : nil }

    /// Hours elapsed in the active fast (0 when idle).
    func elapsedHours(now: Date = Date()) -> Double {
        guard let start = fastStart else { return 0 }
        return max(0, now.timeIntervalSince(start) / 3600)
    }

    /// 0…1 progress toward the target window.
    func progress(now: Date = Date()) -> Double {
        guard targetHours > 0 else { return 0 }
        return min(1, elapsedHours(now: now) / targetHours)
    }

    func startFast() { fastStartEpoch = Date().timeIntervalSince1970 }

    /// End the active fast; record the day's completed hours for the streak.
    func endFast() {
        guard let start = fastStart else { return }
        let hours = max(0, Date().timeIntervalSince(start) / 3600)
        recordCompletion(hours: hours, on: start)
        fastStartEpoch = 0
    }

    // MARK: - Externally-set window (Ramadan mode)

    /// Start a fast that began at a known moment rather than "now" — Ramadan's auto-fast opens the
    /// window at the computed Fajr, which may already be hours in the past when the app is opened.
    /// Never moves a fast that is already running (a manual start outranks the automation).
    func startFast(at date: Date) {
        guard fastStartEpoch == 0 else { return }
        fastStartEpoch = date.timeIntervalSince1970
    }

    /// End the active fast at a known moment (Ramadan's Maghrib) so the recorded hours are the
    /// window that was actually fasted, not "however long until the app was next opened".
    func endFast(at date: Date) {
        guard let start = fastStart else { return }
        let hours = max(0, date.timeIntervalSince(start) / 3600)
        recordCompletion(hours: hours, on: start)
        fastStartEpoch = 0
    }

    // MARK: - History & streak

    private func history() -> [String: Double] {
        (d.dictionary(forKey: historyKey) as? [String: Double]) ?? [:]
    }

    private func recordCompletion(hours: Double, on date: Date) {
        var h = history()
        let key = Self.dateString(date)
        h[key] = max(h[key] ?? 0, hours)   // keep the longest fast that started that day
        d.set(h, forKey: historyKey)
    }

    /// Consecutive days (ending today or yesterday) that met the target window.
    func streak() -> Int {
        let h = history()
        let cal = Calendar.current
        var day = Date()
        // Allow today to still be in progress: start counting from yesterday if today not yet recorded.
        if h[Self.dateString(day)] == nil { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        for _ in 0..<400 {
            let key = Self.dateString(day)
            if let hrs = h[key], hrs >= targetHours - 0.25 { count += 1 }
            else { break }
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
