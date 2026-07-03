import Foundation

/// Computes the proprietary Eating score (0–100) from the day's logged nutrition, activity-adjusted
/// calorie balance (Mifflin–St Jeor BMR → TDEE with a resting-day floor), protein/macro/micro coverage,
/// and dinner-to-bed timing. Pure & deterministic — no AI, no I/O. Sub-scores that lack inputs are
/// omitted (not zeroed) and the remaining weights renormalize, matching ScoreEngine's Readiness pattern.
/// See docs/plans/2026-07-improvement-plan.md §4.2 for the formulas and sources.
enum EatingScorer {
    struct Inputs {
        var calories: Double = 0
        var proteinG: Double = 0
        var carbsG: Double = 0
        var fatG: Double = 0
        var microRatios: [Double] = []   // per-nutrient intake/RDA, uncapped; needs ≥5 tracked nutrients to count
        var weightKg: Double = 0
        var heightCm: Double = 170
        var ageYears: Double = 30
        var sexMale: Bool = true
        var activeKcal: Double = 0
        var goal: String = "maintain"    // "maintain" | "cut" | "bulk"
        var proteinTargetG: Double = 120 // fallback when weight is unknown
        var dinnerEpoch: Double = 0
        var referenceBedEpoch: Double = 0 // actual sleep.bedEpoch (past nights) or tonight's recommended bedtime
    }

    struct Result {
        var score: Int
        var available: Bool   // false → no sub-score had enough data (never show a 0)
        var partial: Bool     // true → some sub-scores were omitted; the shown score is renormalized
        var tdee: Double
        var netKcal: Double   // intake − TDEE; feeds the weekly weight projection
    }

    /// Mifflin–St Jeor resting metabolic rate. Returns 0 (unavailable) without a weight.
    static func bmr(weightKg: Double, heightCm: Double, age: Double, male: Bool) -> Double {
        guard weightKg > 0 else { return 0 }
        let base = 10 * weightKg + 6.25 * heightCm - 5 * age
        return max(0, male ? base + 5 : base - 161)
    }

    /// TDEE = BMR + ~10% TEF/NEAT + active energy, floored at 1.15·BMR so a genuine rest day
    /// (activeKcal≈0) never collapses to bare BMR and reads as a false surplus.
    static func tdee(bmr: Double, activeKcal: Double) -> Double {
        guard bmr > 0 else { return 0 }
        return max(bmr * 1.10 + max(0, activeKcal), bmr * 1.15)
    }

    static func compute(_ i: Inputs) -> Result {
        let bmrV = bmr(weightKg: i.weightKg, heightCm: i.heightCm, age: i.ageYears, male: i.sexMale)
        let tdeeV = tdee(bmr: bmrV, activeKcal: i.activeKcal)

        var subs: [(weight: Double, value: Double)] = []
        var partial = false

        if tdeeV > 0, i.calories > 0 {
            let center: Double = i.goal == "cut" ? tdeeV - 400 : (i.goal == "bulk" ? tdeeV + 275 : tdeeV)
            let bandHalf = 0.05 * tdeeV
            let devBeyondBand = max(0, abs(i.calories - center) - bandHalf)
            var calFit = 100 - min(100, 100 * devBeyondBand / (0.35 * tdeeV))
            if i.calories < 1.2 * bmrV { calFit *= 0.5 }   // extra penalty for a too-aggressive deficit
            subs.append((0.29, max(0, calFit)))
        } else { partial = true }

        if i.weightKg > 0 {
            let factor: Double = i.goal == "cut" ? 2.2 : (i.goal == "bulk" ? 2.0 : 1.6)
            subs.append((0.24, min(100, 100 * i.proteinG / max(1, factor * i.weightKg))))
        } else if i.proteinTargetG > 0 {
            subs.append((0.24, min(100, 100 * i.proteinG / i.proteinTargetG)))
        } else { partial = true }

        if i.calories > 0 {
            let carbPct = i.carbsG * 4 / i.calories * 100
            let proteinPct = i.proteinG * 4 / i.calories * 100
            let fatPct = i.fatG * 9 / i.calories * 100
            func amdrFit(_ pct: Double, _ lo: Double, _ hi: Double) -> Double {
                if pct >= lo && pct <= hi { return 100 }
                let dev = pct < lo ? lo - pct : pct - hi
                return max(0, 100 - dev / 15 * 100)
            }
            let macroFit = (amdrFit(carbPct, 45, 65) + amdrFit(proteinPct, 10, 35) + amdrFit(fatPct, 20, 35)) / 3
            subs.append((0.18, macroFit))
        } else { partial = true }

        if i.microRatios.count >= 5 {
            let mar = i.microRatios.map { min(1, $0) }.reduce(0, +) / Double(i.microRatios.count) * 100
            subs.append((0.18, mar))
        } else { partial = true }

        if i.dinnerEpoch > 0, i.referenceBedEpoch > i.dinnerEpoch {
            let gapH = (i.referenceBedEpoch - i.dinnerEpoch) / 3600
            subs.append((0.12, gapH >= 3 ? 100 : max(0, gapH / 3 * 100)))
        } else { partial = true }

        guard !subs.isEmpty else {
            return Result(score: 0, available: false, partial: true, tdee: tdeeV, netKcal: 0)
        }
        let weightSum = subs.reduce(0) { $0 + $1.weight }
        let weighted = subs.reduce(0) { $0 + $1.weight * $1.value } / weightSum
        let netKcal = (tdeeV > 0 && i.calories > 0) ? i.calories - tdeeV : 0
        return Result(score: Int(weighted.rounded()), available: true, partial: partial, tdee: tdeeV, netKcal: netKcal)
    }
}
