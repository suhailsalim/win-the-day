import Foundation

/// Thin backward-compatible shim over `ScoreEngine` (the WHOOP-style Sleep/Readiness/Active engine
/// in ScoreEngine.swift). Kept so any code still using the old, simpler `ReadinessScorer` API
/// continues to compile; new call sites should use `ScoreEngine.compute` directly for the full
/// feature set (overnight-median HRV, respiratory rate, self-report check-in, Active score).
enum ReadinessScorer {
    struct Inputs {
        var sleep: SleepBreakdown?
        var hrv: Double = 0
        var restingHR: Double = 0
        var hrvBaseline: Double = 0       // rolling avg ms (0 = unknown → skip)
        var rhrBaseline: Double = 0
        var priorActiveKcal: Double = 0   // yesterday's active energy
        var typicalActiveKcal: Double = 0 // rolling avg active energy
        var dinnerEpoch: Double = 0       // last night's dinner time (unused by ScoreEngine; kept for source compat)
        var sleepTargetHours: Double = 7.5
    }

    struct Result { var readiness: Int; var sleepScore: Int; var factors: [ReadinessFactor] }

    static func compute(_ i: Inputs) -> Result {
        // Legacy baselines are plain ms/bpm averages, not ScoreEngine's ln/z-score baselines, so we
        // can't safely translate them into a `calibrated` state — fall back to the sleep-only signal.
        let engineInputs = ScoreEngine.Inputs(
            sleep: i.sleep,
            hrvOvernightMedian: 0,
            restingHR: 0,
            respiratoryRate: 0,
            priorDaySleepDebtMin: 0,
            recentMidSleepEpochs: [],
            activeKcal: i.priorActiveKcal,
            checkIn: DayCheckIn(),
            baselines: ScoreEngine.Baselines(typicalActiveKcal: i.typicalActiveKcal, sampleNights: 0))
        let r = ScoreEngine.compute(engineInputs)
        return Result(readiness: r.readiness, sleepScore: r.sleepScore, factors: r.factors)
    }
}
