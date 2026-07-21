import XCTest
@testable import AppCore

/// The milestone engine is pure and deterministic: stats in → catalog entries out. These tests pin
/// the three properties the feature depends on — thresholds fire exactly once, re-evaluating never
/// duplicates, and streak counting honours the app's rest/sick/travel protection.
final class MilestoneEngineTests: XCTestCase {

    private func stats(_ change: (inout MilestoneEngine.Stats) -> Void) -> MilestoneEngine.Stats {
        var s = MilestoneEngine.Stats()
        change(&s)
        return s
    }

    // MARK: - Catalog integrity

    func testCatalogIdsAreUniqueAndThresholdsPositive() {
        let ids = MilestoneEngine.catalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "a duplicate id would orphan somebody's earned record")
        for def in MilestoneEngine.catalog {
            XCTAssertGreaterThan(def.threshold, 0, "\(def.id) would be earned by an empty account")
            XCTAssertFalse(def.title.isEmpty)
            XCTAssertFalse(def.symbol.isEmpty)
        }
    }

    func testEmptyStatsEarnNothing() {
        XCTAssertTrue(MilestoneEngine.evaluate(stats: MilestoneEngine.Stats()).isEmpty)
    }

    // MARK: - Evaluate

    func testThresholdIsInclusiveAndOnlyFiresAtOrAboveIt() {
        let just = stats { $0.daysLogged = 6 }
        XCTAssertFalse(MilestoneEngine.evaluate(stats: just).contains { $0.id == "days-7" })

        let hit = stats { $0.daysLogged = 7 }
        XCTAssertTrue(MilestoneEngine.evaluate(stats: hit).contains { $0.id == "days-7" })

        let over = stats { $0.daysLogged = 400 }
        let ids = Set(MilestoneEngine.evaluate(stats: over).map(\.id))
        XCTAssertEqual(ids.intersection(["days-7", "days-30", "days-100", "days-365"]).count, 4,
                       "passing a high threshold must also grant the lower ones")
    }

    func testEvaluateIsDeterministicAndInCatalogOrder() {
        let s = stats { $0.daysLogged = 120; $0.workouts = 60; $0.studyHours = 300 }
        let a = MilestoneEngine.evaluate(stats: s).map(\.id)
        let b = MilestoneEngine.evaluate(stats: s).map(\.id)
        XCTAssertEqual(a, b)
        let order = MilestoneEngine.catalog.map(\.id)
        XCTAssertEqual(a, order.filter { a.contains($0) })
    }

    func testWaterGlassesDeriveFrom250mlUnits() {
        let s = stats { $0.waterMl = 125_100 }   // 500.4 glasses
        XCTAssertEqual(s.waterGlasses, 500)
        XCTAssertTrue(MilestoneEngine.evaluate(stats: s).contains { $0.id == "water-500" })
    }

    // MARK: - Idempotence (the whole point of persisting earned records)

    func testReEvaluatingNeverDuplicates() {
        let s = stats { $0.daysLogged = 40; $0.workouts = 12 }
        var record: [EarnedMilestone] = []

        let first = MilestoneEngine.newlyEarned(stats: s, already: record)
        XCTAssertFalse(first.isEmpty)
        record += first.map { EarnedMilestone(id: $0.id, earnedEpoch: 1_772_000_000) }

        XCTAssertTrue(MilestoneEngine.newlyEarned(stats: s, already: record).isEmpty,
                      "the same stats must not re-earn anything")

        // More progress grants only the new ones.
        let later = stats { $0.daysLogged = 110; $0.workouts = 12 }
        let second = MilestoneEngine.newlyEarned(stats: later, already: record)
        XCTAssertEqual(second.map(\.id), ["days-100"])

        record += second.map { EarnedMilestone(id: $0.id, earnedEpoch: 1_772_100_000) }
        XCTAssertEqual(Set(record.map(\.id)).count, record.count)
    }

    func testLosingDataNeverRevokesAnEarnedRecord() {
        // Earned at 100 days, then the entries vanish (deletion / failed import).
        let record = MilestoneEngine.evaluate(stats: stats { $0.daysLogged = 100 })
            .map { EarnedMilestone(id: $0.id, earnedEpoch: 1_772_000_000) }
        let wiped = MilestoneEngine.Stats()
        XCTAssertTrue(MilestoneEngine.newlyEarned(stats: wiped, already: record).isEmpty)
        // `newlyEarned` only ever *adds*; nothing in the engine can remove a record.
        XCTAssertEqual(record.count, MilestoneEngine.evaluate(stats: stats { $0.daysLogged = 100 }).count)
    }

    // MARK: - Upcoming

    func testUpcomingSkipsEarnedAndRanksByCloseness() {
        let s = stats { $0.daysLogged = 29; $0.workouts = 9 }
        let earned = [EarnedMilestone(id: "days-7", earnedEpoch: 1)]
        let next = MilestoneEngine.upcoming(stats: s, earned: earned, limit: 3)
        XCTAssertFalse(next.contains { $0.def.id == "days-7" }, "already earned must not resurface")
        XCTAssertEqual(next.first?.def.id, "days-30")
        XCTAssertEqual(next.first?.remaining, 1)
        XCTAssertEqual(next.count, 3)
        // Sorted closest-first.
        XCTAssertEqual(next.map(\.fraction), next.map(\.fraction).sorted(by: >))
    }

    // MARK: - Streaks (reuses the app's protection semantics)

    private func days(_ specs: [(String, Bool, Bool)]) -> [MilestoneEngine.DayFact] {
        specs.map { MilestoneEngine.DayFact(key: $0.0, won: $0.1, perfect: $0.1, isProtected: $0.2) }
    }

    func testLongestStreakCountsConsecutiveWonDays() {
        let facts = days([("2026-03-01", true, false), ("2026-03-02", true, false),
                          ("2026-03-03", false, false), ("2026-03-04", true, false),
                          ("2026-03-05", true, false), ("2026-03-06", true, false)])
        XCTAssertEqual(MilestoneEngine.longestStreak(facts), 3)
    }

    func testProtectedDaysPauseTheChainWithoutBreakingOrExtendingIt() {
        // A rest day sits in the middle of four won days — the chain is 4, not 5 and not 2.
        let facts = days([("2026-03-01", true, false), ("2026-03-02", true, false),
                          ("2026-03-03", false, true),   // rest/sick/travel
                          ("2026-03-04", true, false), ("2026-03-05", true, false)])
        XCTAssertEqual(MilestoneEngine.longestStreak(facts), 4)
    }

    func testAMissingCalendarDayBreaksTheChain() {
        let facts = days([("2026-03-01", true, false), ("2026-03-02", true, false),
                          // 03-03 never logged at all
                          ("2026-03-04", true, false)])
        XCTAssertEqual(MilestoneEngine.longestStreak(facts), 2)
    }

    func testStreakSpansMonthAndYearBoundaries() {
        let facts = days([("2025-12-30", true, false), ("2025-12-31", true, false),
                          ("2026-01-01", true, false), ("2026-01-02", true, false)])
        XCTAssertEqual(MilestoneEngine.longestStreak(facts), 4)
    }

    func testPerfectRunIsCountedSeparatelyFromWonDays() {
        let facts = [MilestoneEngine.DayFact(key: "2026-03-01", won: true, perfect: true),
                     MilestoneEngine.DayFact(key: "2026-03-02", won: true, perfect: false),
                     MilestoneEngine.DayFact(key: "2026-03-03", won: true, perfect: true),
                     MilestoneEngine.DayFact(key: "2026-03-04", won: true, perfect: true)]
        XCTAssertEqual(MilestoneEngine.longestStreak(facts), 4)
        XCTAssertEqual(MilestoneEngine.longestPerfectRun(facts), 2)
    }

    func testPerfectWeekNeedsSevenPerfectDaysInARow() {
        let keys = (1...7).map { String(format: "2026-03-%02d", $0) }
        let facts = keys.map { MilestoneEngine.DayFact(key: $0, won: true, perfect: true) }
        let run = MilestoneEngine.longestPerfectRun(facts)
        XCTAssertEqual(run, 7)
        XCTAssertTrue(MilestoneEngine.evaluate(stats: stats { $0.longestPerfectRun = Double(run) })
            .contains { $0.id == "perfect-week" })
    }

    func testEmptyAndMalformedDayKeys() {
        XCTAssertEqual(MilestoneEngine.longestStreak([]), 0)
        XCTAssertEqual(MilestoneEngine.longestStreak(days([("", true, false), ("nonsense", true, false)])), 0)
        XCTAssertNil(MilestoneEngine.dayIndex("2026-13-40"))
        XCTAssertEqual(MilestoneEngine.dayIndex("1970-01-01"), 0)
        XCTAssertEqual(MilestoneEngine.dayIndex("1970-01-02"), 1)
        XCTAssertEqual((MilestoneEngine.dayIndex("2026-03-02") ?? 0) - (MilestoneEngine.dayIndex("2026-02-28") ?? 0), 2,
                       "2026 is not a leap year — 28 Feb → 2 Mar is two days")
        XCTAssertEqual((MilestoneEngine.dayIndex("2024-03-01") ?? 0) - (MilestoneEngine.dayIndex("2024-02-28") ?? 0), 2,
                       "2024 is a leap year — 29 Feb sits in between")
    }

    // MARK: - Persistence of the record itself

    func testEarnedMilestoneRoundTripsAndToleratesEmptyJSON() throws {
        let rec = EarnedMilestone(id: "days-100", earnedEpoch: 1_772_000_000)
        let back = try JSONDecoder().decode(EarnedMilestone.self, from: JSONEncoder().encode(rec))
        XCTAssertEqual(back, rec)

        let empty = try JSONDecoder().decode(EarnedMilestone.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.id, "")
        XCTAssertEqual(empty.earnedEpoch, 0)
        XCTAssertNil(empty.earnedDate)

        let junk = try JSONDecoder().decode(EarnedMilestone.self,
                                            from: Data(#"{"id":"days-7","earnedEpoch":"soon"}"#.utf8))
        XCTAssertEqual(junk.id, "days-7", "a bad epoch must not take the id down with it")
        XCTAssertEqual(junk.earnedEpoch, 0)
    }
}
