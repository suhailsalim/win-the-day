import Foundation
import CoreLocation
@preconcurrency import UserNotifications
import SwiftUI
import WidgetKit

/// Calculation method (twilight angles). Default: Muslim World League.
struct CalcMethod: Equatable {
    var name: String
    var fajrAngle: Double
    var ishaAngle: Double

    static let mwl = CalcMethod(name: "Muslim World League", fajrAngle: 18, ishaAngle: 17)
    static let karachi = CalcMethod(name: "Karachi", fajrAngle: 18, ishaAngle: 18)
    static let egypt = CalcMethod(name: "Egyptian", fajrAngle: 19.5, ishaAngle: 17.5)
    static let ummAlQura = CalcMethod(name: "Umm al-Qura", fajrAngle: 18.5, ishaAngle: 18) // Isha = +90min handled separately normally
    static let jafari = CalcMethod(name: "Jafari (Shia)", fajrAngle: 16, ishaAngle: 14)
    static let all = [mwl, karachi, egypt, ummAlQura]
}

@MainActor
final class PrayerManager: NSObject, ObservableObject {
    @Published var today: PrayerTimes?
    @Published var nextFajr: Date?     // tomorrow's Fajr — bounds Isha's classification window (PrayerClassifier)
    @Published var placeName: String = ""
    @Published var enabled: Bool
    @Published var method: CalcMethod
    @Published var branch: String      // "sunni" or "shia"
    @Published var madhab: String      // "hanafi", "shafi", "maliki", "hanbali"
    @Published var ramadanMode: Bool   // schedule suhoor/iftar reminders
    @Published var locationAuthorized = false
    @Published var statusNote: String = ""

    /// "auto" | "on" | "off". Jumu'ah replaces Dhuhr on Friday for those it is obligatory on — in
    /// the majority view, adult resident men. "auto" follows the sex in Targets, but onboarding
    /// never asks for that (it defaults to male), so this stays user-correctable rather than the app
    /// quietly deciding a point of practice on someone's behalf.
    @Published var jumuahMode: String
    /// Minutes past midnight of the local congregation, or -1 to use the computed Dhuhr. A mosque's
    /// khutbah time is set by the mosque, not by astronomy — it can only be entered, not derived.
    @Published var jumuahMinute: Int
    /// Mirrored from `Targets.sexMale` so notification scheduling, which runs without the store, can
    /// resolve "auto" too.
    @Published var userIsMale: Bool

    static let madhabs = ["hanafi", "shafi", "maliki", "hanbali"]
    static let jumuahModes = ["auto", "on", "off"]

    /// Does this user observe Jumu'ah at all? (Independent of what day it is.)
    var observesJumuah: Bool {
        switch jumuahMode {
        case "on": return true
        case "off": return false
        default: return userIsMale
        }
    }

    /// Does the Dhuhr slot read as Jumu'ah on `date`?
    func isJumuah(on date: Date = Date()) -> Bool {
        observesJumuah && PrayerTimes.isFriday(date)
    }

    /// Display name for a prayer on a given day — "Jumu'ah" in place of Dhuhr on Fridays.
    func label(_ name: PrayerTimes.Name, on date: Date = Date()) -> String {
        name.label(jumuah: isJumuah(on: date))
    }

    /// The time to *show*. Identical to the computed time except for Jumu'ah when a congregation
    /// time has been entered. The underlying window is untouched, so classification and scoring
    /// still run off the astronomical Dhuhr and marking early or late bands the same as ever.
    func displayTime(_ name: PrayerTimes.Name, on date: Date, from times: PrayerTimes?) -> Date? {
        guard let base = times?[name] else { return nil }
        guard name == .dhuhr, isJumuah(on: date), jumuahMinute >= 0 else { return base }
        return Calendar.current.date(bySettingHour: jumuahMinute / 60, minute: jumuahMinute % 60,
                                     second: 0, of: base) ?? base
    }

    func setJumuahMode(_ m: String) {
        jumuahMode = Self.jumuahModes.contains(m) ? m : "auto"
        persist(); refreshFromCache()
    }

    /// Pass -1 to fall back to the computed Dhuhr.
    func setJumuahMinute(_ m: Int) {
        jumuahMinute = m < 0 ? -1 : min(24 * 60 - 1, m)
        persist(); refreshFromCache()
    }

    /// Called by the app whenever Targets change, so "auto" tracks the user's sex.
    func syncSex(male: Bool) {
        guard male != userIsMale else { return }
        userIsMale = male
        defaults.set(male, forKey: "prayer_user_male")
        refreshFromCache()
    }

    /// Asr shadow factor: Hanafi = 2, everyone else (incl. Shia/Jafari) = 1.
    private var asrFactor: Double { (branch == "sunni" && madhab == "hanafi") ? 2 : 1 }
    /// Shia uses the Jafari method; Sunni uses the chosen method.
    private var activeMethod: CalcMethod { branch == "shia" ? .jafari : method }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var coordinate: CLLocationCoordinate2D?
    private let prayerNotePrefix = "prayer-"

