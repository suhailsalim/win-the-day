import XCTest
@testable import AppCore

/// Locks in the contracts `ScoreEngine` is designed around (docs/plans/2026-07-improvement-plan.md §4.1):
/// pure determinism, the ≥7-night calibration gate on Readiness, a clamped monotonic strain, weight
/// renormalization when a sensor is missing, and the bounded self-report multiplier.
final class ScoreEngineTests: XCTestCase {

    // MARK: - Fixtures

    /// A solid, fully-instrumented night: 7h10m asleep with stages, high efficiency.
    private func goodNight() -> SleepBreakdown {
        var s = SleepBreakdown()
        s.asleepMin = 430; s.inBedMin = 470
        s.deepMin = 75; s.remMin = 100; s.coreMin = 255; s.awakeMin = 40
        s.bedEpoch = 1_771_970_000; s.wakeEpoch = 1_771_998_200
        s.efficiency = 430.0 / 470.0
        s.latencyMin = 12
        return s
    }

    /// Baselines past the 7-night gate, with usable HRV / RHR / respiratory spreads.
    private func calibratedBaselines() -> ScoreEngine.Baselines {
        var b = ScoreEngine.Baselines()
        b.lnHrvMean = log(55); b.lnHrvSD = 0.25
        b.rhrMean = 54; b.rhrSD = 3.5
        b.respMean = 14.5; b.respSD = 0.8
        b.sleepNeedBaselineMin = 465
        b.typicalActiveKcal = 520
        b.sampleNights = 21
        return b
    }

    private func calibratedInputs() -> ScoreEngine.Inputs {
        var i = ScoreEngine.Inputs()
        i.sleep = goodNight()
        i.hrvOvernightMedian = 58
        i.restingHR = 53
        i.respiratoryRate = 14.2
        i.priorDaySleepDebtMin = 40
        i.recentMidSleepEpochs = [1_771_800_000, 1_771_886_400, 1_771_972_800]
        i.activeKcal = 640
        i.baselines = calibratedBaselines()
        return i
    }

