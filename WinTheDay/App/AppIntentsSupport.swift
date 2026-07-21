import Foundation
import AppIntents
import WidgetKit

/// Lightweight persisted-data access used by App Intents (they may run while the app isn't open).
enum DayStore {
    static let dataKey = "suhail_health_v2"
    static let targetsKey = "targets_v1"

    static func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func loadData() -> AppData {
        guard let raw = UserDefaults.standard.data(forKey: dataKey),
              let d = try? JSONDecoder().decode(AppData.self, from: raw) else { return AppData() }
        return d
    }

    static func saveData(_ d: AppData) {
        if let raw = try? JSONEncoder().encode(d) { UserDefaults.standard.set(raw, forKey: dataKey) }
    }

    static func proteinTarget() -> Double {
        guard let raw = UserDefaults.standard.data(forKey: targetsKey),
              let t = try? JSONDecoder().decode(Targets.self, from: raw) else { return 120 }
        return t.protein
    }

    static func score(_ e: Entry) -> Int {
        var s = 0; let n = e.nn
        if n.fajr { s += 1 }
        if n.protein || (Double(e.proteinG) ?? 0) >= proteinTarget() { s += 1 }
        if n.moved { s += 1 }
        if n.phone { s += 1 }
        if n.side { s += 1 }
        return s
    }

    @discardableResult
    static func mutateToday(_ change: (inout Entry) -> Void) -> Entry {
        var data = loadData()
        let key = todayString()
        var entry = data.entries[key] ?? Entry(date: key)
        change(&entry)
        if entry.isMeaningful { data.entries[key] = entry } else { data.entries.removeValue(forKey: key) }
        saveData(data)
        markDirty()
        publishSnapshot(entry)
        WidgetCenter.shared.reloadAllTimelines()
        return entry
    }

    // MARK: - Foreground reconciliation + intent-only helpers

    /// Raised by every mutating intent. An intent can write this blob while the app is suspended;
    /// `AppStore.reconcileIntentWrites()` re-reads from disk on the next foreground so the app's
    /// stale in-memory `AppData` can't silently overwrite the intent's write on the next edit.
    /// It lives in the App Group (not `.standard`) so the widget process can raise it too.
    static let dirtyKey = "intents_dirty_v1"
    /// Set by `StartFocusIntent`; consumed once by `AppStore.reconcileIntentWrites()`.
    static let openFocusKey = "intent_open_focus_v1"

    static func markDirty() {
        UserDefaults(suiteName: SharedStore.appGroup)?.set(true, forKey: dirtyKey)
    }

    /// Today's prayer times + tomorrow's Fajr, recomputed from what `PrayerManager` persisted.
    /// Intents get no managers, so this mirrors its inputs (same UserDefaults keys, same asr
    /// shadow factor) rather than importing it. `nil` = no coordinates cached yet.
    static func prayerContext() -> (today: PrayerTimes, nextFajr: Date?)? {
        let d = UserDefaults.standard
        guard let lat = d.object(forKey: "prayer_lat") as? Double,
              let lon = d.object(forKey: "prayer_lon") as? Double else { return nil }
        let branch = d.string(forKey: "prayer_branch") ?? "sunni"
        let madhab = d.string(forKey: "prayer_madhab")
            ?? ((d.object(forKey: "prayer_hanafi") as? Bool ?? true) ? "hanafi" : "shafi")
        let method: CalcMethod = branch == "shia"
            ? .jafari
            : (CalcMethod.all.first { $0.name == (d.string(forKey: "prayer_method") ?? "") } ?? .mwl)
        let asrFactor: Double = (branch == "sunni" && madhab == "hanafi") ? 2 : 1
        let tz = TimeZone.current
        let today = PrayerTimes.calculate(date: Date(), latitude: lat, longitude: lon, timeZone: tz,
                                          fajrAngle: method.fajrAngle, ishaAngle: method.ishaAngle,
                                          asrFactor: asrFactor)
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let nextFajr = PrayerTimes.calculate(date: tomorrowDate, latitude: lat, longitude: lon, timeZone: tz,
                                             fajrAngle: method.fajrAngle, ishaAngle: method.ishaAngle,
                                             asrFactor: asrFactor)[.fajr]
        return (today, nextFajr)
    }

    /// "Maghrib at 8:41 pm" for the spoken day summary, or nil without coordinates.
    static func nextPrayerText() -> String? {
        guard let ctx = prayerContext() else { return nil }
        let now = Date()
        guard let next = ctx.today.ordered.first(where: { $0.0.isPrayer && $0.1 > now }) else {
            guard let fajr = ctx.nextFajr else { return nil }
            return "Fajr at \(timeText(fajr))"
        }
        return "\(next.0.label) at \(timeText(next.1))"
    }

    private static func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    private static func publishSnapshot(_ e: Entry) {
        var s = SharedStore.load()
        s.score = score(e); s.nnDone = s.score
        s.prayersDone = e.prayers.count
        s.waterMl = e.waterMl
        s.caloriesText = e.calories.isEmpty ? "—" : e.calories
        s.proteinText = e.proteinG.isEmpty ? "—" : e.proteinG
        SharedStore.save(s)
    }
}

// MARK: - Intents

