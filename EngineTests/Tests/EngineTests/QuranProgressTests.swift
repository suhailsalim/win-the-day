import XCTest
@testable import AppCore

/// Khatmah plan maths + the position tables, and the tolerant-decode guard for the two persisted
/// pieces this feature adds (`Entry.quranPages`, `AppData.khatmah` / `KhatmahPlan`).
///
/// The plan deliberately has **no stored page counter**: the position is `startPage + Σ pages`, so
/// the tests below feed the sum in rather than mutating state — editing a past day can only move
/// the position by the delta.
final class QuranProgressTests: XCTestCase {

    private func plan(days: Int = 30, startPage: Int = 0) -> KhatmahPlan {
        KhatmahPlan(startEpoch: 1_772_000_000, targetDays: days, startPage: startPage)
    }

    // MARK: - Tables

    func testJuzTableCovers604PagesInOrder() {
        XCTAssertEqual(QuranProgress.juzStartPages.count, 30)
        XCTAssertEqual(QuranProgress.juzStartPages.first, 1)
        XCTAssertEqual(QuranProgress.juzStartPages.last, 582)
        for (a, b) in zip(QuranProgress.juzStartPages, QuranProgress.juzStartPages.dropFirst()) {
            XCTAssertLessThan(a, b, "juz' start pages must strictly increase")
        }
        XCTAssertTrue(QuranProgress.juzStartPages.allSatisfy { (1...QuranProgress.totalPages).contains($0) })
    }

    func testJuzLookupAtBoundariesAndClamps() {
        XCTAssertEqual(QuranProgress.juz(forPage: 1), 1)
        XCTAssertEqual(QuranProgress.juz(forPage: 21), 1)
        XCTAssertEqual(QuranProgress.juz(forPage: 22), 2)
        XCTAssertEqual(QuranProgress.juz(forPage: 231), 12)
        XCTAssertEqual(QuranProgress.juz(forPage: 582), 30)
        XCTAssertEqual(QuranProgress.juz(forPage: 604), 30)
        XCTAssertEqual(QuranProgress.juz(forPage: 0), 1, "a page below the mushaf clamps, never crashes")
        XCTAssertEqual(QuranProgress.juz(forPage: 9_999), 30)
    }

    func testSurahTableIsCompleteAndNonDecreasing() {
        XCTAssertEqual(QuranProgress.surahStartPages.count, 114)
        XCTAssertEqual(QuranProgress.surahStartPages.map(\.number), Array(1...114))
        for (a, b) in zip(QuranProgress.surahStartPages, QuranProgress.surahStartPages.dropFirst()) {
            XCTAssertLessThanOrEqual(a.page, b.page, "surah start pages must not go backwards")
        }
        XCTAssertEqual(QuranProgress.surahStartPages.last?.page, QuranProgress.totalPages)
        // Anchors shared with the juz' table — the two tables must agree.
        XCTAssertEqual(QuranProgress.surah(forPage: 582)?.number, 78, "juz' 30 begins with An-Naba")
        XCTAssertEqual(QuranProgress.surah(forPage: 562)?.number, 67, "juz' 29 begins with Al-Mulk")
        XCTAssertEqual(QuranProgress.surah(forPage: 231)?.name, "Hud")
    }

    func testPositionLabelIsAPositionAndNothingMore() {
        XCTAssertEqual(QuranProgress.positionLabel(page: 231), "Juz' 12 · Hud · p. 231")
        XCTAssertEqual(QuranProgress.positionLabel(page: 0), "Not started yet")
        XCTAssertTrue(QuranProgress.positionLabel(page: 604).hasSuffix("p. 604"))
    }

    func testJuzEquivalentOfAPageCount() {
        XCTAssertEqual(QuranProgress.pagesInOneJuz, 20)
        XCTAssertEqual(QuranProgress.juzEquivalent(pages: 0), 0)
        XCTAssertEqual(QuranProgress.juzEquivalent(pages: QuranProgress.totalPages), 30, accuracy: 0.001)
        XCTAssertEqual(QuranProgress.juzEquivalent(pages: -5), 0, "negative pages can't read as negative juz'")
    }