    private func assertSameResult(_ a: ScoreEngine.Result, _ b: ScoreEngine.Result,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.sleepScore, b.sleepScore, file: file, line: line)
        XCTAssertEqual(a.readiness, b.readiness, file: file, line: line)
        XCTAssertEqual(a.activeScore, b.activeScore, file: file, line: line)
        XCTAssertEqual(a.activeAvailable, b.activeAvailable, file: file, line: line)
        XCTAssertEqual(a.readinessCalibrating, b.readinessCalibrating, file: file, line: line)
        XCTAssertEqual(a.factors.map(\.label), b.factors.map(\.label), file: file, line: line)
        XCTAssertEqual(a.factors.map(\.delta), b.factors.map(\.delta), file: file, line: line)
    }

    // MARK: - Determinism

    func testComputeIsDeterministicForIdenticalInputs() {
        let i = calibratedInputs()
        assertSameResult(ScoreEngine.compute(i), ScoreEngine.compute(i))
        // …and across a fresh, separately-built copy of the same values.
        assertSameResult(ScoreEngine.compute(i), ScoreEngine.compute(calibratedInputs()))
    }

    func testAllScoresStayInsideZeroToOneHundred() {
        var extreme = calibratedInputs()
        extreme.activeKcal = 9_000
        extreme.hrvOvernightMedian = 400
        extreme.restingHR = 30
        for i in [calibratedInputs(), extreme, ScoreEngine.Inputs()] {
            let r = ScoreEngine.compute(i)
            XCTAssertTrue((0...100).contains(r.sleepScore), "sleepScore \(r.sleepScore) out of range")
            XCTAssertTrue((0...100).contains(r.readiness), "readiness \(r.readiness) out of range")
            XCTAssertTrue((0...100).contains(r.activeScore), "activeScore \(r.activeScore) out of range")
        }
    }

    // MARK: - Calibration gate (< 7 nights → sleep-only Readiness)

    func testReadinessReportsCalibratingUnderSevenNights() {
        var i = calibratedInputs()
        i.baselines.sampleNights = 6
        let r = ScoreEngine.compute(i)
        XCTAssertTrue(r.readinessCalibrating)
        XCTAssertEqual(r.readiness, r.sleepScore,
                       "under 7 nights Readiness must fall back to the sleep-only signal")
        XCTAssertTrue(r.factors.contains { $0.label == "Calibrating" })
        XCTAssertFalse(r.factors.contains { $0.label == "HRV" }, "HRV must not be folded in while calibrating")
    }

    func testReadinessIncludesHRVOnceCalibrated() {
        let r = ScoreEngine.compute(calibratedInputs())
        XCTAssertFalse(r.readinessCalibrating)
        XCTAssertTrue(r.factors.contains { $0.label == "HRV" })
        XCTAssertTrue(r.factors.contains { $0.label == "Resting HR" })
        XCTAssertFalse(r.factors.contains { $0.label == "Calibrating" })
    }

    /// Exactly at the boundary: 7 nights is calibrated, 6 is not.
    func testSevenNightsIsTheCalibrationBoundary() {
        var i = calibratedInputs()
        i.baselines.sampleNights = 7
        XCTAssertFalse(ScoreEngine.compute(i).readinessCalibrating)
        i.baselines.sampleNights = 6
        XCTAssertTrue(ScoreEngine.compute(i).readinessCalibrating)
    }

    /// Calibrated nights alone aren't enough — without an HRV sample there is nothing to z-score.
    func testCalibratedButHRVlessStillFallsBackToSleepOnly() {
        var i = calibratedInputs()
        i.hrvOvernightMedian = 0
        let r = ScoreEngine.compute(i)
        XCTAssertEqual(r.readiness, r.sleepScore)
        XCTAssertFalse(r.readinessCalibrating, "the flag tracks the baseline sample count, not the sample")
    }

    // MARK: - Strain

    func testStrainIsMonotonicAndClampedToTwentyOne() {
        var previous = -1.0
        for kcal in stride(from: 0.0, through: 12_000.0, by: 250.0) {
            let s = ScoreEngine.strain(activeKcal: kcal, typicalActiveKcal: 520)
            XCTAssertGreaterThanOrEqual(s, previous, "strain dipped at \(kcal) kcal")
            XCTAssertTrue((0...21).contains(s), "strain \(s) escaped [0,21] at \(kcal) kcal")
            previous = s
        }
        XCTAssertEqual(ScoreEngine.strain(activeKcal: 1_000_000, typicalActiveKcal: 520), 21, accuracy: 0.0001)
    }

    func testStrainFallsBackToFourHundredWhenTypicalIsUnknown() {
        XCTAssertEqual(ScoreEngine.strain(activeKcal: 400, typicalActiveKcal: 0),
                       ScoreEngine.strain(activeKcal: 400, typicalActiveKcal: 400), accuracy: 0.0001)
        // A rest day sits at the 6.0 anchor, never below it.
        XCTAssertEqual(ScoreEngine.strain(activeKcal: 0, typicalActiveKcal: 0), 6, accuracy: 0.0001)
        XCTAssertEqual(ScoreEngine.strain(activeKcal: -500, typicalActiveKcal: 520), 6, accuracy: 0.0001)
    }

    func testActiveScoreRisesWithActiveEnergyAndIsUnavailableAtZero() {
        var i = calibratedInputs()
        i.activeKcal = 0
        let rest = ScoreEngine.compute(i)
        XCTAssertFalse(rest.activeAvailable, "0 kcal means no data — the ring shows a placeholder, not a 0")
        XCTAssertEqual(rest.activeScore, 0)

        i.activeKcal = 300
        let light = ScoreEngine.compute(i)
        i.activeKcal = 1_200
        let hard = ScoreEngine.compute(i)
        XCTAssertTrue(light.activeAvailable)
        XCTAssertGreaterThan(hard.activeScore, light.activeScore)
    }

    // MARK: - Missing sub-inputs renormalize rather than zeroing

    func testMissingRestingHRRenormalizesInsteadOfScoringZero() {
        var i = calibratedInputs()
        i.restingHR = 0
        i.respiratoryRate = 0
        let r = ScoreEngine.compute(i)
        XCTAssertGreaterThan(r.readiness, 0, "a dropped sub-input must not collapse Readiness to 0")
        XCTAssertFalse(r.factors.contains { $0.label == "Resting HR" })

        // With only the HRV + sleep sub-scores left, the weights renormalize to sum to 1 — so an
        // above-baseline HRV still reads above the midpoint rather than being diluted toward zero.
        XCTAssertGreaterThan(r.readiness, 50)
    }

    func testMissingBaselineSpreadIsTreatedAsNoBaseline() {
        var i = calibratedInputs()
        i.baselines.lnHrvSD = 0          // a flat/degenerate baseline would divide by zero
        let r = ScoreEngine.compute(i)
        XCTAssertEqual(r.readiness, r.sleepScore)
        XCTAssertFalse(r.factors.contains { $0.label == "HRV" })
    }

    func testSleepWithoutStagesRedistributesTheStageWeight() {
        var i = calibratedInputs()
        var stageless = goodNight()
        stageless.deepMin = 0; stageless.remMin = 0; stageless.coreMin = 0
        i.sleep = stageless
        let r = ScoreEngine.compute(i)
        XCTAssertGreaterThan(r.sleepScore, 0)
        XCTAssertTrue((0...100).contains(r.sleepScore))
        XCTAssertFalse(r.factors.contains { $0.label == "Deep + REM" })
    }

    func testNoSleepDataReturnsZeroesWithAnExplanation() {
        var i = ScoreEngine.Inputs()
        i.activeKcal = 500
        let r = ScoreEngine.compute(i)
        XCTAssertEqual(r.sleepScore, 0)
        XCTAssertEqual(r.readiness, 0)
        XCTAssertTrue(r.activeAvailable)
        XCTAssertEqual(r.factors.first?.label, "Sleep")
    }

    // MARK: - Self-report multiplier

    func testSelfReportMultiplierIsFlooredAtZeroPointEightFive() {
        let clean = ScoreEngine.compute(calibratedInputs())

        var worst = calibratedInputs()
        worst.checkIn = DayCheckIn()
        worst.checkIn.alcohol = 3
        worst.checkIn.illness = true
        worst.checkIn.lateCaffeine = true
        worst.checkIn.soreness = 3
        worst.checkIn.stress = 3
        let penalized = ScoreEngine.compute(worst)

        // Every penalty maxed multiplies out to ~0.73, which the floor clamps back to exactly 0.85.
        let expected = 0.85 * Double(clean.readiness)
        XCTAssertEqual(Double(penalized.readiness), expected, accuracy: 1.0,
                       "the check-in must never move Readiness by more than 15%")
        XCTAssertLessThan(penalized.readiness, clean.readiness)
        XCTAssertTrue(penalized.factors.contains { $0.label == "Check-in" },
                      "a penalising check-in must be explained in the factor breakdown")
    }

    func testAMildCheckInPenalizesLessThanASevereOne() {
        var mild = calibratedInputs()
        mild.checkIn.alcohol = 1
        var severe = calibratedInputs()
        severe.checkIn.alcohol = 3
        severe.checkIn.stress = 3
        let clean = ScoreEngine.compute(calibratedInputs()).readiness
        let mildR = ScoreEngine.compute(mild).readiness
        let severeR = ScoreEngine.compute(severe).readiness
        XCTAssertLessThanOrEqual(mildR, clean)
        XCTAssertLessThan(severeR, mildR)
    }

    /// The check-in only sharpens the HRV-based score; while calibrating it must not apply at all.
    func testCheckInDoesNotApplyWhileCalibrating() {
        var i = calibratedInputs()
        i.baselines.sampleNights = 3
        let clean = ScoreEngine.compute(i)
        i.checkIn.alcohol = 3
        i.checkIn.illness = true
        XCTAssertEqual(ScoreEngine.compute(i).readiness, clean.readiness)
    }

    // MARK: - The legacy shim still delegates here

    func testReadinessScorerShimMatchesTheUncalibratedEngine() {
        var legacy = ReadinessScorer.Inputs()
        legacy.sleep = goodNight()
        legacy.priorActiveKcal = 640
        legacy.typicalActiveKcal = 520
        let shim = ReadinessScorer.compute(legacy)

        var direct = ScoreEngine.Inputs()
        direct.sleep = goodNight()
        direct.activeKcal = 640
        direct.baselines.typicalActiveKcal = 520
        let engine = ScoreEngine.compute(direct)

        XCTAssertEqual(shim.readiness, engine.readiness)
        XCTAssertEqual(shim.sleepScore, engine.sleepScore)
    }
}
