import Foundation

/// Classifies when a prayer was marked against its valid Shari window, so the day's prayer
/// ring can distinguish prompt / on-time / later-but-valid / qadha instead of a flat checkbox.
/// Pure & deterministic — no I/O, no dates other than what's passed in.
///
/// Window sources (see docs/plans/2026-07-improvement-plan.md §4.3 for citations):
///   Fajr:    fajr → sunrise                              qadha after sunrise
///   Dhuhr:   dhuhr → Asr onset                            qadha after Asr onset
///   Asr:     asr → (sunset − 30min); makruh (sunset−30) → sunset;  qadha after sunset
///   Maghrib: sunset → +20min (prompt); +20min → Isha is still fully valid; qadha after Isha
///   Isha:    isha → Islamic midnight (preferred); midnight → next Fajr (permitted); qadha after next Fajr
/// A consistent +90s grace applies to every qadha boundary. "Islamic midnight" is
/// sunset + half the night to next Fajr, not clock midnight.
enum PrayerClassifier {
    private static let graceSeconds: TimeInterval = 90

    /// - Parameters:
    ///   - name: which prayer was marked (must be `.isPrayer`; `.sunrise` always classifies `.unknown`).
    ///   - markedAt: when the user tapped it.
    ///   - today: today's computed prayer times (drives the asr shadow-factor/madhab already baked into `asrTime`).
    ///   - nextFajr: tomorrow's Fajr — needed to bound Isha's permitted window. Pass `nil` when unavailable
    ///     (no location/coordinates yet, or astronomically undefined at extreme latitude); Isha then classifies `.unknown`.
    static func classify(_ name: PrayerTimes.Name, markedAt: Date, today: PrayerTimes, nextFajr: Date?) -> PrayerBand {
        guard name.isPrayer, let start = today[name] else { return .unknown }

        switch name {
        case .fajr:
            guard let sunrise = today[.sunrise] else { return .unknown }
            return band(markedAt, start: start, end: sunrise, qadhaAt: sunrise)

        case .dhuhr:
            guard let asrOnset = today[.asr] else { return .unknown }
            return band(markedAt, start: start, end: asrOnset, qadhaAt: asrOnset)

        case .asr:
            guard let sunset = today[.maghrib] else { return .unknown }
            let makruhStart = sunset.addingTimeInterval(-30 * 60)
            return band(markedAt, start: start, end: makruhStart, makruhEnd: sunset, qadhaAt: sunset)

        case .maghrib:
            guard let sunset = today[.maghrib], let isha = today[.isha] else { return .unknown }
            let promptWindowEnd = sunset.addingTimeInterval(20 * 60)
            return band(markedAt, start: sunset, end: promptWindowEnd, makruhEnd: isha, qadhaAt: isha)

        case .isha:
            guard let nextFajr, let midnight = islamicMidnight(sunset: today[.maghrib], nextFajr: nextFajr) else { return .unknown }
            return band(markedAt, start: start, end: midnight, makruhEnd: nextFajr, qadhaAt: nextFajr)

        case .sunrise:
            return .unknown
        }
    }

    /// Islamic midnight = sunset + half the night to next Fajr (not clock midnight).
    static func islamicMidnight(sunset: Date?, nextFajr: Date?) -> Date? {
        guard let sunset, let nextFajr, nextFajr > sunset else { return nil }
        return sunset.addingTimeInterval(nextFajr.timeIntervalSince(sunset) / 2)
    }

    /// Core banding shared by all five prayers: an on-time window [start, end) with an early
    /// "prompt" sub-window, an optional later-but-still-valid window [end, makruhEnd), and
    /// qadha once `qadhaAt` (+grace) has passed.
    private static func band(_ markedAt: Date, start: Date, end: Date, makruhEnd: Date? = nil, qadhaAt: Date) -> PrayerBand {
        guard markedAt >= start else { return .unknown }   // marked before the window opened — don't penalize, just don't time it
        let windowLen = end.timeIntervalSince(start)
        let promptLen = max(15 * 60, windowLen * 0.20)
        if markedAt < start.addingTimeInterval(promptLen) { return .promptOnTime }
        if markedAt < end { return .onTime }
        if let makruhEnd, markedAt < makruhEnd { return .lateValid }
        if markedAt < qadhaAt.addingTimeInterval(graceSeconds) { return .lateValid }
        return .qadha
    }

    /// Fail-soft day-ring score out of 10: prayers whose window hasn't ended yet and were never
    /// marked are excluded (not due yet); prayers whose window passed unmarked score as qadha (2).
    /// Never a misleading 0 mid-day, never a free 100% before the day is done.
    static func dayScore(prayers: PrayerLog, today: PrayerTimes, nextFajr: Date?, now: Date = Date()) -> (points: Int, outOf: Int) {
        var points = 0, dueCount = 0
        for name in PrayerTimes.Name.allCases where name.isPrayer {
            let key = name.rawValue
            if prayers.isOn(key) {
                points += prayers.band(key).points
                dueCount += 1
                continue
            }
            guard let start = today[name] else { continue }
            let windowPassed: Bool
            switch name {
            case .fajr: windowPassed = (today[.sunrise].map { now >= $0 }) ?? false
            case .dhuhr: windowPassed = (today[.asr].map { now >= $0 }) ?? false
            case .asr: windowPassed = (today[.maghrib].map { now >= $0 }) ?? false
            case .maghrib: windowPassed = (today[.isha].map { now >= $0 }) ?? false
            case .isha:
                windowPassed = nextFajr.map { now >= $0 } ?? false
            case .sunrise: windowPassed = false
            }
            guard now >= start else { continue }   // not due yet — excluded, not counted as a miss
            if windowPassed {
                points += PrayerBand.qadha.points
                dueCount += 1
            }
        }
        return (points, dueCount * 10)
    }
}
