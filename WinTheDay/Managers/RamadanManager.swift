import Foundation
@preconcurrency import UserNotifications

/// One scheduled `ramadan-` local notification. File-scope (not nested in the `@MainActor` class)
/// so it is plainly `Sendable` and can cross into the notification-centre closures.
private struct RamadanNote: Sendable {
    let id: String
    let fire: Date
    let title: String
    let body: String
}

/// Ramadan mode — the month-long mode, not a daily toggle.
///
/// Owns the auto-detected dates (`RamadanCalendar`, Umm al-Qura ± a moon-sighting adjustment), the
/// suhoor/iftar boundaries (always the **computed** Fajr/Maghrib from `PrayerManager` — never a
/// hardcoded clock time), the `ramadan-` notification set, and the optional auto-fast that drives
/// `FastingManager`. Owns its `ramadan_*` UserDefaults keys and is injected in `WinTheDayApp`
/// (AGENTS.md convention 3).
///
/// Notification prefixes are one-per-concern (convention 6): `ramadan-` is entirely this manager's
/// — `PrayerManager` no longer schedules under it, because both clearing the same prefix would have
/// meant whichever ran last silently wiped the other's requests.
@MainActor
final class RamadanManager: ObservableObject {
    /// How Ramadan is decided. `.auto` is the point of the feature; `.on`/`.off` are the manual escape
    /// hatches (a local sighting the calendar disagrees with, or a user who doesn't want the mode).
    enum Mode: String, CaseIterable {
        case auto, on, off
        var label: String {
            switch self {
            case .auto: return "Automatic"
            case .on: return "Always on"
            case .off: return "Off"
            }
        }
    }

    @Published private(set) var mode: Mode
    /// −1 … +1 days. See `RamadanCalendar` for the sign convention.
    @Published private(set) var dayAdjustment: Int
    @Published private(set) var autoFast: Bool
    @Published private(set) var suhoorLeadMinutes: Int
    @Published private(set) var preIftarReminder: Bool
    /// Gregorian `yyyy-MM-dd` keys the user marked "not fasting today" (travel, illness, menses).
    @Published private(set) var skippedDays: [String]

    // Weak so the manager graph stays acyclic; both are `@StateObject`s owned by `WinTheDayApp`.
    private weak var prayer: PrayerManager?
    private weak var fasting: FastingManager?

    private let d = UserDefaults.standard
    private let notePrefix = "ramadan-"
    private let preIftarLeadMinutes = 10
    /// iOS caps the whole app at 64 pending local notifications — 5 days × 3 keeps us well inside it.
    private let scheduleDays = 5
    private let autoFastDayKey = "ramadan_autofast_day"
    private let seededYearKey = "ramadan_seeded_year"
    private var lastScheduleSync: Date?

    init() {
        mode = Mode(rawValue: d.string(forKey: "ramadan_mode") ?? "") ?? .auto
        dayAdjustment = min(1, max(-1, d.object(forKey: "ramadan_adjust") as? Int ?? 0))
        autoFast = d.object(forKey: "ramadan_autofast") as? Bool ?? true
        suhoorLeadMinutes = min(90, max(5, d.object(forKey: "ramadan_suhoor_lead") as? Int ?? 30))
        preIftarReminder = d.object(forKey: "ramadan_pre_iftar") as? Bool ?? true
        skippedDays = d.stringArray(forKey: "ramadan_skips") ?? []
    }

    private func persist() {
        d.set(mode.rawValue, forKey: "ramadan_mode")
        d.set(dayAdjustment, forKey: "ramadan_adjust")
        d.set(autoFast, forKey: "ramadan_autofast")
        d.set(suhoorLeadMinutes, forKey: "ramadan_suhoor_lead")
        d.set(preIftarReminder, forKey: "ramadan_pre_iftar")
        d.set(skippedDays, forKey: "ramadan_skips")
    }

    // MARK: - Wiring

    /// Hand the manager the two peers it drives. Called once from `WinTheDayApp`.
    func attach(prayer: PrayerManager, fasting: FastingManager) {
        self.prayer = prayer
        self.fasting = fasting
        refresh(force: true)
    }

