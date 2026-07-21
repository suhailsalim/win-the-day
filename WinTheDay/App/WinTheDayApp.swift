import SwiftUI

@main
struct WinTheDayApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var health = HealthManager()
    @StateObject private var prayer = PrayerManager()
    @StateObject private var hydration = HydrationManager()
    @StateObject private var studyTimer = StudyTimer()
    @StateObject private var fasting = FastingManager()
    @StateObject private var calendar = CalendarManager()
    @StateObject private var weather = WeatherManager()
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(health)
                .environmentObject(prayer)
                .environmentObject(hydration)
                .environmentObject(studyTimer)
                .environmentObject(fasting)
                .environmentObject(calendar)
                .environmentObject(weather)
                .environmentObject(lock)
                .tint(Theme.accentDark)
                .preferredColorScheme(.light)
                // App lock: privacy cover + Face ID gate, drawn above every tab.
                .overlay {
                    if lock.shielded { LockScreenView().environmentObject(lock) }
                }
                .animation(.easeOut(duration: 0.15), value: lock.shielded)
                .task { lock.start(enabled: store.settings.appLockEnabled) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                store.writeAutoBackup()
                store.refreshSmartReminders(force: true)
            }
            let on = store.settings.appLockEnabled
            switch phase {
            case .inactive:   lock.willResignActive(enabled: on)
            case .background: lock.didEnterBackground(enabled: on)
            case .active:     lock.didBecomeActive(enabled: on, graceMinutes: store.settings.appLockGraceMinutes)
            @unknown default: break
            }
        }
    }
}