    private let defaults = UserDefaults.standard

    override init() {
        enabled = defaults.object(forKey: "prayer_enabled") as? Bool ?? true
        branch = defaults.string(forKey: "prayer_branch") ?? "sunni"
        // Migrate the old asrHanafi bool into a madhab.
        if let m = defaults.string(forKey: "prayer_madhab") {
            madhab = m
        } else {
            madhab = (defaults.object(forKey: "prayer_hanafi") as? Bool ?? true) ? "hanafi" : "shafi"
        }
        ramadanMode = defaults.object(forKey: "prayer_ramadan") as? Bool ?? false
        let savedJumuah = defaults.string(forKey: "prayer_jumuah") ?? "auto"
        jumuahMode = PrayerManager.jumuahModes.contains(savedJumuah) ? savedJumuah : "auto"
        jumuahMinute = defaults.object(forKey: "prayer_jumuah_minute") as? Int ?? -1
        userIsMale = defaults.object(forKey: "prayer_user_male") as? Bool ?? true
        let savedMethod = defaults.string(forKey: "prayer_method") ?? "Muslim World League"
        method = CalcMethod.all.first { $0.name == savedMethod } ?? .mwl
        if let lat = defaults.object(forKey: "prayer_lat") as? Double,
           let lon = defaults.object(forKey: "prayer_lon") as? Double {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        placeName = defaults.string(forKey: "prayer_place") ?? ""
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let coordinate { recompute(for: coordinate) }   // show cached times immediately
    }

    private func persist() {
        defaults.set(enabled, forKey: "prayer_enabled")
        defaults.set(branch, forKey: "prayer_branch")
        defaults.set(madhab, forKey: "prayer_madhab")
        defaults.set(ramadanMode, forKey: "prayer_ramadan")
        defaults.set(jumuahMode, forKey: "prayer_jumuah")
        defaults.set(jumuahMinute, forKey: "prayer_jumuah_minute")
        defaults.set(userIsMale, forKey: "prayer_user_male")
        defaults.set(method.name, forKey: "prayer_method")
        if let c = coordinate {
            defaults.set(c.latitude, forKey: "prayer_lat")
            defaults.set(c.longitude, forKey: "prayer_lon")
        }
        defaults.set(placeName, forKey: "prayer_place")
    }

    // MARK: - Entry point (call when the app appears)

    func start() {
        guard enabled else { return }
        Task { await requestNotifications() }
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationAuthorized = true
            manager.requestLocation()
        case .denied, .restricted:
            locationAuthorized = false
            statusNote = "Location is off — enable it in Settings for accurate times."
        @unknown default: break
        }
        if let coordinate { recompute(for: coordinate) }
    }

    func setEnabled(_ on: Bool) {
        enabled = on; persist()
        if on { start() } else { clearNotifications() }
    }

    func setMethod(_ m: CalcMethod) { method = m; persist(); refreshFromCache() }
    func setBranch(_ b: String) { branch = b; persist(); refreshFromCache() }
    func setMadhab(_ m: String) { madhab = m; persist(); refreshFromCache() }
    /// Ramadan mode is *derived* — `RamadanManager` auto-detects the month and mirrors it here so the
    /// widget snapshot and the fasting card stay in step. The `ramadan-` notification prefix belongs
    /// entirely to that manager (AGENTS.md convention 6): two owners clearing the same prefix meant
    /// whichever ran last silently deleted the other's requests.
    func setRamadan(_ on: Bool) {
        ramadanMode = on; persist()
        refreshFromCache()
    }

    /// Suhoor ends at Fajr; iftar is at Maghrib (today's computed times).
    var suhoorEnd: Date? { today?[.fajr] }
    var iftar: Date? { today?[.maghrib] }

    /// Computed prayer times for any date at the cached location — `nil` until a location is known.
    /// Ramadan mode schedules against this so day N's suhoor is always built from day N's own Fajr.
    func times(for date: Date) -> PrayerTimes? {
        guard let coordinate else { return nil }
        let m = activeMethod
        return PrayerTimes.calculate(date: date, latitude: coordinate.latitude, longitude: coordinate.longitude,
                                     timeZone: .current, fajrAngle: m.fajrAngle, ishaAngle: m.ishaAngle,
                                     asrFactor: asrFactor)
    }

    private func refreshFromCache() {
        if let coordinate { recompute(for: coordinate) }
    }

    // MARK: - Notifications

    private func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Compute & schedule