    /// Re-derive everything: mirror the mode onto `PrayerManager` (which gates the widget snapshot
    /// and the existing fasting-card header), rebuild the `ramadan-` set, reconcile the auto-fast.
    /// Rescheduling is debounced to once every 5 minutes so the Today module's ticker is free to
    /// call this every minute; `force` is for settings changes and for foregrounding.
    func refresh(force: Bool = false) {
        let active = isActiveToday
        if let prayer, prayer.ramadanMode != active { prayer.setRamadan(active) }
        if force || lastScheduleSync.map({ Date().timeIntervalSince($0) >= 300 }) ?? true {
            lastScheduleSync = Date()
            scheduleNotifications()
        }
        reconcileFast()
    }

    // MARK: - Dates

    func isActive(on date: Date) -> Bool {
        switch mode {
        case .on: return true
        case .off: return false
        case .auto: return RamadanCalendar.isRamadan(date, adjustmentDays: dayAdjustment)
        }
    }

    var isActiveToday: Bool { isActive(on: Date()) }

    /// Ramadan day 1…30. `nil` when the calendar says we're outside Ramadan (which includes
    /// `.on` mode used out of season — then there is simply no day number to show).
    var dayNumber: Int? { RamadanCalendar.dayNumber(Date(), adjustmentDays: dayAdjustment) }
    var daysRemaining: Int? { RamadanCalendar.daysRemaining(Date(), adjustmentDays: dayAdjustment) }

    /// Suhoor ends at the computed Fajr; iftar is the computed Maghrib. Both are `nil` until a
    /// location is known — Ramadan mode then degrades to a manual fast rather than inventing times.
    var suhoorEnd: Date? { prayer?.suhoorEnd }
    var iftar: Date? { prayer?.iftar }
    /// Tomorrow's Fajr — what an *evening* suhoor countdown must point at (the classic off-by-one).
    var nextSuhoorEnd: Date? { prayer?.nextFajr }
    var hasComputedTimes: Bool { suhoorEnd != nil && iftar != nil }

    /// Are we inside today's fasting window right now?
    func inFastingWindow(_ now: Date = Date()) -> Bool {
        guard let fajr = suhoorEnd, let maghrib = iftar else { return false }
        return now >= fajr && now < maghrib
    }

    // MARK: - Per-day opt-out (travel, illness — without disabling the whole mode)

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    var todayKey: String { Self.dayKey(Date()) }
    func isSkipped(_ key: String) -> Bool { skippedDays.contains(key) }
    /// The flag the day's Eating score is gated on — a real, fasting Ramadan day.
    var isFastingToday: Bool { isActiveToday && !isSkipped(todayKey) }

    func setSkipped(_ on: Bool, day: String) {
        var set = Set(skippedDays)
        if on { set.insert(day) } else { set.remove(day) }
        skippedDays = Array(Array(set).sorted().suffix(90))   // bounded: only recent days matter
        persist()
        refresh(force: true)
    }

    // MARK: - Settings

    func setMode(_ m: Mode) { mode = m; persist(); refresh(force: true) }
    func setDayAdjustment(_ v: Int) { dayAdjustment = min(1, max(-1, v)); persist(); refresh(force: true) }
    func setAutoFast(_ on: Bool) { autoFast = on; persist(); refresh(force: true) }
    func setSuhoorLead(_ minutes: Int) { suhoorLeadMinutes = min(90, max(5, minutes)); persist(); refresh(force: true) }
    func setPreIftarReminder(_ on: Bool) { preIftarReminder = on; persist(); refresh(force: true) }

    var adjustmentLabel: String {
        switch dayAdjustment {
        case 1: return "1 day earlier"
        case -1: return "1 day later"
        default: return "Umm al-Qura"
        }
    }

    /// Settings subtitle — says what the mode is actually doing right now.
    var statusLine: String {
        switch mode {
        case .off: return "Off"
        case .on: return "Always on"
        case .auto:
            if let n = dayNumber { return "Automatic — Ramadan day \(n)" }
            return "Automatic — not Ramadan right now"
        }
    }

    // MARK: - Taraweeh seeding (once per Hijri year, never re-seeded after a deletion)

