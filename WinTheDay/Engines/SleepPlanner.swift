import Foundation

/// Recommends tonight's sleep need, bedtime and a dinner cutoff — built on the same strain
/// (`ScoreEngine.strain`) that drives the Sleep score, so "how much sleep do I need" and
/// "how sufficient was last night's sleep" always agree. Pure & deterministic.
enum SleepPlanner {
    struct Plan {
        var needHours: Double
        var recommendedWakeEpoch: Double
        var recommendedBedEpoch: Double
        var dinnerCutoffEpoch: Double
    }

    /// - Parameters:
    ///   - baselineNeedMin: rolling median historical asleep minutes (0 → falls back to 8h).
    ///   - strainS: today's strain S ∈ [0,21] (`ScoreEngine.strain`) — the same value behind the Sleep score.
    ///   - debtMin: capped recent sleep debt in minutes.
    ///   - recentWakeEpochs: recent wake times, used to infer the user's typical wake clock-time.
    ///   - dinnerGapHours: minimum dinner-to-bed gap for good sleep (research: ~3h; reflux-prone ~3.5–4h).
    static func plan(baselineNeedMin: Double, strainS: Double, debtMin: Double,
                      recentWakeEpochs: [Double], dinnerGapHours: Double = 3, referenceNow: Date = Date()) -> Plan {
        let strainAddHours = 1.7 / (1 + exp((17 - strainS) / 3.5))
        let baseHours = baselineNeedMin > 0 ? baselineNeedMin / 60 : 8
        let needHours = baseHours + strainAddHours + min(max(0, debtMin), 120) / 60

        let wakeEpoch = typicalWakeEpoch(recentWakeEpochs, after: referenceNow)
        let bedEpoch = wakeEpoch - needHours * 3600 - 20 * 60
        let dinnerCutoff = bedEpoch - dinnerGapHours * 3600
        return Plan(needHours: needHours, recommendedWakeEpoch: wakeEpoch, recommendedBedEpoch: bedEpoch, dinnerCutoffEpoch: dinnerCutoff)
    }

    /// Median wake clock-time from recent history, projected onto the next occurrence after `now`.
    private static func typicalWakeEpoch(_ wakeEpochs: [Double], after now: Date) -> Double {
        let cal = Calendar.current
        let valid = wakeEpochs.filter { $0 > 0 }
        let minutesOfDay: Double
        if valid.isEmpty {
            minutesOfDay = 7 * 60   // sensible default: 7am
        } else {
            let mins = valid.map { epoch -> Double in
                let c = cal.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: epoch))
                return Double((c.hour ?? 7) * 60 + (c.minute ?? 0))
            }.sorted()
            minutesOfDay = mins[mins.count / 2]
        }
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = Int(minutesOfDay) / 60
        comps.minute = Int(minutesOfDay) % 60
        let today = cal.date(from: comps) ?? now
        let candidate = today > now ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
        return candidate.timeIntervalSince1970
    }
}