    // MARK: - Plan maths

    func testThirtyDayKhatmahStartedTodayAsksFor21PagesADay() {
        let s = QuranProgress.status(plan: plan(), pagesBeforeToday: 0, pagesToday: 0, dayIndex: 0)
        XCTAssertEqual(s.dailyTarget, 21, "ceil(604/30)")
        XCTAssertEqual(s.flatDailyPages, 21)
        XCTAssertEqual(s.dayNumber, 1)
        XCTAssertEqual(s.daysRemaining, 30)
        XCTAssertEqual(s.currentPage, 0)
        XCTAssertEqual(s.pagesRemaining, 604)
        XCTAssertFalse(s.isComplete)
    }

    func testMissedDaysRedistributeForwardInsteadOfPilingUpAsDebt() {
        // Two days missed entirely: the ask rises, but only over the days that are left.
        let s = QuranProgress.status(plan: plan(), pagesBeforeToday: 0, pagesToday: 0, dayIndex: 2)
        XCTAssertEqual(s.dailyTarget, 22, "ceil(604/28)")
        XCTAssertEqual(s.dayNumber, 3)
        XCTAssertEqual(s.daysRemaining, 28)
        XCTAssertEqual(s.paceDelta, -63, "3 days × 21 pages expected, none read")
    }

    func testTodaysTargetIsFixedAtTheStartOfTheDay() {
        // Reading during the day must not shrink the day's own ask underneath the reader.
        let before = QuranProgress.status(plan: plan(), pagesBeforeToday: 0, pagesToday: 0, dayIndex: 0)
        let during = QuranProgress.status(plan: plan(), pagesBeforeToday: 0, pagesToday: 12, dayIndex: 0)
        XCTAssertEqual(before.dailyTarget, during.dailyTarget)
        XCTAssertEqual(during.remainingToday, 9)
        XCTAssertEqual(during.currentPage, 12)
    }

    func testSurplusReadingIsCreditedAndLowersTomorrowsAsk() {
        let today = QuranProgress.status(plan: plan(), pagesBeforeToday: 0, pagesToday: 60, dayIndex: 0)
        XCTAssertEqual(today.remainingToday, 0)
        XCTAssertEqual(today.paceDelta, 39, "reading past the ask counts as ahead, it is not clipped")
        let tomorrow = QuranProgress.status(plan: plan(), pagesBeforeToday: 60, pagesToday: 0, dayIndex: 1)
        XCTAssertEqual(tomorrow.dailyTarget, 19, "ceil(544/29)")
    }

    func testEditingAPastDayMovesThePositionByTheDeltaNotByTheWholeAmount() {
        // Same day, entries corrected 40 → 30 pages. The position is derived, so it drops by 10.
        let logged = QuranProgress.status(plan: plan(), pagesBeforeToday: 40, pagesToday: 0, dayIndex: 3)
        let corrected = QuranProgress.status(plan: plan(), pagesBeforeToday: 30, pagesToday: 0, dayIndex: 3)
        XCTAssertEqual(logged.currentPage, 40)
        XCTAssertEqual(corrected.currentPage, 30)
        XCTAssertEqual(logged.currentPage - corrected.currentPage, 10)
        XCTAssertEqual(corrected.pagesRead, 30, "a re-log must never add on top of the old value")
    }

    func testCompletionCapsAt604AndReportsDone() {
        let s = QuranProgress.status(plan: plan(), pagesBeforeToday: 600, pagesToday: 30, dayIndex: 25)
        XCTAssertTrue(s.isComplete)
        XCTAssertEqual(s.currentPage, 604, "the position never runs past the last page")
        XCTAssertEqual(s.pagesRemaining, 0)
        XCTAssertEqual(s.dailyTarget, 1, "4 pages left spread over the 5 days that remained")
        XCTAssertEqual(s.fraction, 1, accuracy: 0.0001)
    }

