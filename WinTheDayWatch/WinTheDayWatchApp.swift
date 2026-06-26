import SwiftUI

@main
struct WinTheDayWatchApp: App {
    @StateObject private var sync = WatchSync.shared
    init() { WatchSync.shared.activate() }
    var body: some Scene {
        WindowGroup {
            WatchView().environmentObject(sync)
        }
    }
}
