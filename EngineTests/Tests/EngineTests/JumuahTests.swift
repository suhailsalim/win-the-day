import XCTest
@testable import AppCore

/// Jumu'ah replaces Dhuhr on Friday for those it is obligatory on. It is purely a *naming* change:
/// the slot keeps the same window and is still recorded under the `dhuhr` key, so history, streaks
/// and prayer scoring are untouched. These tests pin both halves of that.
final class JumuahTests: XCTestCase {

    /// Fixed UTC calendar so the weekday assertions cannot drift with the machine's locale —
    /// a locale whose week starts on Monday must not change what `.weekday` returns.
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = utc
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    func testFridayIsDetectedAcrossAWholeWeek() {
        // 2026-07-20 is a Monday; step through to Sunday.
        let days = ["2026-07-20": false,   // Mon
                    "2026-07-21": false,   // Tue
                    "2026-07-22": false,   // Wed
                    "2026-07-23": false,   // Thu
                    "2026-07-24": true,    // Fri
                    "2026-07-25": false,   // Sat
                    "2026-07-26": false]   // Sun
        for (day, expected) in days {
            XCTAssertEqual(PrayerTimes.isFriday(date("\(day) 12:00"), calendar: utc), expected, day)
        }
    }

    func testFridayHoldsAtBothEndsOfTheDay() {
        XCTAssertTrue(PrayerTimes.isFriday(date("2026-07-24 00:00"), calendar: utc))
        XCTAssertTrue(PrayerTimes.isFriday(date("2026-07-24 23:59"), calendar: utc))
        XCTAssertFalse(PrayerTimes.isFriday(date("2026-07-23 23:59"), calendar: utc))
        XCTAssertFalse(PrayerTimes.isFriday(date("2026-07-25 00:00"), calendar: utc))
    }

    func testOnlyDhuhrIsRenamed() {
        XCTAssertEqual(PrayerTimes.Name.dhuhr.label(jumuah: true), "Jumu'ah")
        XCTAssertEqual(PrayerTimes.Name.dhuhr.label(jumuah: false), "Dhuhr")
        // Every other prayer is unaffected, Friday or not.
        for n in PrayerTimes.Name.allCases where n != .dhuhr {
            XCTAssertEqual(n.label(jumuah: true), n.label, "\(n) must never be renamed")
        }
    }

    func testTheStoredKeyNeverChanges() {
        // This is the guarantee that keeps history, streaks and scoring intact: the rawValue is what
        // gets persisted, and it stays "dhuhr" no matter what the slot is called on screen.
        XCTAssertEqual(PrayerTimes.Name.dhuhr.rawValue, "dhuhr")
        XCTAssertEqual(PrayerTimes.Name.allCases.map(\.rawValue),
                       ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"])
    }
}