    func testFinishedPlanAsksForNothingMore() {
        let s = QuranProgress.status(plan: plan(), pagesBeforeToday: 604, pagesToday: 0, dayIndex: 26)
        XCTAssertTrue(s.isComplete)
        XCTAssertEqual(s.dailyTarget, 0)
        XCTAssertEqual(s.remainingToday, 0)
    }

    func testPastTheTargetDateEverythingLeftLandsOnTodayWithoutDividingByZero() {
        let s = QuranProgress.status(plan: plan(), pagesBeforeToday: 500, pagesToday: 0, dayIndex: 40)
        XCTAssertEqual(s.daysRemaining, 0)
        XCTAssertEqual(s.dailyTarget, 104, "all remaining pages, not a crash and not 0")
        XCTAssertEqual(s.dayNumber, 41)
    }

    func testPlanContinuingFromAStartPage() {
        let s = QuranProgress.status(plan: plan(days: 30, startPage: 300), pagesBeforeToday: 0, pagesToday: 0, dayIndex: 0)
        XCTAssertEqual(s.flatDailyPages, 11, "ceil(304/30)")
        XCTAssertEqual(s.dailyTarget, 11)
        XCTAssertEqual(s.currentPage, 300)
        XCTAssertEqual(s.fraction, 300.0 / 604.0, accuracy: 0.0001)
    }

    func testOneJuzADayRamadanPaceFinishesInThirtyDays() {
        let s = QuranProgress.status(plan: plan(days: 30), pagesBeforeToday: 20 * 29, pagesToday: 20, dayIndex: 29)
        XCTAssertEqual(s.daysRemaining, 1)
        XCTAssertEqual(s.pagesRead, 600)
        XCTAssertEqual(s.dailyTarget, 24, "the last day mops up what a flat 20/day leaves behind")
    }

    // MARK: - Hostile / degenerate plans

    func testDegenerateStoredValuesAreClampedRatherThanCrashing() {
        let broken = KhatmahPlan(startEpoch: 1, targetDays: 0, startPage: -50)
        let s = QuranProgress.status(plan: broken, pagesBeforeToday: -5, pagesToday: -5, dayIndex: -3)
        XCTAssertEqual(s.dailyTarget, 604, "targetDays 0 must not divide by zero")
        XCTAssertEqual(s.currentPage, 0)
        XCTAssertEqual(s.dayNumber, 1)

        let past604 = KhatmahPlan(targetDays: 10, startPage: 9_999)
        XCTAssertEqual(QuranProgress.flatDailyPages(past604), 0)
        XCTAssertTrue(QuranProgress.status(plan: past604, pagesBeforeToday: 0, pagesToday: 0, dayIndex: 0).isComplete)
    }

    // MARK: - Tolerant Codable (AGENTS.md convention 1)

