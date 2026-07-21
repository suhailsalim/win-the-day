import Foundation

/// Hijri (Umm al-Qura) date helpers for Ramadan mode. Pure Foundation, no I/O, no state — the
/// month is *detected*, never hardcoded, so the app is right every year without a release.
///
/// Moon sighting differs by locality, so every entry point takes `adjustmentDays`: the **Gregorian**
/// date is shifted by that many days before the Hijri conversion. `+1` therefore means "Ramadan
/// started a day earlier here than Umm al-Qura says" (today reads as tomorrow's Hijri date) and
/// `-1` means it started a day later. The UI exposes −1 … +1; a hardcoded calendar is wrong
/// somewhere in the world every single year, so this knob is not optional.
///
/// The Hijri day religiously flips at sunset, but the app's day key is Gregorian `yyyy-MM-dd`
/// throughout. This deliberately keeps everything on the Gregorian key and only *displays*
/// "Ramadan day N" — there is no sunset-keyed data model anywhere in the app.
enum RamadanCalendar {
    /// Ramadan is the 9th month of the Hijri year.
    static let ramadanMonth = 9

    private static func calendars(_ timeZone: TimeZone) -> (hijri: Calendar, gregorian: Calendar) {
        var h = Calendar(identifier: .islamicUmmAlQura)
        h.timeZone = timeZone
        h.locale = Locale(identifier: "en_US_POSIX")
        var g = Calendar(identifier: .gregorian)
        g.timeZone = timeZone
        g.locale = Locale(identifier: "en_US_POSIX")
        return (h, g)
    }

    /// Hijri (year, month, day) for a Gregorian instant, after applying `adjustmentDays`.
    static func hijri(_ date: Date, adjustmentDays: Int = 0,
                      timeZone: TimeZone = .current) -> (year: Int, month: Int, day: Int) {
        let (hijri, gregorian) = calendars(timeZone)
        let shifted = gregorian.date(byAdding: .day, value: adjustmentDays, to: date) ?? date
        let c = hijri.dateComponents([.year, .month, .day], from: shifted)
        return (c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Is this instant inside Ramadan?
    static func isRamadan(_ date: Date, adjustmentDays: Int = 0, timeZone: TimeZone = .current) -> Bool {
        hijri(date, adjustmentDays: adjustmentDays, timeZone: timeZone).month == ramadanMonth
    }

    /// 1…30 during Ramadan, `nil` outside it.
    static func dayNumber(_ date: Date, adjustmentDays: Int = 0, timeZone: TimeZone = .current) -> Int? {
        let h = hijri(date, adjustmentDays: adjustmentDays, timeZone: timeZone)
        guard h.month == ramadanMonth, h.day >= 1 else { return nil }
        return h.day
    }

    /// Hijri year of the instant — the stamp that keeps a once-per-Ramadan action once-per-Ramadan.
    static func hijriYear(_ date: Date, adjustmentDays: Int = 0, timeZone: TimeZone = .current) -> Int {
        hijri(date, adjustmentDays: adjustmentDays, timeZone: timeZone).year
    }

    /// Days of Ramadan left **including today** (1 on the last day); `nil` outside Ramadan.
    /// Counted by walking forward rather than by trusting a fixed 29/30 — Umm al-Qura months are both.
    static func daysRemaining(_ date: Date, adjustmentDays: Int = 0, timeZone: TimeZone = .current) -> Int? {
        guard isRamadan(date, adjustmentDays: adjustmentDays, timeZone: timeZone) else { return nil }
        let (_, gregorian) = calendars(timeZone)
        var count = 0
        for offset in 0..<31 {
            guard let day = gregorian.date(byAdding: .day, value: offset, to: date),
                  isRamadan(day, adjustmentDays: adjustmentDays, timeZone: timeZone) else { break }
            count += 1
        }
        return count
    }
}
