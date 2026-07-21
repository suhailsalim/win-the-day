import XCTest
@testable import AppCore

/// Locks in the Eating score's contracts (docs/plans/2026-07-improvement-plan.md §4.2): the
/// Mifflin–St Jeor BMR, the 1.15·BMR resting-day TDEE floor, and the "omit, don't zero" rule —
/// sub-scores without inputs drop out and the remaining weights renormalize, so a partially-logged
/// day never reads as a bad day.
final class EatingScorerTests: XCTestCase {

    // 80 kg / 180 cm / 30 y male → BMR 1780 kcal.
    private let bmr80kg: Double = 10 * 80 + 6.25 * 180 - 5 * 30 + 5

    /// A day where every sub-score has its inputs and each one scores 100 — the reference point the
    /// renormalization tests compare against.
    private func perfectDay() -> EatingScorer.Inputs {
        var i = EatingScorer.Inputs()
        i.weightKg = 80; i.heightCm = 180; i.ageYears = 30; i.sexMale = true
        i.activeKcal = 500                       // TDEE = 1780·1.10 + 500 = 2458
        i.calories = 2458
        i.proteinG = 128                         // maintain → 1.6 g/kg
        i.carbsG = 300                           // 48.8% of kcal (AMDR 45–65)
        i.fatG = 70                              // 25.6% of kcal (AMDR 20–35)
        i.microRatios = [1.0, 1.1, 1.0, 1.2, 1.0]
        i.dinnerEpoch = 1_772_128_800            // 19:00-ish
        i.referenceBedEpoch = 1_772_128_800 + 4 * 3600
        i.goal = "maintain"
        return i
    }

    // MARK: - BMR / TDEE

    func testBMRUsesMifflinStJeorAndNeedsAWeight() {
        XCTAssertEqual(EatingScorer.bmr(weightKg: 80, heightCm: 180, age: 30, male: true), bmr80kg, accuracy: 0.0001)
        XCTAssertEqual(EatingScorer.bmr(weightKg: 80, heightCm: 180, age: 30, male: false),
                       bmr80kg - 166, accuracy: 0.0001)   // +5 for male vs −161 for female
        XCTAssertEqual(EatingScorer.bmr(weightKg: 0, heightCm: 180, age: 30, male: true), 0,
                       "without a weight the BMR is unavailable, not a guess")
    }

    func testTDEEIsFlooredAtOnePointOneFiveTimesBMROnARestDay() {
        let floored = EatingScorer.tdee(bmr: bmr80kg, activeKcal: 0)
        XCTAssertEqual(floored, bmr80kg * 1.15, accuracy: 0.0001,
                       "a rest day must not collapse to bare BMR and read as a false surplus")
        XCTAssertGreaterThan(floored, bmr80kg * 1.10)
    }

    func testTDEEAddsActiveEnergyOnceItExceedsTheFloor() {
        XCTAssertEqual(EatingScorer.tdee(bmr: bmr80kg, activeKcal: 500),
                       bmr80kg * 1.10 + 500, accuracy: 0.0001)
        XCTAssertEqual(EatingScorer.tdee(bmr: 0, activeKcal: 500), 0, "no weight → no TDEE")
        // Negative active energy is nonsense input; it must not drag TDEE below the floor.
        XCTAssertEqual(EatingScorer.tdee(bmr: bmr80kg, activeKcal: -900), bmr80kg * 1.15, accuracy: 0.0001)
    }

    func testComputeSurfacesTheSameTDEEAndNetKcal() {
        var i = perfectDay()
        i.calories = 2758
        let r = EatingScorer.compute(i)
        XCTAssertEqual(r.tdee, 2458, accuracy: 0.0001)
        XCTAssertEqual(r.netKcal, 300, accuracy: 0.0001)
        XCTAssertEqual(EatingScorer.compute(EatingScorer.Inputs()).netKcal, 0,
                       "no TDEE and no intake → no projection, not a fabricated one")
    }

    // MARK: - The happy path

    func testAFullyLoggedOnTargetDayScoresOneHundredAndIsNotPartial() {
        let r = EatingScorer.compute(perfectDay())
        XCTAssertTrue(r.available)
        XCTAssertFalse(r.partial, "every sub-score had its inputs")
        XCTAssertEqual(r.score, 100)
    }

    func testComputeIsDeterministic() {
        let a = EatingScorer.compute(perfectDay())
        let b = EatingScorer.compute(perfectDay())
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(a.available, b.available)
        XCTAssertEqual(a.partial, b.partial)
        XCTAssertEqual(a.tdee, b.tdee, accuracy: 0.0001)
        XCTAssertEqual(a.netKcal, b.netKcal, accuracy: 0.0001)
    }

    // MARK: - Omit, don't zero: gating + renormalization

