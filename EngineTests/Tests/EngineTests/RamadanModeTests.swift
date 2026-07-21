import XCTest
@testable import AppCore

/// Ramadan mode: the auto-detecting Hijri calendar (`RamadanCalendar`), the fasting-day flag's
/// tolerant decode (`Entry.ramadanFasting`), and the Eating timing allowance that stops a fast
/// being scored as a late dinner.
///
/// Everything runs in a fixed UTC calendar so the assertions don't drift with the machine's zone.
final class RamadanModeTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    /// Gregorian instant of a given Umm al-Qura Hijri date, midnight UTC.
    private func hijriDate(year: Int, month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.timeZone = utc
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return cal.date(from: c)!
    }

    private func adding(_ days: Int, to date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(byAdding: .day, value: days, to: date)!
    }

    // MARK: - Detection

    func testFirstDayOfRamadanIsDayOneAndTheDayBeforeIsOutside() {
        for year in [1446, 1447, 1448, 1450] {
            let first = hijriDate(year: year, month: 9, day: 1)
            XCTAssertTrue(RamadanCalendar.isRamadan(first, timeZone: utc), "1 Ramadan \(year) must read as Ramadan")
            XCTAssertEqual(RamadanCalendar.dayNumber(first, timeZone: utc), 1)
            XCTAssertEqual(RamadanCalendar.hijriYear(first, timeZone: utc), year)

            let sha_ban = adding(-1, to: first)
            XCTAssertFalse(RamadanCalendar.isRamadan(sha_ban, timeZone: utc), "the day before must not be Ramadan")
            XCTAssertNil(RamadanCalendar.dayNumber(sha_ban, timeZone: utc))
        }
    }

    func testRamadanIsOneContiguousRunOfTwentyNineOrThirtyDays() {
        let first = hijriDate(year: 1447, month: 9, day: 1)
        var run = 0
        for offset in 0..<40 {
            let d = adding(offset, to: first)
            if RamadanCalendar.isRamadan(d, timeZone: utc) {
                XCTAssertEqual(RamadanCalendar.dayNumber(d, timeZone: utc), offset + 1,
                               "day numbers must increase by one")
                run += 1
            } else { break }
        }
        XCTAssertTrue(run == 29 || run == 30, "Umm al-Qura months are 29 or 30 days, got \(run)")
        // …and nothing after the run is Ramadan again in the same year.
        for offset in run..<(run + 40) {
            XCTAssertFalse(RamadanCalendar.isRamadan(adding(offset, to: first), timeZone: utc))
        }
    }

    func testDaysRemainingCountsTodayAndHitsOneOnTheLastDay() {
        let first = hijriDate(year: 1447, month: 9, day: 1)
        let total = RamadanCalendar.daysRemaining(first, timeZone: utc)
        XCTAssertNotNil(total)
        XCTAssertEqual(total, RamadanCalendar.dayNumber(adding((total ?? 1) - 1, to: first), timeZone: utc),
                       "the last day's number equals the month length")
        XCTAssertEqual(RamadanCalendar.daysRemaining(adding((total ?? 1) - 1, to: first), timeZone: utc), 1)
        XCTAssertNil(RamadanCalendar.daysRemaining(adding(-1, to: first), timeZone: utc),
                     "nil outside Ramadan")
    }

    /// The moon-sighting knob is the whole reason a hardcoded calendar is wrong somewhere every year.
    func testAdjustmentShiftsTheWholeWindowByExactlyOneDay() {
        let first = hijriDate(year: 1447, month: 9, day: 1)
        let dayBefore = adding(-1, to: first)

        // +1 ⇒ "it started a day earlier here": the day before 1 Ramadan already counts as day 1.
        XCTAssertTrue(RamadanCalendar.isRamadan(dayBefore, adjustmentDays: 1, timeZone: utc))
        XCTAssertEqual(RamadanCalendar.dayNumber(dayBefore, adjustmentDays: 1, timeZone: utc), 1)
        XCTAssertEqual(RamadanCalendar.dayNumber(first, adjustmentDays: 1, timeZone: utc), 2)

        // −1 ⇒ "it started a day later here": 1 Ramadan is not yet Ramadan.
        XCTAssertFalse(RamadanCalendar.isRamadan(first, adjustmentDays: -1, timeZone: utc))
        XCTAssertEqual(RamadanCalendar.dayNumber(adding(1, to: first), adjustmentDays: -1, timeZone: utc), 1)
    }

    func testMidMonthDaysAreNeverRamadanInAnUnrelatedHijriMonth() {
        for month in [1, 2, 8, 10, 12] {
            let d = hijriDate(year: 1447, month: month, day: 15)
            XCTAssertFalse(RamadanCalendar.isRamadan(d, timeZone: utc), "Hijri month \(month) is not Ramadan")
        }
    }

    // MARK: - Entry.ramadanFasting (tolerant decode — a missing key must not lose the entry)

    func testRamadanFastingRoundTrips() throws {
        var e = Entry(date: "2026-02-20")
        e.ramadanFasting = true
        e.quranPages = 3
        let data = try JSONEncoder().encode(e)
        let back = try JSONDecoder().decode(Entry.self, from: data)
        XCTAssertTrue(back.ramadanFasting)
        XCTAssertEqual(back.quranPages, 3)
    }

    func testEntryWithoutRamadanFastingKeyStillDecodes() throws {
        let json = #"{"date":"2025-01-01","calories":"2100","waterMl":1500}"#
        let e = try JSONDecoder().decode(Entry.self, from: Data(json.utf8))
        XCTAssertFalse(e.ramadanFasting, "missing key defaults to false")
        XCTAssertEqual(e.date, "2025-01-01")
        XCTAssertEqual(e.calories, "2100", "the rest of the entry must survive")
        XCTAssertEqual(e.waterMl, 1500)
    }

    // MARK: - Eating timing sub-score

    private func lateDinnerDay(ramadan: Bool) -> EatingScorer.Inputs {
        var i = EatingScorer.Inputs()
        i.weightKg = 80; i.heightCm = 180; i.ageYears = 30; i.sexMale = true
        i.calories = 2500; i.proteinG = 130; i.carbsG = 300; i.fatG = 80
        i.activeKcal = 500
        i.microRatios = Array(repeating: 1.0, count: 8)
        // Iftar at 18:45, bed at 20:30 — 1.75h, well short of the normal 3h bar.
        i.dinnerEpoch = 1_772_045_100
        i.referenceBedEpoch = i.dinnerEpoch + 1.75 * 3600
        i.ramadanFasting = ramadan
        return i
    }

    func testRamadanFastIsNotPenalizedForALateIftar() {
        let normal = EatingScorer.compute(lateDinnerDay(ramadan: false))
        let fasting = EatingScorer.compute(lateDinnerDay(ramadan: true))
        XCTAssertGreaterThan(fasting.score, normal.score,
                             "a Ramadan day must not be marked down for eating at Maghrib")
    }

    func testRamadanFlagDoesNotChangeAnythingElse() {
        var i = EatingScorer.Inputs()
        i.weightKg = 80; i.calories = 2500; i.proteinG = 130; i.carbsG = 300; i.fatG = 80
        // No dinner time logged → the timing sub-score is omitted either way.
        XCTAssertEqual(EatingScorer.compute(i).score,
                       EatingScorer.compute({ var r = i; r.ramadanFasting = true; return r }()).score)

        // A dinner that already clears 3h scores 100 with or without the flag.
        i.dinnerEpoch = 1_772_045_100
        i.referenceBedEpoch = i.dinnerEpoch + 4 * 3600
        XCTAssertEqual(EatingScorer.compute(i).score,
                       EatingScorer.compute({ var r = i; r.ramadanFasting = true; return r }()).score)
    }
}
