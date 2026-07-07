import Foundation

/// Computes the three WHOOP-style daily scores — Sleep, Readiness (recovery), Active (strain) —
/// as pure functions of Apple Health signals + rolling baselines + an optional self-report check-in.
/// No network, no persistence: callers gather `Inputs` (HealthManager + local entry history) and
/// cache the `Result` on `Entry`. See docs/plans/2026-07-improvement-plan.md §4.1 for the formulas
/// and their sources (WHOOP developer docs, HRV log-normal literature).
enum ScoreEngine {

    /// Rolling personal baselines. `sampleNights` gates whether Readiness includes HRV/RHR at all —
    /// under 7 nights the z-scores are too noisy, so Readiness falls back to the sleep-only signal.
    struct Baselines {
        var lnHrvMean: Double = 0
        var lnHrvSD: Double = 0
        var rhrMean: Double = 0
        var rhrSD: Double = 0
        var respMean: Double = 0
        var respSD: Double = 0
        var sleepNeedBaselineMin: Double = 0   // rolling median of historical asleepMin (0 → fall back to 480)
        var typicalActiveKcal: Double = 0      // rolling median of historical daily active energy (0 → fall back to 400)
        var sampleNights: Int = 0
        var calibrated: Bool { sampleNights >= 7 }
    }

    struct Inputs {
        var sleep: SleepBreakdown?
        var hrvOvernightMedian: Double = 0     // ms SDNN, 0 = unknown
        var restingHR: Double = 0              // bpm, 0 = unknown
        var respiratoryRate: Double = 0        // breaths/min, 0 = unknown
        var priorDaySleepDebtMin: Double = 0   // capped sum of the last 3 nights' deficits vs their own need
        var recentMidSleepEpochs: [Double] = [] // up to the last 4 nights' mid-sleep epochs, for Consistency
        var activeKcal: Double = 0             // the relevant day's active energy (drives strain S)
        var checkIn = DayCheckIn()
        var baselines = Baselines()
    }

    struct Result {
        var sleepScore: Int
        var readiness: Int
        var activeScore: Int
        var activeAvailable: Bool
        var readinessCalibrating: Bool   // true while baselines.sampleNights < 7
        var factors: [ReadinessFactor]
    }

    /// Single strain source of truth, S ∈ [0,21]. Derived from active-energy alone so it's always
    /// computable from an iPhone (no Watch required); both Active and Sleep-Need consume this value.
    static func strain(activeKcal: Double, typicalActiveKcal: Double) -> Double {
        let typical = typicalActiveKcal > 0 ? typicalActiveKcal : 400
        let s = 6 + 8 * log2(1 + max(0, activeKcal) / typical)
        return min(21, max(0, s))
    }

