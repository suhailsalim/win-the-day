import XCTest
@testable import AppCore

/// Locks in the Shari windows `PrayerClassifier` encodes (docs/plans/2026-07-improvement-plan.md §4.3):
/// prompt / on-time / later-but-valid / qadha, Islamic midnight for Isha, the +90s grace on every
/// qadha boundary, and the fail-soft day score.
///
/// Every boundary is built from literal epochs, never from `Date()` or a calendar — `Date` is an
/// absolute instant and the classifier only ever compares instants, so these assertions hold in
/// every locale and time zone.
final class PrayerClassifierTests: XCTestCase {

    /// Local midnight of the fictional test day; all times are offsets from it in hours.
    private let dayStart: TimeInterval = 1_772_064_000

    private func t(_ hours: Double) -> Date { Date(timeIntervalSince1970: dayStart + hours * 3600) }
    private func t(_ hours: Double, plusSeconds: Double) -> Date {
        Date(timeIntervalSince1970: dayStart + hours * 3600 + plusSeconds)
    }

    // fajr 05:00 · sunrise 06:30 · dhuhr 12:30 · asr 16:00 · maghrib/sunset 19:00 · isha 20:30
    private var times: PrayerTimes {
        PrayerTimes(times: [.fajr: t(5), .sunrise: t(6.5), .dhuhr: t(12.5),
                            .asr: t(16), .maghrib: t(19), .isha: t(20.5)])
    }
    /// Tomorrow's Fajr — 05:00 the next morning (29h after this day's midnight).
    private var nextFajr: Date { t(29) }

    private func classify(_ name: PrayerTimes.Name, at marked: Date,
                          times: PrayerTimes? = nil, nextFajr: Date? = nil) -> PrayerBand {
        PrayerClassifier.classify(name, markedAt: marked, today: times ?? self.times,
                                  nextFajr: nextFajr ?? self.nextFajr)
    }

    // MARK: - Maghrib: prompt (20 min) → still fully valid until Isha → qadha after Isha

    func testMaghribBetweenPromptWindowAndIshaIsLateValidNeverQadha() {
        // The prompt sub-window is max(15 min, 20% of the 20-min window) = 15 min.
        XCTAssertEqual(classify(.maghrib, at: t(19, plusSeconds: 60)), .promptOnTime)
        XCTAssertEqual(classify(.maghrib, at: t(19.25)), .onTime)          // 19:15 — past prompt, inside window
        XCTAssertEqual(classify(.maghrib, at: t(19.5)), .lateValid)        // 19:30 — after +20min
        XCTAssertEqual(classify(.maghrib, at: t(20)), .lateValid)          // 20:00 — still before Isha
        XCTAssertEqual(classify(.maghrib, at: t(20, plusSeconds: 29 * 60 + 59)), .lateValid) // 20:29:59
    }

    func testMaghribAfterIshaPlusGraceIsQadha() {
        XCTAssertEqual(classify(.maghrib, at: t(20.5, plusSeconds: 60)), .lateValid, "inside the +90s grace")
        XCTAssertEqual(classify(.maghrib, at: t(20.5, plusSeconds: 120)), .qadha)
        XCTAssertEqual(classify(.maghrib, at: t(22)), .qadha)
    }

    // MARK: - Isha: preferred until Islamic midnight, permitted until next Fajr, then qadha

    func testIshaBeforeIslamicMidnightIsOnTime() throws {
        // Islamic midnight = sunset 19:00 + half the 10h night to 05:00 = 00:00.
        let midnight = try XCTUnwrap(PrayerClassifier.islamicMidnight(sunset: t(19), nextFajr: nextFajr))
        XCTAssertEqual(midnight, t(24))

        XCTAssertEqual(classify(.isha, at: t(20.5, plusSeconds: 300)), .promptOnTime)  // first 42 min
        XCTAssertEqual(classify(.isha, at: t(22)), .onTime)
        XCTAssertEqual(classify(.isha, at: t(23.9)), .onTime)
    }

