import SwiftUI
import UIKit

/// Owns the live appearance state and keeps `Theme`'s UserDefaults mirrors in step with
/// `AppSettings`, so a dynamic `UIColor` provider can resolve the right palette at any time —
/// including at cold launch, before `AppStore` has decoded its JSON.
///
/// Liquid glass follows the *system*: iOS Accessibility → Reduce Transparency turns it off, and
/// this observes that switch live rather than only reading it at launch. There is deliberately no
/// in-app toggle for it — the OS setting is the setting.
@MainActor
final class ThemeController: ObservableObject {
    /// Bumped whenever anything about the palette changes. `WinTheDayApp` uses it to force one full
    /// re-render: `Theme`'s tokens are plain computed properties, so nothing else would tell SwiftUI
    /// that views it considers unchanged now resolve to different colours.
    @Published private(set) var revision = 0

    @Published private(set) var mode: ThemeMode = .system
    @Published private(set) var darkStyle: DarkStyle = .grey
    @Published private(set) var glassOn = true

    private var observer: NSObjectProtocol?

    init() {
        // Seed from the mirrors so the very first frame is already correct.
        let d = UserDefaults.standard
        darkStyle = DarkStyle(rawValue: d.string(forKey: Theme.darkStyleKey) ?? "") ?? .grey
        mode = ThemeMode(rawValue: d.string(forKey: Self.modeKey) ?? "") ?? .system
        glassOn = !d.bool(forKey: Theme.reduceTransparencyKey)
    }

    private static let modeKey = "theme_mode_v1"

    func start() {
        syncReduceTransparency()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncReduceTransparency() }
        }
    }

    /// Push the persisted preference into the mirrors. Called on launch and whenever Settings change.
    func apply(mode newMode: ThemeMode, darkStyle newStyle: DarkStyle) {
        let d = UserDefaults.standard
        var changed = false
        if newMode != mode {
            mode = newMode
            d.set(newMode.rawValue, forKey: Self.modeKey)
            changed = true
        }
        if newStyle != darkStyle {
            darkStyle = newStyle
            d.set(newStyle.rawValue, forKey: Theme.darkStyleKey)
            changed = true
        }
        // Always reconcile the mirror even when the value matched in memory — a restored backup can
        // replace AppSettings without going through this method.
        d.set(newStyle.rawValue, forKey: Theme.darkStyleKey)
        d.set(newMode.rawValue, forKey: Self.modeKey)
        if changed { revision += 1 }
    }

    private func syncReduceTransparency() {
        let reduced = UIAccessibility.isReduceTransparencyEnabled
        UserDefaults.standard.set(reduced, forKey: Theme.reduceTransparencyKey)
        guard glassOn == reduced else { return }   // already matches; nothing to redraw
        glassOn = !reduced
        revision += 1
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