    static func compute(_ i: Inputs) -> Result {
        var factors: [ReadinessFactor] = []

        guard let sleep = i.sleep, sleep.asleepMin > 0 else {
            return Result(sleepScore: 0, readiness: 0, activeScore: 0, activeAvailable: i.activeKcal > 0,
                          readinessCalibrating: !i.baselines.calibrated,
                          factors: [ReadinessFactor("Sleep", 0, "No sleep data recorded last night.")])
        }

        // ---- Sleep (0–100) ----
        let S = strain(activeKcal: i.activeKcal, typicalActiveKcal: i.baselines.typicalActiveKcal)
        let strainAddMin = 60 * 1.7 / (1 + exp((17 - S) / 3.5))
        let baselineNeedMin = i.baselines.sleepNeedBaselineMin > 0 ? i.baselines.sleepNeedBaselineMin : 480
        let sleepNeedMin = baselineNeedMin + strainAddMin + min(i.priorDaySleepDebtMin, 120)

        let sufficiency = min(100, 100 * sleep.asleepMin / max(1, sleepNeedMin))
        let efficiency = sleep.inBedMin > 0 ? sleep.efficiency * 100 : 90
        let consistency = consistencyScore(i.recentMidSleepEpochs)
        let stageQuality: Double? = sleep.hasStages
            ? min(100, 100 * ((sleep.deepMin + sleep.remMin) / max(1, sleep.asleepMin)) / 0.40)
            : nil

        var sleep100: Double
        if let stageQuality {
            sleep100 = 0.50 * sufficiency + 0.20 * efficiency + 0.20 * consistency + 0.10 * stageQuality
        } else {
            let norm = 0.90   // redistribute the 0.10 stage-quality weight when stages aren't recorded
            sleep100 = (0.50 * sufficiency + 0.20 * efficiency + 0.20 * consistency) / norm
        }
        sleep100 = max(0, min(100, sleep100))
        let sleepScore = Int(sleep100.rounded())

        factors.append(ReadinessFactor("Sleep need", Int((sufficiency - 85).rounded()),
            String(format: "%.1fh asleep vs %.1fh needed", sleep.asleepHours, sleepNeedMin / 60)))
        if sleep.hasStages {
            let pct = Int(((sleep.deepMin + sleep.remMin) / max(1, sleep.asleepMin) * 100).rounded())
            factors.append(ReadinessFactor("Deep + REM", 0, "\(pct)% restorative sleep"))
        }
        if sleep.inBedMin > 0 {
            factors.append(ReadinessFactor("Efficiency", 0, "\(Int(efficiency.rounded()))% time asleep in bed"))
        }

        // ---- Readiness (0–100): HRV-dominant, baseline-relative; falls back to sleep-only until calibrated ----
        var readiness: Double
        if i.baselines.calibrated, i.hrvOvernightMedian > 0, i.baselines.lnHrvSD > 0 {
            let hrvZ = (log(i.hrvOvernightMedian) - i.baselines.lnHrvMean) / i.baselines.lnHrvSD
            var subs: [(weight: Double, value: Double)] = [(0.55, sigmoid(hrvZ)), (0.10, sleep100 / 100)]
            factors.append(ReadinessFactor("HRV", Int(((sigmoid(hrvZ) - 0.5) * 30).rounded()),
                String(format: "%.0f ms overnight median", i.hrvOvernightMedian)))

            if i.restingHR > 0, i.baselines.rhrSD > 0 {
                let rhrZ = (i.restingHR - i.baselines.rhrMean) / i.baselines.rhrSD
                subs.append((0.25, sigmoid(-rhrZ)))
                factors.append(ReadinessFactor("Resting HR", Int(((sigmoid(-rhrZ) - 0.5) * 20).rounded()),
                    String(format: "%.0f bpm vs %.0f baseline", i.restingHR, i.baselines.rhrMean)))
            }
            if i.respiratoryRate > 0, i.baselines.respSD > 0 {
                let respZ = (i.respiratoryRate - i.baselines.respMean) / i.baselines.respSD
                subs.append((0.05, sigmoid(-respZ)))
            }
            let weightSum = subs.reduce(0) { $0 + $1.weight }
            let weighted = subs.reduce(0) { $0 + $1.weight * $1.value } / weightSum

            let mult = selfReportMultiplier(i.checkIn)
            readiness = 100 * weighted * mult
            if mult < 1 {
                factors.append(ReadinessFactor("Check-in", Int(((mult - 1) * 100).rounded()),
                    "Alcohol, late caffeine, illness or soreness noted today."))
            }
        } else {
            readiness = sleep100   // sensor-only fallback until ≥7 calibrated nights
            let remaining = max(0, 7 - i.baselines.sampleNights)
            if remaining > 0 {
                factors.append(ReadinessFactor("Calibrating", 0,
                    "Readiness needs \(remaining) more night\(remaining == 1 ? "" : "s") of data to include HRV/RHR."))
            }
        }
        readiness = max(0, min(100, readiness))

        // ---- Active (0–100): log-saturating strain, always available from active-energy alone ----
        let activeAvailable = i.activeKcal > 0
        let activeScore = activeAvailable ? Int((100 * (1 - exp(-S / 10.5))).rounded()) : 0

        return Result(sleepScore: sleepScore, readiness: Int(readiness.rounded()),
                      activeScore: activeScore, activeAvailable: activeAvailable,
                      readinessCalibrating: !i.baselines.calibrated, factors: factors)
    }

    private static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    /// MAD-based consistency of mid-sleep time across the last few nights, anchored at 6pm so an
    /// overnight mid-sleep near clock-midnight never wraps around and produces a spurious deviation.
    private static func consistencyScore(_ midSleepEpochs: [Double]) -> Double {
        let valid = midSleepEpochs.filter { $0 > 0 }
        guard valid.count >= 2 else { return 100 }   // not enough history — don't penalize
        let cal = Calendar.current
        let anchored: [Double] = valid.map { epoch in
            let comps = cal.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: epoch))
            var h = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
            if h < 18 { h += 24 }
            return h * 60
        }
        let mean = anchored.reduce(0, +) / Double(anchored.count)
        let mad = anchored.map { abs($0 - mean) }.reduce(0, +) / Double(anchored.count)
        return max(0, 100 - min(120, mad) / 120 * 100)
    }

    /// Bounded self-report multiplier — sharpens Readiness but never dominates it (floor 0.85).
    private static func selfReportMultiplier(_ c: DayCheckIn) -> Double {
        var mult = 1.0
        if c.alcohol >= 2 { mult *= 0.93 } else if c.alcohol == 1 { mult *= 0.96 }
        if c.lateCaffeine { mult *= 0.96 }
        if c.illness { mult *= 0.95 }
        mult -= 0.02 * Double(c.soreness)
        mult -= 0.02 * Double(c.stress)
        return max(0.85, mult)
    }
}
