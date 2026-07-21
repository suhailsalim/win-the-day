import Foundation
import LocalAuthentication

/// Optional Face ID / Touch ID gate over the whole app, plus the privacy cover the app switcher
/// screenshots. Local-only: nothing leaves the device, the lock is purely a UI shield over
/// `RootView` (widgets, the watch app and notifications are governed by iOS, not by this).
@MainActor
final class AppLock: ObservableObject {
    /// The user must authenticate before content is shown again.
    @Published private(set) var locked = false
    /// Redaction cover for the app switcher — set on `.inactive`, cleared on `.active`.
    @Published private(set) var covered = false
    /// An authentication sheet is on screen (suppresses the retry button).
    @Published private(set) var authenticating = false
    /// Why the last attempt failed, shown on the lock screen.
    @Published private(set) var failureNote = ""
    /// Set when the device can no longer authenticate (passcode switched off) — we degrade to
    /// unlocked-with-a-banner instead of locking the user out of their own data forever.
    @Published private(set) var unavailableNote = ""

    /// Cover the UI whenever we're locked or merely inactive.
    var shielded: Bool { locked || covered }

    private let d = UserDefaults.standard
    /// Mirror of `AppSettings.appLockEnabled`, so a cold launch can lock before `AppStore` has
    /// decoded its JSON. `AppSettings` stays the source of truth; `syncEnabled` keeps this in step.
    private let enabledKey = "applock_enabled"
    private var backgroundedAt: Date?
    private var promptedThisForeground = false

    init() {
        locked = d.object(forKey: enabledKey) as? Bool ?? false
    }

    // MARK: - Lifecycle

    /// Called once at launch with the real setting: reconciles the launch mirror and prompts if
    /// we came up locked.
    func start(enabled: Bool) {
        syncEnabled(enabled)
        if locked { promptOnce() }
    }

    /// Keep the launch mirror in step with the persisted setting (and unlock when switched off).
    func syncEnabled(_ enabled: Bool) {
        d.set(enabled, forKey: enabledKey)
        if !enabled {
            locked = false; covered = false; backgroundedAt = nil
            failureNote = ""; unavailableNote = ""
        }
    }

    /// `.inactive` — Control Center pulls and permission dialogs fire this too, so the cover blinks;
    /// that's the price of having the app-switcher thumbnail redacted, and it's what every banking
    /// app does. Don't paper over it with delays.
    func willResignActive(enabled: Bool) {
        covered = enabled
    }

    /// `.background` — start the grace clock.
    func didEnterBackground(enabled: Bool) {
        guard enabled else { return }
        covered = true
        backgroundedAt = Date()
    }

    /// `.active` — re-arm the lock if we were away longer than the grace period.
    func didBecomeActive(enabled: Bool, graceMinutes: Int) {
        covered = false
        promptedThisForeground = false
        guard enabled else {
            locked = false; backgroundedAt = nil; unavailableNote = ""
            return
        }
        // Passcode turned off since the toggle was flipped: degrade rather than lock out.
        if let why = AppLock.unavailableReason() {
            unavailableNote = why
            locked = false; backgroundedAt = nil
            return
        }
        unavailableNote = ""
        if let since = backgroundedAt {
            // Clamp negative deltas (wall-clock/timezone changes) to "expired" so travelling can
            // never silently extend the unlocked window.
            let away = Date().timeIntervalSince(since)
            if away < 0 || away > Double(max(0, graceMinutes)) * 60 { locked = true }
            backgroundedAt = nil
        }
        if locked { promptOnce() }
    }

    // MARK: - Authentication

    /// Auto-prompt at most once per foreground — otherwise a cancelled sheet re-presents forever.
    /// Every retry after that comes from the lock screen's button.
    private func promptOnce() {
        guard !promptedThisForeground else { return }
        promptedThisForeground = true
        unlock()
    }

    /// Run the biometric/passcode prompt and drop the shield on success. A failure or cancel keeps
    /// the cover up — we never fall through to content.
    func unlock() {
        guard locked, !authenticating else { return }
        authenticating = true
        Task {
            let failure = await authenticate(reason: "Unlock Win the Day")
            authenticating = false
            if let failure {
                failureNote = failure
            } else {
                failureNote = ""
                locked = false
                covered = false
            }
        }
    }

    /// One `deviceOwnerAuthentication` evaluation — that policy already falls back to the device
    /// passcode, so never use `.deviceOwnerAuthenticationWithBiometrics` here. Returns `nil` on
    /// success, otherwise a message to show the user.
    func authenticate(reason: String) async -> String? {
        if let why = AppLock.unavailableReason() { return why }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, error in
                cont.resume(returning: ok ? nil : AppLock.message(for: error))
            }
        }
    }

    /// `nil` when the device can authenticate; otherwise why it can't (usually: no passcode set).
    nonisolated static func unavailableReason() -> String? {
        var err: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) { return nil }
        if let code = err?.code, LAError.Code(rawValue: code) == .passcodeNotSet {
            return "App lock needs a device passcode. Turn one on in iOS Settings → Face ID & Passcode."
        }
        return err?.localizedDescription ?? "This device can't verify it's you."
    }

    /// Label for the toggle and the unlock button ("Face ID" / "Touch ID" / "Passcode").
    nonisolated static var biometryLabel: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Passcode"
        }
    }

    private nonisolated static func message(for error: Error?) -> String {
        guard let code = (error as NSError?)?.code, let la = LAError.Code(rawValue: code) else {
            return "Couldn't verify it's you."
        }
        switch la {
        case .userCancel, .appCancel, .systemCancel: return "Unlock cancelled."
        case .userFallback: return "Use your device passcode to unlock."
        case .biometryLockout: return "Biometrics are locked out — use your device passcode."
        case .passcodeNotSet: return "Set a device passcode to use app lock."
        default: return "Couldn't verify it's you."
        }
    }
}
