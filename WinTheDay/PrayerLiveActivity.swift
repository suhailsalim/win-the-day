import Foundation
import ActivityKit

/// Starts/ends the prayer Live Activity. Works once the Widget Extension target (which declares the
/// matching ActivityConfiguration) is added — until then `Activity.request` simply throws and is ignored.
@MainActor
final class PrayerLiveActivityController {
    static let shared = PrayerLiveActivityController()
    private init() {}

    private let windowMinutes: Double = 20
    private var startedKey: String = ""    // prayer+time we already started, to avoid duplicates

    /// If we're within `windowMinutes` after an adhan, show a countdown Live Activity.
    func startIfWithinWindow(times: PrayerTimes) {
        let now = Date()
        // Find the most recent prayer whose adhan was within the window.
        let recent = times.ordered
            .filter { $0.0.isPrayer && $0.1 <= now && now.timeIntervalSince($0.1) <= windowMinutes * 60 }
            .max { $0.1 < $1.1 }
        guard let (name, start) = recent else { return }

        let key = "\(name.rawValue)-\(Int(start.timeIntervalSince1970))"
        guard key != startedKey else { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Don't stack duplicates.
        if !Activity<PrayerActivityAttributes>.activities.isEmpty { startedKey = key; return }

        let end = start.addingTimeInterval(windowMinutes * 60)
        let attributes = PrayerActivityAttributes(prayerName: name.label, startDate: start)
        let state = PrayerActivityAttributes.ContentState(endDate: end)
        let content = ActivityContent(state: state, staleDate: end)
        do {
            let activity = try Activity<PrayerActivityAttributes>.request(attributes: attributes, content: content)
            startedKey = key
            // Auto-end when the window closes.
            Task {
                let remaining = end.timeIntervalSinceNow
                if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                await activity.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate)
            }
        } catch {
            // No widget target yet, or activities disabled — silently ignore.
        }
    }
}