    func testKhatmahPlanRoundTripsEveryField() throws {
        let original = KhatmahPlan(startEpoch: 1_772_000_000, targetDays: 45, startPage: 120,
                                   completedEpochs: [1_770_000_000, 1_771_000_000])
        let back = try JSONDecoder().decode(KhatmahPlan.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(back, original, "a missing tolerant decode line would silently drop part of the plan")
        XCTAssertEqual(back.timesCompleted, 2)
    }

    func testKhatmahPlanSurvivesEmptyAndHostileJSON() throws {
        let empty = try JSONDecoder().decode(KhatmahPlan.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.startEpoch, 0)
        XCTAssertEqual(empty.targetDays, 30)
        XCTAssertEqual(empty.startPage, 0)
        XCTAssertTrue(empty.completedEpochs.isEmpty)
        XCTAssertNil(empty.startDate)

        // The whole plan is decoded as one value inside AppData — one bad key must not delete it.
        let hostile = try JSONDecoder().decode(
            KhatmahPlan.self,
            from: Data(#"{"startEpoch":1772000000,"targetDays":"soon","startPage":null,"completedEpochs":"none"}"#.utf8))
        XCTAssertEqual(hostile.startEpoch, 1_772_000_000)
        XCTAssertEqual(hostile.targetDays, 30)
        XCTAssertEqual(hostile.startPage, 0)
        XCTAssertTrue(hostile.completedEpochs.isEmpty)
    }

    func testEntryAndAppDataKeepTheNewQuranFields() throws {
        var e = Entry(date: "2026-03-04")
        e.quranPages = 23
        let backEntry = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(backEntry.quranPages, 23, "Entry.quranPages needs its own tolerant decode line")
        XCTAssertTrue(e.isMeaningful, "a day with only Qur'an pages must still be saved — the plan derives from it")

        var d = AppData()
        d.entries = ["2026-03-04": e]
        d.khatmah = KhatmahPlan(startEpoch: 1_772_000_000, targetDays: 60, startPage: 40)
        let backData = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(backData.khatmah, d.khatmah)
        XCTAssertEqual(backData.entries["2026-03-04"]?.quranPages, 23)

        // Data written before this feature existed: no plan, no pages, nothing thrown.
        let legacy = try JSONDecoder().decode(AppData.self, from: Data(#"{"audits":{"2026-01-09":"ok"}}"#.utf8))
        XCTAssertNil(legacy.khatmah)
        let legacyEntry = try JSONDecoder().decode(Entry.self, from: Data(#"{"date":"2025-11-02"}"#.utf8))
        XCTAssertEqual(legacyEntry.quranPages, 0)
    }

    func testQuranRingFillsProportionallyAndCapsAtTheDailyTarget() {
        var entry = Entry(date: "2026-03-04")
        entry.quranPages = 10
        let def = RingDef(source: .custom, metric: .quranPages)
        var ctx = RingEngine.Context()
        ctx.quranDailyTarget = 20
        let half = RingEngine.compute(def, entry: entry, ctx: ctx)
        XCTAssertEqual(half.fraction, 0.5, accuracy: 0.0001)
        XCTAssertTrue(half.available)
        XCTAssertEqual(half.displayValue, "10")

        entry.quranPages = 45
        XCTAssertEqual(RingEngine.compute(def, entry: entry, ctx: ctx).fraction, 1, accuracy: 0.0001)

        // No plan running → falls back to a juz' a day rather than reading as "not configured".
        let noPlan = RingEngine.compute(def, entry: Entry(date: "2026-03-04"), ctx: RingEngine.Context())
        XCTAssertTrue(noPlan.available)
        XCTAssertEqual(noPlan.caption, "of 20 pages")
    }

    func testQuranModuleKeySitsRightAfterPrayerAndSurvivesOldPrefs() throws {
        XCTAssertTrue(ModulePrefs.defaultOrder.contains("quran"))
        let i = try XCTUnwrap(ModulePrefs.defaultOrder.firstIndex(of: "quran"))
        XCTAssertEqual(ModulePrefs.defaultOrder[i - 1], "prayer")
        XCTAssertEqual(ModulePrefs().label("quran"), "Qur'an reading")
        XCTAssertFalse(ModulePrefs().enabled("quran"), "opt-in, like fasting")

        var m = ModulePrefs()
        m.quran = true
        let back = try JSONDecoder().decode(ModulePrefs.self, from: JSONEncoder().encode(m))
        XCTAssertTrue(back.quran, "ModulePrefs.quran needs its own tolerant decode line")
        // Prefs saved before the module existed must still gain it, at the end of the saved order.
        let legacy = try JSONDecoder().decode(ModulePrefs.self, from: Data(#"{"order":["rings","prayer"]}"#.utf8))
        XCTAssertTrue(legacy.order.contains("quran"))
        XCTAssertFalse(legacy.quran)
        XCTAssertEqual(legacy.setEnabledRoundTrip("quran"), true)
    }
}

private extension ModulePrefs {
    /// Tiny helper: `setEnabled` is `mutating`, so exercise it on a copy.
    func setEnabledRoundTrip(_ key: String) -> Bool {
        var copy = self
        copy.setEnabled(key, true)
        return copy.enabled(key)
    }
}