    /// True exactly once per Hijri year; stamps `ramadan_seeded_year` as it returns, so a habit the
    /// user then deletes is not resurrected on the next launch.
    func consumeTaraweehSeed() -> Bool {
        let year = RamadanCalendar.hijriYear(Date(), adjustmentDays: dayAdjustment)
        guard (d.object(forKey: seededYearKey) as? Int) != year else { return false }
        d.set(year, forKey: seededYearKey)
        return true
    }

    // MARK: - Auto-fast (manual always wins)

    /// Start the fast at Fajr and end it at Maghrib while Ramadan mode + auto-fast are on.
    /// The day is stamped the moment we auto-start, so a fast the user ends by hand is never
    /// restarted by the next refresh — a manual decision outranks the automation, always.
    func reconcileFast() {
        guard let fasting, autoFast, isActiveToday else { return }
        // High latitude / no location yet: no computed boundaries → leave the fast fully manual.
        guard let fajr = suhoorEnd, let maghrib = iftar, maghrib > fajr else { return }
        let now = Date()
        let key = todayKey
        let stamped = d.string(forKey: autoFastDayKey)

        if isSkipped(key) {
            if stamped == key, fasting.isFasting { fasting.endFast() }
            return
        }
        if now >= fajr, now < maghrib {
            guard stamped != key else { return }
            if !fasting.isFasting {
                if !fasting.enabled { fasting.enabled = true }
                fasting.startFast(at: fajr)
            }
            d.set(key, forKey: autoFastDayKey)
        } else if now >= maghrib, stamped == key, fasting.isFasting,
                  let start = fasting.fastStart, start < maghrib {
            fasting.endFast(at: maghrib)
        }
    }

    // MARK: - Notifications (`ramadan-` prefix — cleared wholesale, then rebuilt)

    /// Suhoor fires before **that day's own** Fajr, so the request for day N is always built from
    /// day N's computed Fajr — scheduling tomorrow's suhoor off today's Fajr is the off-by-one bug
    /// this loop exists to avoid. Silent no-op when notifications were never granted.
    private func scheduleNotifications() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        var planned: [RamadanNote] = []

        if let prayer {
            for offset in 0..<scheduleDays {
                guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
                let stamp = Self.dayKey(day)
                guard isActive(on: day), !isSkipped(stamp) else { continue }
                guard let pt = prayer.times(for: day) else { break }   // no location → nothing to schedule

                if let fajr = pt[.fajr],
                   let warn = cal.date(byAdding: .minute, value: -suhoorLeadMinutes, to: fajr), warn > now {
                    planned.append(RamadanNote(
                        id: "\(notePrefix)suhoor-\(stamp)", fire: warn,
                        title: "Suhoor ending soon 🌙",
                        body: "About \(suhoorLeadMinutes) min to Fajr — finish suhoor and hydrate."))
                }
                if let maghrib = pt[.maghrib] {
                    if preIftarReminder,
                       let pre = cal.date(byAdding: .minute, value: -preIftarLeadMinutes, to: maghrib), pre > now {
                        planned.append(RamadanNote(
                            id: "\(notePrefix)preiftar-\(stamp)", fire: pre,
                            title: "Iftar in \(preIftarLeadMinutes) minutes",
                            body: "Dates and water ready — Maghrib is close."))
                    }
                    if maghrib > now {
                        planned.append(RamadanNote(
                            id: "\(notePrefix)iftar-\(stamp)", fire: maghrib,
                            title: "Iftar time 🤲",
                            body: "Maghrib is in — time to break your fast. Ramadan Mubarak."))
                    }
                }
            }
        }

        let notes = planned
        let prefix = notePrefix
        let calendar = cal
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            guard granted else { return }
            center.getPendingNotificationRequests { reqs in
                let ours = reqs.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
                center.removePendingNotificationRequests(withIdentifiers: ours)
                for n in notes {
                    let content = UNMutableNotificationContent()
                    content.title = n.title
                    content.body = n.body
                    content.sound = .default
                    let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: n.fire)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: trigger))
                }
                #if DEBUG
                print("[ramadan] \(notes.map { $0.id })")
                #endif
            }
        }
    }
}
