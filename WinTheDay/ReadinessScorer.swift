import Foundation

/// Computes a 0–100 Readiness score (with a sleep sub-score) on top of Apple Health,
/// fusing sleep, HRV, resting HR, prior-day load and late meals.
enum ReadinessScorer {
    struct Inputs {
        var sleep: SleepBreakdown?
        var hrv: Double = 0
        var restingHR: Double = 0
        var hrvBaseline: Double = 0       // rolling avg (0 = unknown → skip)
        var rhrBaseline: Double = 0
        var priorActiveKcal: Double = 0   // yesterday's active energy
        var typicalActiveKcal: Double = 0 // rolling avg active energy
        var dinnerEpoch: Double = 0       // last night's dinner time
        var sleepTargetHours: Double = 7.5
    }

    struct Result { var readiness: Int; var sleepScore: Int; var factors: [ReadinessFactor] }

    static func compute(_ i: Inputs) -> Result {
        var factors: [ReadinessFactor] = []

        // ---- Sleep sub-score ----
        guard let s = i.sleep, s.asleepMin > 0 else {
            return Result(readiness: 0, sleepScore: 0,
                          factors: [ReadinessFactor("Sleep", 0, "No sleep data recorded last night.")])
        }
        let durRatio = min(1.2, s.asleepHours / max(4, i.sleepTargetHours))
        let durScore = min(1, durRatio)                       // 0–1
        let effScore = s.inBedMin > 0 ? s.efficiency : 0.9    // assume good if unknown
        let stageScore: Double
        if s.hasStages {
            let restorative = (s.deepMin + s.remMin) / max(1, s.asleepMin)   // ideal ~0.4
            stageScore = min(1, restorative / 0.4)
        } else {
            stageScore = -1   // sentinel: no stages
        }
        var sleep100: Double
        if stageScore < 0 {
            sleep100 = (durScore * 0.7 + effScore * 0.3) * 100
        } else {
            sleep100 = (durScore * 0.5 + effScore * 0.2 + stageScore * 0.3) * 100
        }
        sleep100 = max(0, min(100, sleep100))
        let sleepScore = Int(sleep100.rounded())

        factors.append(ReadinessFactor("Sleep duration",
            Int(((durScore - 0.85) * 30).rounded()),
            String(format: "%.1fh asleep vs %.1fh target", s.asleepHours, i.sleepTargetHours)))
        if s.hasStages {
            let pct = Int(((s.deepMin + s.remMin) / max(1, s.asleepMin) * 100).rounded())
            factors.append(ReadinessFactor("Deep + REM", 0, "\(pct)% restorative sleep"))
        }
        if s.inBedMin > 0 {
            factors.append(ReadinessFactor("Efficiency", 0, "\(Int((s.efficiency * 100).rounded()))% time asleep in bed"))
        }

        // ---- Readiness = sleep base + physiology + behaviour ----
        var readiness = sleep100

        if i.hrv > 0 && i.hrvBaseline > 0 {
            let ratio = i.hrv / i.hrvBaseline
            let delta = Int((max(-1, min(1, (ratio - 1) / 0.25)) * 12).rounded())   // ±12
            readiness += Double(delta)
            factors.append(ReadinessFactor("HRV", delta,
                String(format: "%d ms vs %d baseline", Int(i.hrv), Int(i.hrvBaseline))))
        }
        if i.restingHR > 0 && i.rhrBaseline > 0 {
            let diff = i.restingHR - i.rhrBaseline           // lower is better
            let delta = Int((max(-1, min(1, -diff / 6)) * 8).rounded())            // ±8
            readiness += Double(delta)
            factors.append(ReadinessFactor("Resting HR", delta,
                String(format: "%d bpm vs %d baseline", Int(i.restingHR), Int(i.rhrBaseline))))
        }
        if i.priorActiveKcal > 0 && i.typicalActiveKcal > 0 && i.priorActiveKcal > i.typicalActiveKcal * 1.4 {
            readiness -= 6
            factors.append(ReadinessFactor("Yesterday's load", -6, "High training load — prioritise recovery."))
        }
        if i.dinnerEpoch > 0, let bed = i.sleep?.bedEpoch, bed > 0 {
            let gapH = (bed - i.dinnerEpoch) / 3600
            if gapH >= 0 && gapH < 2 {
                readiness -= 6
                factors.append(ReadinessFactor("Late dinner", -6,
                    String(format: "Ate ~%.1fh before bed", gapH)))
            }
        }

        return Result(readiness: max(0, min(100, Int(readiness.rounded()))),
                      sleepScore: sleepScore, factors: factors)
    }
}
