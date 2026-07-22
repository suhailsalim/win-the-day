# NET-05 — Weather forecast query sends user location to open-meteo.com at full coordinate precision (no rounding)

| Field | Value |
|---|---|
| **Severity** | Informational |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | transport / data-egress |
| **Location(s)** | `WinTheDay/Managers/WeatherManager.swift` |

## Summary

WeatherManager.fetch() interpolates the user's full-precision latitude/longitude directly into the Open-Meteo forecast URL. Transport is HTTPS, so this is a data-egress/precision concern (disclosing home-grade location to a third party at more precision than a 7-day forecast needs), not a wire-confidentiality break.

## Details

Confirmed at `WinTheDay/Managers/WeatherManager.swift:48`:

```swift
let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)" +
    "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day,precipitation" +
    ...
    "&timezone=auto&forecast_days=7&wind_speed_unit=kmh"
```

`c` is the `coord: CLLocationCoordinate2D?` property. Its two sources (both verified in-file):

- Seed from the prayer engine's cached coordinate — `WeatherManager.swift:29-30`:
  ```swift
  if let lat = d.object(forKey: "prayer_lat") as? Double, let lon = d.object(forKey: "prayer_lon") as? Double {
      coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }
  ```
- A live GPS fix — `WeatherManager.swift:187-189`:
  ```swift
  nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
      guard let loc = locs.last else { return }
      Task { @MainActor in self.coord = loc.coordinate; await self.fetch() }
  }
  ```

Two accuracy nuances that the original report understated/omitted, both material to severity:

1. The live fix is already coarsened — `WeatherManager.swift:27` sets `manager.desiredAccuracy = kCLLocationAccuracyKilometer`, so the CLLocation path delivers roughly city/km-grade coordinates, not street-level. However, `CLLocationCoordinate2D` is still a full `Double`, and Swift string-interpolating a `Double` emits its full decimal expansion (e.g. `51.50735223`), so the *URL* carries far more digits than the underlying fix is accurate to — cosmetically precise, log-prone, but not actually more informative than ~1 km.

2. The seed path is the sharper leak: `prayer_lat`/`prayer_lon` are written by the prayer/Qibla engine, which needs higher precision for accurate prayer-time and Qibla-direction math, so that cached value can be genuinely home-grade and is interpolated verbatim.

Transport itself is fine: the URL is `https://` (line 48) and the request goes through `URLSession.shared.data(from:)` (line 55) — no cleartext, no ATS exception needed for this host. This finding is purely about (a) sending location to a third party and (b) doing so at unnecessary precision.

## Failure / exploit scenario

Under threat model (d)/(e): A weather forecast is useful at ~1–10 km resolution, yet the request discloses the user's location to open-meteo.com. Because the coordinate is in the query string, it is disproportionately exposed to request logging (Open-Meteo access logs, any TLS-terminating CDN in front of it, on-device diagnostic/network logs) compared to a POST body. When `coord` is seeded from the prayer engine's cached `prayer_lat`/`prayer_lon`, the disclosed value can pinpoint the user's home/neighbourhood rather than just their city. There is no interception here (HTTPS), so this is a privacy/data-minimisation issue, not an exploitable network attack — hence Informational. Note also this is a materially smaller exposure than the app already makes by design: the same `prayer_lat`/`prayer_lon` at full precision are written into the plaintext backup export (see BackupService), which is the higher-impact vector for the same data.

## Impact

Precise-ish user location egresses to a third-party weather API at more decimal precision than a forecast requires, sitting in a log-prone query string. Confidentiality on the wire is intact (HTTPS). Realistic worst case is that Open-Meteo (or an intermediary) can correlate the user's approximate-to-home location over time from access logs. No credential, health, or account data is exposed by this call. For App Store privacy accuracy, note that location is being shared with a third party (Open-Meteo) for the weather feature — this should be reflected in the privacy disclosures / nutrition label.

## Recommendation

Round the coordinates before building the URL, e.g. `String(format: "%.2f", c.latitude)` / `%.2f` for longitude (~1.1 km, ample for a 7-day forecast — and consistent with the `kCLLocationAccuracyKilometer` the app already requests). This removes the false precision on the live-fix path and, more importantly, coarsens the home-grade prayer-engine seed before it leaves the device:

```swift
let lat = String(format: "%.2f", c.latitude)
let lon = String(format: "%.2f", c.longitude)
let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)" + ...
```

Separately, confirm the third-party location share to Open-Meteo is reflected in the App Store privacy manifest / nutrition label (threat model (e)). This is a low-effort data-minimisation win; not urgent.

## References

- CWE-359: Exposure of Private Personal Information to an Unauthorized Actor
- OWASP MASVS-PRIVACY: data minimization
- Apple App Store privacy nutrition labels / PrivacyInfo.xcprivacy required-reason & data-collection disclosures


---

_Finding NET-05. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._