    func testIshaAfterIslamicMidnightIsLateValidAndAfterNextFajrIsQadha() {
        XCTAssertEqual(classify(.isha, at: t(24, plusSeconds: 60)), .lateValid)
        XCTAssertEqual(classify(.isha, at: t(27)), .lateValid)             // 03:00 — permitted, not qadha
        XCTAssertEqual(classify(.isha, at: t(29, plusSeconds: 60)), .lateValid, "inside the +90s grace")
        XCTAssertEqual(classify(.isha, at: t(29, plusSeconds: 300)), .qadha)
    }

    // MARK: - Missing times (high latitude / no coordinates yet) must never crash

    func testMissingPrayerTimeClassifiesUnknown() {
        let noIsha = PrayerTimes(times: [.fajr: t(5), .sunrise: t(6.5), .dhuhr: t(12.5),
                                         .asr: t(16), .maghrib: t(19)])
        XCTAssertEqual(classify(.isha, at: t(22), times: noIsha), .unknown)
        XCTAssertEqual(classify(.maghrib, at: t(20), times: noIsha), .unknown)

        let empty = PrayerTimes(times: [:])
        for name in PrayerTimes.Name.allCases {
            XCTAssertEqual(classify(name, at: t(12), times: empty), .unknown,
                           "\(name.rawValue) must classify .unknown, not crash, without times")
        }
    }

    func testIshaWithoutTomorrowsFajrIsUnknown() {
        XCTAssertEqual(PrayerClassifier.classify(.isha, markedAt: t(22), today: times, nextFajr: nil), .unknown)
        XCTAssertNil(PrayerClassifier.islamicMidnight(sunset: t(19), nextFajr: nil))
        XCTAssertNil(PrayerClassifier.islamicMidnight(sunset: nil, nextFajr: nextFajr))
        XCTAssertNil(PrayerClassifier.islamicMidnight(sunset: t(19), nextFajr: t(18)),
                     "a next-Fajr before sunset is nonsense, not a negative night")
    }

    func testSunriseIsNeverAPrayer() {
        XCTAssertFalse(PrayerTimes.Name.sunrise.isPrayer)
        XCTAssertEqual(classify(.sunrise, at: t(6.5)), .unknown)
    }

    // MARK: - The +90s grace on every qadha boundary

    func testSixtySecondsPastTheQadhaBoundaryIsStillPreQadha() {
        // Fajr's window ends at sunrise, which is also its qadha boundary — no makruh tail.
        XCTAssertEqual(classify(.fajr, at: t(6.5, plusSeconds: -1)), .onTime)
        XCTAssertEqual(classify(.fajr, at: t(6.5, plusSeconds: 60)), .lateValid, "60s < the 90s grace")
        XCTAssertEqual(classify(.fajr, at: t(6.5, plusSeconds: 89)), .lateValid)
        XCTAssertEqual(classify(.fajr, at: t(6.5, plusSeconds: 90)), .qadha, "the grace is exclusive at 90s")
        XCTAssertEqual(classify(.fajr, at: t(7)), .qadha)
    }

    func testFajrPromptWindowIsTwentyPercentOfTheWindow() {
        // 05:00 → 06:30 is 90 min, so prompt runs to 05:18.
        XCTAssertEqual(classify(.fajr, at: t(5, plusSeconds: 60)), .promptOnTime)
        XCTAssertEqual(classify(.fajr, at: t(5.25)), .promptOnTime)   // 05:15
        XCTAssertEqual(classify(.fajr, at: t(5.5)), .onTime)          // 05:30
    }

    func testMarkedBeforeTheWindowOpensIsUnknownNotPenalised() {
        XCTAssertEqual(classify(.fajr, at: t(4)), .unknown)
        XCTAssertEqual(classify(.dhuhr, at: t(11)), .unknown)
        XCTAssertEqual(classify(.asr, at: t(15)), .unknown)
    }

    // MARK: - Dhuhr & Asr (including Asr's makruh tail)

    func testDhuhrIsQadhaOnceAsrOnsetPasses() {
        XCTAssertEqual(classify(.dhuhr, at: t(12.5, plusSeconds: 60)), .promptOnTime)
        XCTAssertEqual(classify(.dhuhr, at: t(14)), .onTime)
        XCTAssertEqual(classify(.dhuhr, at: t(16, plusSeconds: 60)), .lateValid, "inside the grace")
        XCTAssertEqual(classify(.dhuhr, at: t(16.5)), .qadha)
    }

