import Foundation
import AppIntents
import WidgetKit
import SwiftUI

/// Intents behind the interactive widget buttons (iOS 17 `Button(intent:)`).
///
/// A widget button's intent runs in the widget extension's process, which can only see the App
/// Group. The app's real day blob (`suhail_health_v2`) lives in the *app's* own
/// `UserDefaults.standard` and is invisible from here, so a tap can't write the entry directly.
/// Instead each tap does two things:
///   1. appends a tiny action record to a queue in the App Group, and
///   2. optimistically nudges the shared snapshot so the widget redraws within a second.
/// `AppStore.reconcileIntentWrites()` drains the queue into the real entry on the next foreground.
///
/// The queue is deliberately plain JSON (`[[String: Any]]`) instead of a shared Swift type: the app
/// side reads the same key with `JSONSerialization`, so nothing has to be added to `Shared/` (and
/// no `project.pbxproj` membership to keep in sync across four targets).
enum WidgetActionQueue {
    /// Both keys are mirrored in `AppStore.reconcileIntentWrites()` / `DayStore.dirtyKey`.
    static let dirtyKey = "intents_dirty_v1"
    static let queueKey = "widget_actions_v1"
    private static let maxQueued = 100

    static func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Append one action. Each record carries its own day + epoch, so a tap that the app only
    /// drains tomorrow still lands on the day it was actually made.
    static func append(_ action: [String: Any]) {
        guard let d = UserDefaults(suiteName: SharedStore.appGroup) else { return }
        var queued: [[String: Any]] = []
        if let raw = d.data(forKey: queueKey),
           let arr = (try? JSONSerialization.jsonObject(with: raw)) as? [[String: Any]] {
            queued = arr
        }
        queued.append(action)
        if queued.count > maxQueued { queued.removeFirst(queued.count - maxQueued) }
        if let raw = try? JSONSerialization.data(withJSONObject: queued) { d.set(raw, forKey: queueKey) }
        d.set(true, forKey: dirtyKey)
    }
}

/// The prayer that's currently *due* is the one before the snapshot's next prayer in the daily
/// cycle — after Isha the snapshot wraps to tomorrow's Fajr, so "due" wraps back to Isha.
let widgetPrayerCycle = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

func duePrayer(_ snap: SharedSnapshot) -> (key: String, label: String)? {
    guard let i = widgetPrayerCycle.firstIndex(of: snap.nextPrayerName) else { return nil }
    let label = widgetPrayerCycle[(i + widgetPrayerCycle.count - 1) % widgetPrayerCycle.count]
    return (label.lowercased(), label)
}

/// One glass of water from the hydration widget. Fixed at 250 ml — the user's glass size lives in
/// the app's own defaults and isn't part of the App-Group snapshot.
struct LogWaterFromWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Glass of Water"
    static var description = IntentDescription("Add 250 ml from the hydration widget.")
    /// Widget-button plumbing — the Shortcuts-facing verb is `LogWaterIntent` in the app.
    static var isDiscoverable = false

    static let glassMl = 250

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetActionQueue.append([
            "kind": "water",
            "ml": Self.glassMl,
            "day": WidgetActionQueue.todayString(),
            "epoch": Date().timeIntervalSince1970
        ])
        var s = SharedStore.load()
        s.waterMl = max(0, s.waterMl + Self.glassMl)
        SharedStore.save(s)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Mark the currently-due prayer from the next-prayer widget. The band is left to the app: only it
/// has the coordinates and calculation method needed to classify prompt / on-time / later, and it
/// classifies against the epoch recorded here, not against drain time.
struct MarkPrayerFromWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Prayer From Widget"
    static var description = IntentDescription("Mark the prayer that's currently due.")
    static var isDiscoverable = false

    @Parameter(title: "Prayer")
    var prayer: String

    init() { self.prayer = "" }
    init(prayer: String) { self.prayer = prayer }

    func perform() async throws -> some IntentResult {
        guard widgetPrayerCycle.contains(where: { $0.lowercased() == prayer }) else { return .result() }
        WidgetActionQueue.append([
            "kind": "prayer",
            "name": prayer,
            "day": WidgetActionQueue.todayString(),
            "epoch": Date().timeIntervalSince1970
        ])
        var s = SharedStore.load()
        s.prayersDone = min(5, s.prayersDone + 1)
        SharedStore.save(s)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Buttons

/// The two interactive controls live here rather than in `HomeWidgets.swift` so the `import
/// AppIntents` that `Button(intent:)` needs stays with the intents it drives.

struct WaterGlassButton: View {
    var tint: Color

    var body: some View {
        Button(intent: LogWaterFromWidgetIntent()) {
            Label("\(LogWaterFromWidgetIntent.glassMl) ml", systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }
}

struct MarkPrayerButton: View {
    let due: (key: String, label: String)
    var tint: Color

    var body: some View {
        Button(intent: MarkPrayerFromWidgetIntent(prayer: due.key)) {
            Label("Mark \(due.label)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }
}
