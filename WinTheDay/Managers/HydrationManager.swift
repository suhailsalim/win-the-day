import Foundation
@preconcurrency import UserNotifications
import WidgetKit

/// Hydration target + configurable reminder notifications.
@MainActor
final class HydrationManager: ObservableObject {
    @Published var targetMl: Int { didSet { persist() } }
    @Published var glassMl: Int { didSet { persist() } }
    @Published var remindersOn: Bool { didSet { persist(); reschedule() } }
    @Published var intervalHours: Int { didSet { persist(); reschedule() } }
    @Published var startHour: Int { didSet { persist(); reschedule() } }
    @Published var endHour: Int { didSet { persist(); reschedule() } }

    private let d = UserDefaults.standard
    private let notePrefix = "hydration-"

    init() {
        targetMl = d.object(forKey: "hyd_target") as? Int ?? 3000
        glassMl = d.object(forKey: "hyd_glass") as? Int ?? 250
        remindersOn = d.object(forKey: "hyd_on") as? Bool ?? true
        intervalHours = d.object(forKey: "hyd_interval") as? Int ?? 2
        startHour = d.object(forKey: "hyd_start") as? Int ?? 8
        endHour = d.object(forKey: "hyd_end") as? Int ?? 22
    }

    private func persist() {
        d.set(targetMl, forKey: "hyd_target")
        d.set(glassMl, forKey: "hyd_glass")
        d.set(remindersOn, forKey: "hyd_on")
        d.set(intervalHours, forKey: "hyd_interval")
        d.set(startHour, forKey: "hyd_start")
        d.set(endHour, forKey: "hyd_end")
        var s = SharedStore.load()
        s.waterTarget = targetMl
        SharedStore.save(s)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func start() {
        guard remindersOn else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            reschedule()
        }
    }

    func reschedule() {
        let center = UNUserNotificationCenter.current()
        let prefix = notePrefix
        let on = remindersOn, interval = intervalHours, startH = startHour, endH = endHour
        center.getPendingNotificationRequests { reqs in
            let ours = reqs.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            guard on, interval > 0 else { return }
            var hour = startH
            while hour <= endH {
                var comps = DateComponents(); comps.hour = hour; comps.minute = 0
                let content = UNMutableNotificationContent()
                content.title = "Hydrate 💧"
                content.body = "Time for some water — keep the bottle moving."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                center.add(UNNotificationRequest(identifier: "\(prefix)\(hour)", content: content, trigger: trigger))
                hour += interval
            }
        }
    }
}
