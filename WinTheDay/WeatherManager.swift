import Foundation
import CoreLocation
import WidgetKit

/// Free weather via Open-Meteo (no API key) — used to advise outdoor walks/runs and feed the planner.
/// (Apple WeatherKit needs a paid membership/entitlement, unavailable on free signing.)
@MainActor
final class WeatherManager: NSObject, ObservableObject {
    struct Now { var tempC: Double; var feelsC: Double; var code: Int; var windKph: Double; var isDay: Bool; var precip: Double }
    struct Day: Identifiable { var id: String { date }; var date: String; var code: Int; var maxC: Double; var minC: Double; var precipProb: Int }

    @Published var now: Now?
    @Published var days: [Day] = []
    @Published var place: String = ""
    /// Hourly precip probability + temp for today (for finding a dry window).
    private var hourTimes: [String] = []
    private var hourPrecip: [Int] = []
    private var hourTemp: [Double] = []

    private let manager = CLLocationManager()
    private var coord: CLLocationCoordinate2D?
    private let d = UserDefaults.standard

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        // Seed from the prayer engine's cached coordinate so we have data immediately.
        if let lat = d.object(forKey: "prayer_lat") as? Double, let lon = d.object(forKey: "prayer_lon") as? Double {
            coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        place = d.string(forKey: "prayer_place") ?? ""
    }

    func start() {
        if coord != nil { Task { await fetch() } }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    // MARK: - Fetch

    func fetch() async {
        guard let c = coord else { return }
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)" +
            "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day,precipitation" +
            "&hourly=precipitation_probability,temperature_2m" +
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max" +
            "&timezone=auto&forecast_days=7&wind_speed_unit=kmh"
        guard let url = URL(string: urlStr) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let r = try JSONDecoder().decode(OMResponse.self, from: data)
            if let cur = r.current {
                now = Now(tempC: cur.temperature_2m, feelsC: cur.apparent_temperature ?? cur.temperature_2m,
                          code: cur.weather_code, windKph: cur.wind_speed_10m ?? 0,
                          isDay: (cur.is_day ?? 1) == 1, precip: cur.precipitation ?? 0)
            }
            if let dy = r.daily {
                days = (0..<dy.time.count).map { i in
                    Day(date: dy.time[i], code: dy.weather_code[i],
                        maxC: dy.temperature_2m_max[i], minC: dy.temperature_2m_min[i],
                        precipProb: dy.precipitation_probability_max?[safe: i] ?? 0)
                }
            }
            if let h = r.hourly {
                hourTimes = h.time
                hourPrecip = h.precipitation_probability ?? []
                hourTemp = h.temperature_2m ?? []
            }
            publishSnapshot()
        } catch { /* leave previous data */ }
    }

    /// Write current weather into both app groups for widgets & the watch.
    func publishSnapshot() {
        guard let n = now else { return }
        let cond = Self.condition(n.code)
        let advice = outdoorAdvice()
        for suite in [SharedStore.appGroup, SharedStore.watchAppGroup] {
            var s = SharedStore.load(suite: suite)
            s.weatherTempC = n.tempC
            s.weatherCode = n.code
            s.weatherSymbol = cond.symbol
            s.outdoorOK = advice.ok
            s.weatherHeadline = advice.headline
            SharedStore.save(s, suite: suite)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Advice

    /// Should you train/walk outside right now/today?
    func outdoorAdvice() -> (ok: Bool, headline: String, detail: String) {
        guard let n = now else { return (true, "Weather unavailable", "Plan as usual.") }
        let cond = Self.condition(n.code)
        let today = days.first
        let prob = today?.precipProb ?? 0
        if [95, 96, 99].contains(n.code) {
            return (false, "Thunderstorms", "Skip outdoor — do an indoor session.")
        }
        if prob >= 60 || n.precip > 0.5 {
            let window = bestOutdoorWindow()
            return (false, "Rain likely (\(prob)%)", window ?? "Better indoors today.")
        }
        if n.feelsC >= 38 {
            return (false, "Very hot (\(Int(n.feelsC))°)", "Train early/late or indoors; hydrate well.")
        }
        if n.feelsC <= 2 {
            return (false, "Very cold (\(Int(n.feelsC))°)", "Layer up or go indoors.")
        }
        return (true, "Good to get outside", "\(cond.label), \(Int(n.tempC))°. \(bestOutdoorWindow() ?? "Great for a walk or run.")")
    }

    /// Driest upcoming 2-hour window today (by hourly precip probability).
    func bestOutdoorWindow() -> String? {
        guard !hourTimes.isEmpty, hourPrecip.count == hourTimes.count else { return nil }
        let cal = Calendar.current
        let now = Date()
        var best: (idx: Int, prob: Int)?
        for i in 0..<hourTimes.count {
            guard let t = Self.parseHour(hourTimes[i]), t > now, t < now.addingTimeInterval(14*3600) else { continue }
            let hour = cal.component(.hour, from: t)
            guard hour >= 6 && hour <= 21 else { continue }
            let p = hourPrecip[i]
            if best == nil || p < best!.prob { best = (i, p) }
        }
        guard let b = best, let t = Self.parseHour(hourTimes[b.idx]) else { return nil }
        let f = DateFormatter(); f.dateFormat = "h a"
        return "Driest around \(f.string(from: t)) (\(b.prob)% rain)."
    }

    /// Compact multi-day summary for the AI planner.
    var plannerSummary: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let out = DateFormatter(); out.locale = Locale(identifier: "en_GB"); out.dateFormat = "EEE"
        return days.prefix(6).compactMap { d -> String? in
            guard let date = f.date(from: d.date) else { return nil }
            return "\(out.string(from: date)) \(Self.condition(d.code).label) \(Int(d.maxC))°/\(Int(d.minC))° rain \(d.precipProb)%"
        }.joined(separator: "; ")
    }

    // MARK: - WMO code → condition

    static func condition(_ code: Int) -> (label: String, symbol: String) {
        switch code {
        case 0: return ("Clear", "sun.max.fill")
        case 1, 2: return ("Partly cloudy", "cloud.sun.fill")
        case 3: return ("Cloudy", "cloud.fill")
        case 45, 48: return ("Fog", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67: return ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77: return ("Snow", "cloud.snow.fill")
        case 80, 81, 82: return ("Showers", "cloud.heavyrain.fill")
        case 85, 86: return ("Snow showers", "cloud.snow.fill")
        case 95, 96, 99: return ("Thunderstorm", "cloud.bolt.rain.fill")
        default: return ("—", "cloud.fill")
        }
    }

    private static func parseHour(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    // MARK: - Open-Meteo JSON
    private struct OMResponse: Codable {
        var current: Current?; var hourly: Hourly?; var daily: Daily?
        struct Current: Codable { var temperature_2m: Double; var apparent_temperature: Double?; var weather_code: Int; var wind_speed_10m: Double?; var is_day: Int?; var precipitation: Double? }
        struct Hourly: Codable { var time: [String]; var precipitation_probability: [Int]?; var temperature_2m: [Double]? }
        struct Daily: Codable { var time: [String]; var weather_code: [Int]; var temperature_2m_max: [Double]; var temperature_2m_min: [Double]; var precipitation_probability_max: [Int]? }
    }
}

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways {
                m.requestLocation()
            }
        }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        Task { @MainActor in self.coord = loc.coordinate; await self.fetch() }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
