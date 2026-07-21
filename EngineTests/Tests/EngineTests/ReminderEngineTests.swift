import XCTest
@testable import AppCore

/// Locks in the contracts `ReminderEngine` exists for (docs/plans/PLAN-smart-reminders.md): one
/// reminder per rule at most, nothing scheduled into the past or beyond tonight, protected days and
/// won days stay quiet, and every toggle genuinely gates its rule.
final class ReminderEngineTests: XCTestCase {

    // MARK: - Fixtures

    /// 3pm on a normal day, 2 of 6 habits done, dinner unlogged, protein well short.
    private func afternoonState() -> ReminderEngine.State {
        var s = ReminderEngine.State()
        s.now = at(hour: 15, minute: 0)
        s.dayKey = "2026-07-07"
        s.habitsTotal = 6
        s.habitsDone = 2
        s.proteinTargetG = 150
        s.proteinG = 40
        s.dinnerCutoffEpoch = at(hour: 19, minute: 40).timeIntervalSince1970
        s.recommendedBedEpoch = at(hour: 22, minute: 40).timeIntervalSince1970
        return s
    }

    private func at(hour: Int, minute: Int, dayOffset: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 7 + dayOffset
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private func rules(_ s: ReminderEngine.State) -> [String] {
        ReminderEngine.plan(s).map { $0.rule }
    }

    // MARK: - The happy path

    func testAllFourRulesFireSoonestFirst() {
        // 18:00 protein · 19:10 dinner (cutoff − 30) · 20:00 streak · 22:10 bedtime (bed − 30)
        let planned = ReminderEngine.plan(afternoonState())
        XCTAssertEqual(planned.map { $0.rule }, ["protein", "dinner", "streak", "bedtime"])
        XCTAssertEqual(planned.map { $0.fireDate }, planned.map { $0.fireDate }.sorted())
        XCTAssertEqual(Set(planned.map { $0.rule }).count, planned.count, "at most one reminder per rule")
        XCTAssertLessThanOrEqual(planned.count, 4)
    }

    func testIdentifiersCarryThePrefixAndTheDate() throws {
        for r in ReminderEngine.plan(afternoonState()) {
            let id = r.identifier(dayKey: "2026-07-07")
            XCTAssertTrue(id.hasPrefix(ReminderEngine.idPrefix), id)
            XCTAssertTrue(id.hasSuffix("-2026-07-07"), id)
        }
    }

    func testEveryReminderFiresInTheFutureAndNotBeyondTonight() {
        let s = afternoonState()
        for r in ReminderEngine.plan(s) {
            XCTAssertGreaterThan(r.fireDate, s.now)
            XCTAssertLessThanOrEqual(r.fireDate.timeIntervalSince(Calendar.current.startOfDay(for: s.now)),
                                     28 * 3600)
        }
    }

    func testCopyNeverShamesTheUser() {
        for r in ReminderEngine.plan(afternoonState()) {
            let text = (r.title + " " + r.body).lowercased()
            for word in ["failed", "failure", "missed", "behind", "lazy", "don't"] {
                XCTAssertFalse(text.contains(word), "\(r.rule) copy reads as a guilt-trip: \(text)")
            }
        }
    }

    // MARK: - Master switch & per-rule toggles

    func testMasterToggleSilencesEverything() {
        var s = afternoonState()
        s.enabled = false
        XCTAssertTrue(ReminderEngine.plan(s).isEmpty)
    }

    func testEachToggleGatesOnlyItsOwnRule() {
        var s = afternoonState()
        s.streakRule = false
        XCTAssertEqual(rules(s), ["protein", "dinner", "bedtime"])
        s = afternoonState(); s.dinnerRule = false
        XCTAssertEqual(rules(s), ["protein", "streak", "bedtime"])
        s = afternoonState(); s.bedtimeRule = false
        XCTAssertEqual(rules(s), ["protein", "dinner", "streak"])
        s = afternoonState(); s.proteinRule = false
        XCTAssertEqual(rules(s), ["dinner", "streak", "bedtime"])
    }

    // MARK: - Streak rule

    func testStreakStaysQuietOnProtectedDays() {
        for status in ["sick", "travel", "rest"] {
            var s = afternoonState()
            s.dayStatus = status
            XCTAssertFalse(rules(s).contains("streak"), "\(status) days pause expectations")
        }
    }

    func testStreakStaysQuietOnceTheDayIsWon() {
        var s = afternoonState()
        s.habitsDone = 4          // 4/6 ≥ 60% — the day already cleared the bar
        XCTAssertFalse(rules(s).contains("streak"))
        s.habitsDone = 3          // 3/6 = 50%, 3 pending — still winnable
        XCTAssertTrue(rules(s).contains("streak"))
    }

    func testStreakNeedsAtLeastTwoPendingHabits() {
        var s = afternoonState()
        s.habitsTotal = 6; s.habitsDone = 5
        XCTAssertFalse(rules(s).contains("streak"))
        s.habitsTotal = 0; s.habitsDone = 0
        XCTAssertFalse(rules(s).contains("streak"), "no habits configured means nothing to nudge about")
    }

    func testStreakFiresAtTheConfiguredEveningHourAndNotOnceItHasPassed() throws {
        var s = afternoonState()
        s.eveningHour = 21
        let streak = ReminderEngine.plan(s).first { $0.rule == "streak" }
        XCTAssertEqual(Calendar.current.component(.hour, from: try XCTUnwrap(streak).fireDate), 21)

        s.now = at(hour: 22, minute: 30)      // past the hour — never schedule into the past
        XCTAssertFalse(rules(s).contains("streak"))
    }

    // MARK: - Dinner rule

    func testDinnerFiresThirtyMinutesBeforeTheCutoffAndCancelsOnceLogged() throws {
        let s = afternoonState()
        let dinner = ReminderEngine.plan(s).first { $0.rule == "dinner" }
        XCTAssertEqual(try XCTUnwrap(dinner).fireDate, at(hour: 19, minute: 10))

        var logged = s
        logged.dinnerLogged = true
        XCTAssertFalse(rules(logged).contains("dinner"))
    }

    func testDinnerNeedsASleepPlan() {
        var s = afternoonState()
        s.dinnerCutoffEpoch = 0
        XCTAssertFalse(rules(s).contains("dinner"))
    }

    // MARK: - Bedtime rule

    func testBedtimeFiresThirtyMinutesBeforeBed() throws {
        let bedtime = ReminderEngine.plan(afternoonState()).first { $0.rule == "bedtime" }
        XCTAssertEqual(try XCTUnwrap(bedtime).fireDate, at(hour: 22, minute: 10))
    }

    func testBedtimeJustPastMidnightStillCountsAsTonight() {
        var s = afternoonState()
        s.recommendedBedEpoch = at(hour: 0, minute: 50, dayOffset: 1).timeIntervalSince1970
        XCTAssertTrue(rules(s).contains("bedtime"))

        s.recommendedBedEpoch = at(hour: 9, minute: 0, dayOffset: 1).timeIntervalSince1970
        XCTAssertFalse(rules(s).contains("bedtime"), "anything past the window belongs to the next recompute")
    }

    // MARK: - Protein rule

    func testProteinFiresOnlyBelowSeventyPercentOfTarget() {
        var s = afternoonState()
        s.proteinG = 104           // 69% of 150
        XCTAssertTrue(rules(s).contains("protein"))
        s.proteinG = 106           // 71%
        XCTAssertFalse(rules(s).contains("protein"))
        s.proteinG = 0; s.proteinTargetG = 0
        XCTAssertFalse(rules(s).contains("protein"), "no target means no gap to report")
    }

    func testProteinReportsTheRemainingGap() throws {
        var s = afternoonState()
        s.proteinG = 60; s.proteinTargetG = 150
        let body = try XCTUnwrap(ReminderEngine.plan(s).first { $0.rule == "protein" }).body
        XCTAssertTrue(body.hasPrefix("90g"), body)
    }

    func testProteinDoesNotFireAfterSixPM() {
        var s = afternoonState()
        s.now = at(hour: 19, minute: 0)
        XCTAssertFalse(rules(s).contains("protein"))
    }

    // MARK: - Determinism

    func testSameStateProducesTheSamePlan() {
        let s = afternoonState()
        XCTAssertEqual(ReminderEngine.plan(s), ReminderEngine.plan(s))
    }
}
