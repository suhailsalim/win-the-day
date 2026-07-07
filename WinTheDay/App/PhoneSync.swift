import Foundation
import WatchConnectivity

/// iPhone side of Watch sync: pushes the snapshot to the watch and applies actions sent back.
@MainActor
final class PhoneSync: NSObject, ObservableObject {
    static let shared = PhoneSync()
    var onAction: ((_ action: String, _ amount: Int?, _ name: String?) -> Void)?
    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendSnapshot() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if let data = try? JSONEncoder().encode(SharedStore.load()) {
            try? session.updateApplicationContext(["snapshot": data])
        }
    }
}

extension PhoneSync: WCSessionDelegate {
    nonisolated func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.sendSnapshot() }
    }
    nonisolated func sessionDidBecomeInactive(_ s: WCSession) {}
    nonisolated func sessionDidDeactivate(_ s: WCSession) { s.activate() }

    nonisolated func session(_ s: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let action = userInfo["action"] as? String
        let amount = userInfo["amount"] as? Int
        let name = userInfo["name"] as? String
        Task { @MainActor in
            if let action { self.onAction?(action, amount, name); self.sendSnapshot() }
        }
    }
    nonisolated func session(_ s: WCSession, didReceiveMessage message: [String: Any]) {
        self.session(s, didReceiveUserInfo: message)
    }
}