    func testMissingMicrosAndDinnerMarkThePartialFlagWithoutScoringZero() {
        var i = perfectDay()
        i.microRatios = [1.0, 1.0, 1.0, 1.0]   // 4 tracked nutrients — one short of the ≥5 gate
        i.dinnerEpoch = 0
        i.referenceBedEpoch = 0
        let r = EatingScorer.compute(i)
        XCTAssertTrue(r.available)
        XCTAssertTrue(r.partial, "omitted sub-scores must be advertised")
        XCTAssertEqual(r.score, 100, "the surviving weights renormalize — an unlogged nutrient is not a 0")
    }

    func testFiveMicroRatiosAreEnoughToCountAndAreCappedAtOne() {
        var i = perfectDay()
        i.microRatios = [1.0, 1.0, 1.0, 1.0]
        XCTAssertTrue(EatingScorer.compute(i).partial)
        i.microRatios = [1.0, 1.0, 1.0, 1.0, 1.0]
        XCTAssertFalse(EatingScorer.compute(i).partial)

        // A 10× overdose of one nutrient must not paper over four missing ones.
        var lopsided = perfectDay()
        lopsided.microRatios = [10, 0, 0, 0, 0]
        XCTAssertLessThan(EatingScorer.compute(lopsided).score, 100)
    }

    func testOnlyCalorieProteinAndMacroSubScoresStillRenormalizeToOneHundred() {
        var i = perfectDay()
        i.microRatios = []
        i.dinnerEpoch = 0
        i.referenceBedEpoch = 0
        let r = EatingScorer.compute(i)
        // Raw weights of the three survivors sum to 0.71 — without renormalization this would be 71.
        XCTAssertEqual(r.score, 100)
        XCTAssertTrue(r.partial)
    }

    func testScoreStaysInsideZeroToOneHundredAcrossHostileInputs() {
        var starving = perfectDay()
        starving.calories = 200
        var gorging = perfectDay()
        gorging.calories = 9_000
        gorging.carbsG = 1_500; gorging.fatG = 400; gorging.proteinG = 0
        var noWeight = perfectDay()
        noWeight.weightKg = 0
        for i in [perfectDay(), starving, gorging, noWeight, EatingScorer.Inputs()] {
            let r = EatingScorer.compute(i)
            XCTAssertTrue((0...100).contains(r.score), "score \(r.score) escaped 0…100")
        }
    }

    func testNoInputsAtAllReportsUnavailableRatherThanAZeroScore() {
        var empty = EatingScorer.Inputs()
        empty.proteinTargetG = 0     // the last sub-score that can run without any logged data
        let r = EatingScorer.compute(empty)
        XCTAssertFalse(r.available, "an unlogged day must render a placeholder, never a 0/100")
        XCTAssertTrue(r.partial)
        XCTAssertEqual(r.score, 0)
        XCTAssertEqual(r.tdee, 0)
    }

    func testProteinFallsBackToTheFlatTargetWhenWeightIsUnknown() {
        var i = EatingScorer.Inputs()
        i.proteinTargetG = 120
        i.proteinG = 120
        let hit = EatingScorer.compute(i)
        XCTAssertTrue(hit.available)
        XCTAssertEqual(hit.score, 100, "protein was the only sub-score with data, and it was met")

        i.proteinG = 60
        XCTAssertEqual(EatingScorer.compute(i).score, 50)
    }

    // MARK: - Goal-aware calorie fit

    /// A harder-training cutting day: TDEE 2858, so the cut's centre (2458) sits comfortably above
    /// the 1.2·BMR guard rail and the goal shift can be tested without it firing.
    private func cuttingDay() -> EatingScorer.Inputs {
        var i = perfectDay()
        i.goal = "cut"
        i.activeKcal = 900
        return i
    }

    func testCuttingShiftsTheCalorieTargetDownAndBulkingUp() {
        var cut = perfectDay(); cut.goal = "cut"
        var bulk = perfectDay(); bulk.goal = "bulk"
        let maintainAtTDEE = EatingScorer.compute(perfectDay()).score

        // The same 2458 kcal is on target for maintenance but off-centre for a cut and a bulk.
        XCTAssertLessThan(EatingScorer.compute(cut).score, maintainAtTDEE)
        XCTAssertLessThan(EatingScorer.compute(bulk).score, maintainAtTDEE)

        // Eating at the cut's own centre (TDEE − 400) scores better than eating at maintenance.
        var onCut = cuttingDay()
        onCut.proteinG = 2.2 * 80          // cutting raises the protein factor too
        XCTAssertGreaterThan(EatingScorer.compute(onCut).score, EatingScorer.compute(cut).score)
    }

    func testAnAggressiveDeficitBelowBMRIsHalvedNotRewarded() {
        var crash = cuttingDay()
        crash.calories = 1.1 * bmr80kg     // 1958 kcal — under the 1.2·BMR guard rail
        let moderate = cuttingDay()        // 2458 kcal — exactly the cut's centre
        XCTAssertLessThan(EatingScorer.compute(crash).score, EatingScorer.compute(moderate).score)
    }
}