    func testAsrMakruhTailIsLateValidAndSunsetEndsTheWindow() {
        XCTAssertEqual(classify(.asr, at: t(16, plusSeconds: 60)), .promptOnTime)
        XCTAssertEqual(classify(.asr, at: t(17.5)), .onTime)
        XCTAssertEqual(classify(.asr, at: t(18.75)), .lateValid, "the last 30 min before sunset is makruh but valid")
        XCTAssertEqual(classify(.asr, at: t(19, plusSeconds: 120)), .qadha)
    }

    // MARK: - Band points (what the ring actually adds up)

    func testBandPointsAreOrderedPromptHighestNotLoggedZero() {
        XCTAssertEqual(PrayerBand.promptOnTime.points, 10)
        XCTAssertEqual(PrayerBand.onTime.points, 8)
        XCTAssertEqual(PrayerBand.lateValid.points, 5)
        XCTAssertEqual(PrayerBand.unknown.points, 5)
        XCTAssertEqual(PrayerBand.qadha.points, 2)
        XCTAssertEqual(PrayerBand.notLogged.points, 0)
    }

    // MARK: - Fail-soft day score

    func testDayScoreExcludesPrayersThatArentDueYet() {
        var log = PrayerLog()
        log.setOn("fajr", true, at: dayStart + 5.2 * 3600, band: .promptOnTime)
        // 13:00 — Fajr done, Dhuhr's window still open, Asr onwards not due.
        let (points, outOf) = PrayerClassifier.dayScore(prayers: log, today: times,
                                                       nextFajr: nextFajr, now: t(13))
        XCTAssertEqual(points, 10)
        XCTAssertEqual(outOf, 10, "an open window must not be counted as a miss")
    }

    func testDayScoreCountsPassedWindowsAsQadhaButNotTheOpenOne() {
        // 21:00, nothing marked: Fajr/Dhuhr/Asr/Maghrib windows have closed; Isha is still open.
        let (points, outOf) = PrayerClassifier.dayScore(prayers: PrayerLog(), today: times,
                                                       nextFajr: nextFajr, now: t(21))
        XCTAssertEqual(points, 4 * PrayerBand.qadha.points)
        XCTAssertEqual(outOf, 40)
    }

    func testDayScoreIsZeroOutOfZeroBeforeFajr() {
        let (points, outOf) = PrayerClassifier.dayScore(prayers: PrayerLog(), today: times,
                                                        nextFajr: nextFajr, now: t(4))
        XCTAssertEqual(points, 0)
        XCTAssertEqual(outOf, 0, "before the first window there is nothing to score — the ring dims instead of showing 0%")
    }

    func testDayScoreIsPerfectWhenEveryPrayerIsPrompt() {
        var log = PrayerLog()
        for name in ["fajr", "dhuhr", "asr", "maghrib", "isha"] {
            log.setOn(name, true, at: dayStart, band: .promptOnTime)
        }
        let (points, outOf) = PrayerClassifier.dayScore(prayers: log, today: times,
                                                        nextFajr: nextFajr, now: t(21))
        XCTAssertEqual(points, 50)
        XCTAssertEqual(outOf, 50)
    }

    func testDayScoreIsDeterministicForAFixedNow() {
        var log = PrayerLog()
        log.setOn("fajr", true, at: dayStart + 5.2 * 3600, band: .onTime)
        log.setOn("dhuhr", true, at: dayStart + 13 * 3600, band: .lateValid)
        let first = PrayerClassifier.dayScore(prayers: log, today: times, nextFajr: nextFajr, now: t(17))
        let second = PrayerClassifier.dayScore(prayers: log, today: times, nextFajr: nextFajr, now: t(17))
        XCTAssertEqual(first.points, second.points)
        XCTAssertEqual(first.outOf, second.outOf)
        XCTAssertEqual(first.points, 8 + 5 + 0)   // Asr is open at 17:00, so it is not counted at all
        XCTAssertEqual(first.outOf, 20)
    }
}