    private func recompute(for coord: CLLocationCoordinate2D) {
        let factor = asrFactor
        let m = activeMethod
        let tz = TimeZone.current
        today = PrayerTimes.calculate(date: Date(), latitude: coord.latitude, longitude: coord.longitude,
                                      timeZone: tz, fajrAngle: m.fajrAngle, ishaAngle: m.ishaAngle,
                                      asrFactor: factor)
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        nextFajr = PrayerTimes.calculate(date: tomorrowDate, latitude: coord.latitude, longitude: coord.longitude,
                                         timeZone: tz, fajrAngle: m.fajrAngle, ishaAngle: m.ishaAngle,
                                         asrFactor: factor)[.fajr]
        if enabled { scheduleNotifications(coord: coord, asrFactor: factor, tz: tz) }
        maybeStartLiveActivity()
        publishSnapshot()
    }

    private func publishSnapshot() {
        for suite in [SharedStore.appGroup, SharedStore.watchAppGroup] {
            var s = SharedStore.load(suite: suite)
            if let next = nextPrayer {
                s.nextPrayerName = label(next.0, on: next.1)
                s.nextPrayerEpoch = (displayTime(next.0, on: next.1, from: today) ?? next.1).timeIntervalSince1970
            }
            s.jumuahToday = isJumuah()
            s.placeName = placeName
            s.ramadanSuhoorEpoch = ramadanMode ? (suhoorEnd?.timeIntervalSince1970 ?? 0) : 0
            s.ramadanIftarEpoch = ramadanMode ? (iftar?.timeIntervalSince1970 ?? 0) : 0
            SharedStore.save(s, suite: suite)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func scheduleNotifications(coord: CLLocationCoordinate2D, asrFactor: Double, tz: TimeZone) {
        let center = UNUserNotificationCenter.current()
        let prefix = prayerNotePrefix
        let method = activeMethod
        // Snapshot main-actor state into locals before the escaping closure (AGENTS.md).
        let jumuah = observesJumuah
        let jumuahAt = jumuahMinute
        center.getPendingNotificationRequests { reqs in
            let ours = reqs.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            let now = Date()
            for offset in 0..<5 {     // schedule the next 5 days
                guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
                let pt = PrayerTimes.calculate(date: day, latitude: coord.latitude, longitude: coord.longitude,
                                               timeZone: tz, fajrAngle: method.fajrAngle,
                                               ishaAngle: method.ishaAngle, asrFactor: asrFactor)
                // Skip Fajr — no notification at ~4:30 AM.
                for (name, date) in pt.ordered where name.isPrayer && name != .fajr && date > now {
                    // Friday is resolved per scheduled day in the target time zone, not per "today".
                    let isJumuah = jumuah && name == .dhuhr && PrayerTimes.isFriday(date, calendar: cal)
                    var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    if isJumuah, jumuahAt >= 0 {
                        comps.hour = jumuahAt / 60
                        comps.minute = jumuahAt % 60
                        // A congregation earlier than the astronomical Dhuhr would be invalid; the
                        // picker prevents it, but a stale value must not schedule into the past.
                        if let fires = cal.date(from: comps), fires <= now { continue }
                    }
                    let title = name.label(jumuah: isJumuah)
                    let content = UNMutableNotificationContent()
                    content.title = "\(title) 🕌"
                    content.body = "It\u{2019}s time for \(title) — tap to mark it once you\u{2019}ve prayed."
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    let id = "\(prefix)\(name.rawValue)-\(comps.year!)-\(comps.month!)-\(comps.day!)"
                    center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                }
            }
        }
    }

    private func clearNotifications() {
        let center = UNUserNotificationCenter.current()
        let prefix = prayerNotePrefix
        center.getPendingNotificationRequests { reqs in
            let ours = reqs.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }

    // MARK: - Display helpers

    var nextPrayer: (PrayerTimes.Name, Date)? {
        guard let today else { return nil }
        let now = Date()
        if let upcoming = today.ordered.first(where: { $0.0.isPrayer && $0.1 > now }) { return upcoming }
        return today.ordered.first { $0.0 == .fajr }   // wrap to tomorrow's Fajr (display only)
    }

    // MARK: - Live Activity (started in PrayerLiveActivity.swift when app is open near adhan)

    private func maybeStartLiveActivity() {
        guard let today else { return }
        PrayerLiveActivityController.shared.startIfWithinWindow(times: today)
    }
}

// MARK: - CLLocationManagerDelegate

extension PrayerManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                locationAuthorized = true
                manager.requestLocation()
            case .denied, .restricted:
                locationAuthorized = false
                statusNote = "Location is off — enable it in Settings for accurate times."
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.coordinate = loc.coordinate
            self.persist()
            self.recompute(for: loc.coordinate)
            self.reverseGeocode(loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.coordinate == nil {
                self.statusNote = "Couldn\u{2019}t get your location just now."
            }
        }
    }

    private func reverseGeocode(_ loc: CLLocation) {
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self else { return }
                if let p = placemarks?.first {
                    self.placeName = [p.locality, p.administrativeArea].compactMap { $0 }.first ?? ""
                    self.persist()
                }
            }
        }
    }
}
