import Foundation
import WatchConnectivity
import WidgetKit

/// Watch side of sync: receives the snapshot from iPhone, sends actions back.
@MainActor
final class WatchSync: NSObject, ObservableObject {
    static let shared = WatchSync()
    @Published var snapshot = SharedSnapshot()
    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(action: String, amount: Int? = nil, name: String? = nil) {
        var info: [String: Any] = ["action": action]
        if let amount { info["amount"] = amount }
        if let name { info["name"] = name }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(info, replyHandler: nil) { _ in session.transferUserInfo(info) }
        } else {
            session.transferUserInfo(info)
        }
        // optimistic local update so the watch feels instant
        switch action {
        case "water": snapshot.waterMl += (amount ?? 250)
        case "prayer": snapshot.prayersDone = min(5, snapshot.prayersDone + 1)
        case "fast_start": snapshot.fastingActive = true; snapshot.fastStartEpoch = Date().timeIntervalSince1970
        case "fast_end": snapshot.fastingActive = false; snapshot.fastStartEpoch = 0
        case "workout_quick": snapshot.workoutsThisWeek += 1
        default: break
        }
    }

    private func apply(_ context: [String: Any]) {
        if let data = context["snapshot"] as? Data,
           let snap = try? JSONDecoder().decode(SharedSnapshot.self, from: data) {
            Task { @MainActor in
                self.snapshot = snap
                SharedStore.save(snap, suite: SharedStore.watchAppGroup)   // for complications
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let ctx = s.receivedApplicationContext
        Task { @MainActor in self.apply(ctx) }
    }
    nonisolated func session(_ s: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}
