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
                .tint(Theme.accentDark)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.writeAutoBackup() }
        }
    }
}
