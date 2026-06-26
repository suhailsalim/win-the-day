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
        publishSnapshot(entry)
        WidgetCenter.shared.reloadAllTimelines()
        return entry
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
        let e = DayStore.mutateToday { d in
            switch prayer {
            case .fajr: d.prayers.fajr = true; d.nn.fajr = true
            case .dhuhr: d.prayers.dhuhr = true
            case .asr: d.prayers.asr = true
            case .maghrib: d.prayers.maghrib = true
            case .isha: d.prayers.isha = true
            }
        }
        return .result(dialog: "Marked \(prayer.rawValue.capitalized). \(e.prayers.count) of 5 done today.")
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
    }
}
