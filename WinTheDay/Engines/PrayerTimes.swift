import Foundation

/// Self-contained prayer-time calculator (port of the standard PrayTimes astronomical algorithm).
/// Supports configurable Fajr/Isha twilight angles and Hanafi/Shafi Asr.
struct PrayerTimes {
    enum Name: String, CaseIterable, Identifiable {
        case fajr, sunrise, dhuhr, asr, maghrib, isha
        var id: String { rawValue }
        var label: String {
            switch self {
            case .fajr: return "Fajr"
            case .sunrise: return "Sunrise"
            case .dhuhr: return "Dhuhr"
            case .asr: return "Asr"
            case .maghrib: return "Maghrib"
            case .isha: return "Isha"
            }
        }
        /// On Friday the congregational prayer replaces Dhuhr for those it is obligatory on, so the
        /// slot is *named* differently. Nothing else changes: it occupies the same window and is
        /// still recorded under the `dhuhr` key, so history, streaks and scoring are untouched.
        func label(jumuah: Bool) -> String {
            (jumuah && self == .dhuhr) ? "Jumu'ah" : label
        }

        var isPrayer: Bool { self != .sunrise }
    }

    /// Is `date` a Friday? Takes the calendar so a caller with a fixed time zone (the notification
    /// scheduler builds one) agrees with what the user sees on screen.
    static func isFriday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.weekday, from: date) == 6   // Gregorian: 1 = Sunday … 6 = Friday
    }

    let times: [Name: Date]

    subscript(_ n: Name) -> Date? { times[n] }

    /// Ordered (name, date) pairs.
    var ordered: [(Name, Date)] {
        Name.allCases.compactMap { n in times[n].map { (n, $0) } }
    }

    // MARK: - Calculation

    static func calculate(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone,
                          fajrAngle: Double, ishaAngle: Double, asrFactor: Double) -> PrayerTimes {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 2026, month = comps.month ?? 1, day = comps.day ?? 1
        let tzOffset = Double(timeZone.secondsFromGMT(for: date)) / 3600.0

        let jDate = julian(year, month, day) - longitude / (15.0 * 24.0)

        // Initial guesses (hours) → day fractions
        func portion(_ h: Double) -> Double { h / 24.0 }

        func sun(_ t: Double) -> (decl: Double, eqt: Double) { sunPosition(jDate + t) }
        func midDay(_ t: Double) -> Double { fixHour(12 - sun(t).eqt) }
        func sunAngleTime(_ angle: Double, _ t: Double, ccw: Bool) -> Double {
            let decl = sun(t).decl
            let numerator = -dsin(angle) - dsin(decl) * dsin(latitude)
            let denominator = dcos(decl) * dcos(latitude)
            let h = darccos(numerator / denominator) / 15.0
            return midDay(t) + (ccw ? -h : h)
        }
        func asrTime(_ factor: Double, _ t: Double) -> Double {
            let decl = sun(t).decl
            let angle = -darccot(factor + dtan(abs(latitude - decl)))
            return sunAngleTime(angle, t, ccw: false)
        }

        let riseSet = 0.833
        var fajr = sunAngleTime(fajrAngle, portion(5), ccw: true)
        var sunrise = sunAngleTime(riseSet, portion(6), ccw: true)
        var dhuhr = midDay(portion(12))
        var asr = asrTime(asrFactor, portion(13))
        var maghrib = sunAngleTime(riseSet, portion(18), ccw: false)
        var isha = sunAngleTime(ishaAngle, portion(18), ccw: false)

        // Convert solar hours → local clock
        let adjust = tzOffset - longitude / 15.0
        fajr = fixHour(fajr + adjust)
        sunrise = fixHour(sunrise + adjust)
        dhuhr = fixHour(dhuhr + adjust)
        asr = fixHour(asr + adjust)
        maghrib = fixHour(maghrib + adjust)
        isha = fixHour(isha + adjust)

        func makeDate(_ hours: Double) -> Date {
            let totalMinutes = Int((hours * 60).rounded())
            var c = DateComponents()
            c.year = year; c.month = month; c.day = day
            c.hour = totalMinutes / 60
            c.minute = totalMinutes % 60
            return cal.date(from: c) ?? date
        }

        return PrayerTimes(times: [
            .fajr: makeDate(fajr),
            .sunrise: makeDate(sunrise),
            .dhuhr: makeDate(dhuhr),
            .asr: makeDate(asr),
            .maghrib: makeDate(maghrib),
            .isha: makeDate(isha)
        ])
    }

    // MARK: - Astronomy helpers (degrees)

    private static func sunPosition(_ jd: Double) -> (decl: Double, eqt: Double) {
        let D = jd - 2451545.0
        let g = fixAngle(357.529 + 0.98560028 * D)
        let q = fixAngle(280.459 + 0.98564736 * D)
        let L = fixAngle(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g))
        let e = 23.439 - 0.00000036 * D
        let RA = darctan2(dcos(e) * dsin(L), dcos(L)) / 15.0
        let eqt = q / 15.0 - fixHour(RA)
        let decl = darcsin(dsin(e) * dsin(L))
        return (decl, eqt)
    }

    private static func julian(_ year: Int, _ month: Int, _ day: Int) -> Double {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let A = floor(Double(y) / 100.0)
        let B = 2 - A + floor(A / 4.0)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(day) + B - 1524.5
    }

    private static func dtr(_ d: Double) -> Double { d * .pi / 180 }
    private static func rtd(_ r: Double) -> Double { r * 180 / .pi }
    private static func dsin(_ d: Double) -> Double { sin(dtr(d)) }
    private static func dcos(_ d: Double) -> Double { cos(dtr(d)) }
    private static func dtan(_ d: Double) -> Double { tan(dtr(d)) }
    private static func darcsin(_ x: Double) -> Double { rtd(asin(x)) }
    private static func darccos(_ x: Double) -> Double { rtd(acos(min(1, max(-1, x)))) }
    private static func darctan2(_ y: Double, _ x: Double) -> Double { rtd(atan2(y, x)) }
    private static func darccot(_ x: Double) -> Double { rtd(atan2(1, x)) }
    private static func fixAngle(_ a: Double) -> Double { let r = a.truncatingRemainder(dividingBy: 360); return r < 0 ? r + 360 : r }
    private static func fixHour(_ a: Double) -> Double { let r = a.truncatingRemainder(dividingBy: 24); return r < 0 ? r + 24 : r }
}