enum PrayerChoice: String, AppEnum {
    case fajr, dhuhr, asr, maghrib, isha
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Prayer" }
    static var caseDisplayRepresentations: [PrayerChoice: DisplayRepresentation] {
        [.fajr: "Fajr", .dhuhr: "Dhuhr", .asr: "Asr", .maghrib: "Maghrib", .isha: "Isha"]
    }
}

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Add water to today's hydration.")

    @Parameter(title: "Amount (ml)", default: 250)
    var amount: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let e = DayStore.mutateToday { $0.waterMl = max(0, $0.waterMl + amount) }
        return .result(dialog: "Added \(amount) ml. You're at \(e.waterMl) ml today.")
    }
}

struct MarkPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Prayer Prayed"
    static var description = IntentDescription("Mark one of the five daily prayers as prayed.")

    @Parameter(title: "Prayer")
    var prayer: PrayerChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Record the mark with its timestamp *and* its band, exactly like an in-app tap: a bare
        // bool would land as `.unknown` (5/10) and quietly cost the prayer ring its on-time credit.
        let now = Date()
        let name = PrayerTimes.Name(rawValue: prayer.rawValue) ?? .fajr
        let band: PrayerBand = DayStore.prayerContext().map {
            PrayerClassifier.classify(name, markedAt: now, today: $0.today, nextFajr: $0.nextFajr)
        } ?? .unknown
        let e = DayStore.mutateToday { d in
            d.prayers.setOn(prayer.rawValue, true, at: now.timeIntervalSince1970, band: band)
            if prayer == .fajr { d.nn.fajr = true }
        }
        return .result(dialog: "Marked \(name.label) — \(band.label.lowercased()). \(e.prayers.count) of 5 done today.")
    }
}

struct TodayScoreIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's Score"
    static var description = IntentDescription("Check how many non-negotiables you've hit today.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = DayStore.loadData()
        let e = data.entries[DayStore.todayString()] ?? Entry(date: DayStore.todayString())
        return .result(dialog: "You're at \(DayStore.score(e)) out of 5 today.")
    }
}

struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Weight"
    static var description = IntentDescription("Record today's weight in kilograms.")

    // No default on purpose: Siri should ask rather than silently log a made-up number.
    @Parameter(title: "Weight (kg)")
    var kg: Double

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let value = min(400, max(1, kg))
        let text = String(format: "%.1f", value)
        DayStore.mutateToday { d in
            d.weight = text
            d.weightFromHealth = false   // a spoken log is a manual log, not a smart-scale sample
        }
        return .result(dialog: "Logged \(text) kg for today.")
    }
}

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Focus Session"
    static var description = IntentDescription("Open Win the Day on the focus screen, ready for a block.")
    /// The focus screen is a full-screen UI on a live timer — this one genuinely needs the app.
    static var openAppWhenRun = true

    @Parameter(title: "Minutes", default: 45)
    var minutes: Int

    func perform() async throws -> some IntentResult {
        let m = min(180, max(5, minutes))
        UserDefaults.standard.set(m, forKey: "focus_duration_min")   // FocusScreenView's @AppStorage
        UserDefaults.standard.set(true, forKey: DayStore.openFocusKey)
        return .result()
    }
}

struct DayStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "How's My Day Going"
    static var description = IntentDescription("A spoken summary: score, prayers, water and your next prayer.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let key = DayStore.todayString()
        let e = DayStore.loadData().entries[key] ?? Entry(date: key)
        let s = DayStore.score(e)
        var parts = ["you're at \(s) of 5"]
        if s < 5 { parts.append("\(5 - s) to go") }
        parts.append("\(e.prayers.count) of 5 prayers")
        parts.append(String(format: "%.1f litres of water", Double(e.waterMl) / 1000))
        if let next = DayStore.nextPrayerText() { parts.append("next up \(next)") }
        return .result(dialog: "Today: \(parts.joined(separator: ", ")).")
    }
}

struct WinTheDayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: [
            "Log water in \(.applicationName)",
            "Add a glass of water in \(.applicationName)"
        ], shortTitle: "Log Water", systemImageName: "drop.fill")
        AppShortcut(intent: MarkPrayerIntent(), phrases: [
            "Mark a prayer in \(.applicationName)",
            "Log a prayer in \(.applicationName)"
        ], shortTitle: "Mark Prayer", systemImageName: "moon.stars.fill")
        AppShortcut(intent: TodayScoreIntent(), phrases: [
            "What's my \(.applicationName) score",
            "Today's score in \(.applicationName)"
        ], shortTitle: "Today's Score", systemImageName: "checkmark.seal.fill")
        AppShortcut(intent: LogWeightIntent(), phrases: [
            "Log my weight in \(.applicationName)",
            "Record my weight in \(.applicationName)"
        ], shortTitle: "Log Weight", systemImageName: "scalemass.fill")
        AppShortcut(intent: StartFocusIntent(), phrases: [
            "Start a focus session in \(.applicationName)",
            "Focus in \(.applicationName)"
        ], shortTitle: "Start Focus", systemImageName: "scope")
        AppShortcut(intent: DayStatusIntent(), phrases: [
            "How's my day going in \(.applicationName)",
            "Day status in \(.applicationName)"
        ], shortTitle: "Day Status", systemImageName: "sun.max.fill")
    }
}
