# Faith: prayer, Qibla, fasting & Ramadan

Optional and customizable — the spirituality pillar can be Islam (rich preset), another faith, or off.

## Prayer times (`PrayerManager` + `PrayerTimes`)
- Self-contained astronomical calculation (`PrayerTimes.calculate`). `branch` (sunni/shia) + `madhab`
  (hanafi/shafi/maliki/hanbali) drive the Asr factor; Shia uses the Jafari method. Method choices in
  `CalcMethod` (MWL default).
- Live location via `CLLocationManager`; settings persisted under `prayer_*` UserDefaults keys
  (NOT `AppSettings`, to avoid Codable migrations).
- Per-prayer local notifications (`prayer-` prefix; Fajr notification skipped). Live Activity within
  20 min after adhan (`PrayerLiveActivity`).
- Today: tap a prayer to mark it (`Entry.prayers`).

## Qibla
`QiblaView` + heading via CoreLocation; bearing to the Kaaba. Opened from the prayer card compass.

## Fasting & Ramadan (`FastingManager`)
- Intermittent-fasting window tracker: protocols 14:10…OMAD/custom, active fast start, streak from a
  `fast_history` map. Own UserDefaults (`fast_*`).
- **Ramadan mode** (in `PrayerManager`): suhoor = Fajr, iftar = Maghrib; schedules suhoor (−30 min)
  and iftar notifications (`ramadan-` prefix). Today shows a live suhoor/iftar countdown.
- The fasting Today module shows the IF ring + start/end and (in Ramadan) the countdown. Publishes
  fasting state to the [snapshot](widgets-watch.md).

## Key files
`PrayerManager.swift`, `PrayerTimes.swift`, `QiblaView.swift`, `FastingManager.swift`,
`Shared/PrayerActivityAttributes.swift`, `TodayView.swift` (`prayerCard`, `fastingModule`).
