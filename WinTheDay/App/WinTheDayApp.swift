import SwiftUI

@main
struct WinTheDayApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var health = HealthManager()
    @StateObject private var prayer = PrayerManager()
    @StateObject private var hydration = HydrationManager()
    @StateObject private var studyTimer = StudyTimer()
    @StateObject private var fasting = FastingManager()
    @StateObject private var ramadan = RamadanManager()          // auto-detected Ramadan mode
    @StateObject private var calendar = CalendarManager()
    @StateObject private var weather = WeatherManager()
    @StateObject private var lock = AppLock()
    @StateObject private var windDownRouter = WindDownRouter()   // routes a tapped `winddown-` nudge
    @StateObject private var theme = ThemeController()
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
                .environmentObject(ramadan)
                .environmentObject(calendar)
                .environmentObject(weather)
                .environmentObject(lock)
                .environmentObject(windDownRouter)
                .environmentObject(theme)
                .tint(Theme.accentDark)
                // `.system` resolves to nil, which hands the choice back to iOS.
                .preferredColorScheme(theme.mode.colorScheme)
                // `Theme`'s tokens are computed properties, so SwiftUI has no way to know that views
                // it considers unchanged now resolve to different colours. Re-key on a palette
                // change to force one clean re-render; this fires only when the user flips a
                // setting or toggles Reduce Transparency, never during normal use.
                .id(theme.revision)
                // App lock: privacy cover + Face ID gate, drawn above every tab.
                .overlay {
                    if lock.shielded { LockScreenView().environmentObject(lock) }
                }
                .animation(.easeOut(duration: 0.15), value: lock.shielded)
                .task { lock.start(enabled: store.settings.appLockEnabled) }
                .task {
                    theme.start()
                    theme.apply(mode: store.settings.theme, darkStyle: store.settings.dark)
                }
                // Settings edits and restored backups both land here.
                .onChange(of: store.settings) { _, s in
                    theme.apply(mode: s.theme, darkStyle: s.dark)
                }
                // Cold launch: `.onChange(of: scenePhase)` isn't guaranteed to fire for the very
                // first `.active`, and a Siri/widget write made before launch must not be lost.
                .task { store.reconcileIntentWrites(prayerTimes: prayer.today, nextFajr: prayer.nextFajr) }
                .task { windDownRouter.start() }
                // Ramadan mode: wire the manager to its two peers, then keep it honest whenever the
                // computed Maghrib moves (a new location, a new day, a method change).
                .task { ramadan.attach(prayer: prayer, fasting: fasting); syncRamadan() }
                .onChange(of: prayer.today?[.maghrib]) { _, _ in ramadan.refresh(force: true); syncRamadan() }
                // Jumu'ah "auto" follows the sex in Targets; mirror it so the notification
                // scheduler, which runs without the store, can resolve it too.
                .task { prayer.syncSex(male: store.targets.sexMale) }
                .onChange(of: store.targets.sexMale) { _, male in prayer.syncSex(male: male) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                store.writeAutoBackup()
                store.refreshSmartReminders(force: true)
                store.refreshWindDown(force: true)
            }
            // Re-read anything an intent wrote while we were suspended, *before* any in-app edit
            // can persist our stale cache over it. Cheap no-op when nothing was written.
            if phase == .active {
                store.reconcileIntentWrites(prayerTimes: prayer.today, nextFajr: prayer.nextFajr)
                ramadan.refresh(force: true)   // the day may have rolled over while we were suspended
                syncRamadan()
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

    /// Push Ramadan's derived state into the store: the day's fasting flag (which the Eating timing
    /// sub-score reads) and the once-per-Hijri-year taraweeh habit.
    @MainActor private func syncRamadan() {
        store.setRamadanFasting(ramadan.isFastingToday)
        if ramadan.isActiveToday, ramadan.consumeTaraweehSeed() { store.seedTaraweehHabit() }
    }
}
