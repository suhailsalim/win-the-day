import Foundation

/// Small payload the app writes to the shared App Group so home-screen widgets can render
/// without launching the app. Keep it tiny and Codable.
struct SharedSnapshot: Codable {
    var nextPrayerName: String = "—"
    var nextPrayerEpoch: Double = 0          // time of next prayer
    var placeName: String = ""
    var nnDone: Int = 0
    var nnTotal: Int = 5
    var prayersDone: Int = 0
    var score: Int = 0
    var waterMl: Int = 0
    var waterTarget: Int = 3000
    var caloriesText: String = "—"
    var proteinText: String = "—"

    // Fasting
    var fastingActive: Bool = false
    var fastStartEpoch: Double = 0
    var fastTargetHours: Double = 16
    var ramadanSuhoorEpoch: Double = 0
    var ramadanIftarEpoch: Double = 0

    // Weekly progress
    var weekDaysWon: Int = 0
    var weekDaysLogged: Int = 0
    var workoutsThisWeek: Int = 0
    var studyHoursToday: Double = 0

    // Plan (populated in a later phase)
    var nextSessionTitle: String = ""
    var nextSessionEpoch: Double = 0
    var nextOccasionTitle: String = ""
    var nextOccasionEpoch: Double = 0

    // Readiness & sleep
    var readiness: Int = 0
    var sleepScore: Int = 0
    var dayStatus: String = "normal"

    // Weather
    var weatherTempC: Double = 0
    var weatherCode: Int = -1
    var weatherSymbol: String = ""
    var outdoorOK: Bool = true
    var weatherHeadline: String = ""

    var nextPrayerDate: Date? { nextPrayerEpoch > 0 ? Date(timeIntervalSince1970: nextPrayerEpoch) : nil }
    var fastStartDate: Date? { fastStartEpoch > 0 ? Date(timeIntervalSince1970: fastStartEpoch) : nil }
    var nextSessionDate: Date? { nextSessionEpoch > 0 ? Date(timeIntervalSince1970: nextSessionEpoch) : nil }
    var nextOccasionDate: Date? { nextOccasionEpoch > 0 ? Date(timeIntervalSince1970: nextOccasionEpoch) : nil }
}

enum SharedStore {
    static let appGroup = "group.com.suhail.WinTheDay"            // iOS app + iOS widgets
    static let watchAppGroup = "group.com.suhail.WinTheDay.watch"  // watch app + watch complications
    private static let key = "snapshot"

    static func save(_ snapshot: SharedSnapshot, suite: String = appGroup) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: suite)?.set(data, forKey: key)
    }

    static func load(suite: String = appGroup) -> SharedSnapshot {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: key),
              let snap = try? JSONDecoder().decode(SharedSnapshot.self, from: data) else {
            return SharedSnapshot()
        }
        return snap
    }
}
