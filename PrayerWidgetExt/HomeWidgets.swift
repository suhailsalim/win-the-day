import WidgetKit
import SwiftUI

// Colors (kept local so the widget doesn't depend on the app module).
private let accent = Color(red: 0.78, green: 0.53, blue: 0.24)
private let accentD = Color(red: 0.78, green: 0.52, blue: 0.18)
private let sage = Color(red: 0.24, green: 0.66, blue: 0.46)
private let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
private let cream = Color(red: 0.96, green: 0.92, blue: 0.86)
private let coral = Color(red: 0.85, green: 0.42, blue: 0.29)

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: SharedSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snap: SharedSnapshot()) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snap: SharedStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snap: SharedStore.load())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

private func widgetBackground() -> some View {
    LinearGradient(colors: [Color(red: 0.99, green: 0.96, blue: 0.93), cream],
                   startPoint: .top, endPoint: .bottom)
}

// MARK: - 1×1 Next prayer

struct NextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPrayerWidget", provider: SnapshotProvider()) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "moon.stars.fill").font(.system(size: 16)).foregroundStyle(accent)
                Spacer()
                Text("Next prayer").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(entry.snap.nextPrayerName).font(.system(size: 18, weight: .bold)).foregroundStyle(ink)
                if let d = entry.snap.nextPrayerDate {
                    Text(d, format: .dateTime.hour().minute()).font(.system(size: 13, weight: .semibold)).foregroundStyle(accentD)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Next Prayer")
        .description("Your next prayer and its time.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 1×1 Non-negotiables ring

struct NonNegotiablesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NonNegotiablesWidget", provider: SnapshotProvider()) { entry in
            let done = entry.snap.nnDone, total = max(1, entry.snap.nnTotal)
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(accent.opacity(0.2), lineWidth: 8)
                    Circle().trim(from: 0, to: CGFloat(done) / CGFloat(total))
                        .stroke(done >= 3 ? sage : accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(done)/\(total)").font(.system(size: 20, weight: .bold)).foregroundStyle(ink)
                }
                .frame(width: 74, height: 74)
                Text("Non-negotiables").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Non-negotiables")
        .description("How many of your 5 you\u{2019}ve hit today.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Fasting helpers (shared by widgets)

func fastProgress(_ s: SharedSnapshot, now: Date = Date()) -> Double {
    guard s.fastingActive, s.fastStartEpoch > 0, s.fastTargetHours > 0 else { return 0 }
    let elapsed = now.timeIntervalSince1970 - s.fastStartEpoch
    return min(1, max(0, elapsed / (s.fastTargetHours * 3600)))
}
func fastElapsedHours(_ s: SharedSnapshot, now: Date = Date()) -> Double {
    guard s.fastStartEpoch > 0 else { return 0 }
    return max(0, (now.timeIntervalSince1970 - s.fastStartEpoch) / 3600)
}

// MARK: - 1×1 Fasting

struct FastingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FastingWidget", provider: SnapshotProvider()) { entry in
            let s = entry.snap
            VStack(spacing: 6) {
                if s.ramadanIftarEpoch > 0 {
                    Image(systemName: "moon.stars.fill").font(.system(size: 16)).foregroundStyle(accent)
                    Text("Iftar").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(Date(timeIntervalSince1970: s.ramadanIftarEpoch), format: .dateTime.hour().minute())
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(ink)
                } else if s.fastingActive {
                    let p = fastProgress(s)
                    ZStack {
                        Circle().stroke(accent.opacity(0.2), lineWidth: 8)
                        Circle().trim(from: 0, to: CGFloat(p))
                            .stroke(p >= 1 ? sage : accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(String(format: "%.0f%%", p * 100)).font(.system(size: 17, weight: .bold)).foregroundStyle(ink)
                    }
                    .frame(width: 70, height: 70)
                    Text(String(format: "%.1fh fast", fastElapsedHours(s))).font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "timer").font(.system(size: 20)).foregroundStyle(accent)
                    Text("Not fasting").font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Fasting")
        .description("Your fasting window or next iftar.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 1×1 Readiness

struct ReadinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReadinessWidget", provider: SnapshotProvider()) { entry in
            let r = entry.snap.readiness
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color(red: 0.43, green: 0.48, blue: 1).opacity(0.2), lineWidth: 8)
                    Circle().trim(from: 0, to: CGFloat(r) / 100)
                        .stroke(r >= 70 ? sage : (r >= 45 ? accentD : Color(red: 0.85, green: 0.42, blue: 0.29)),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(r > 0 ? "\(r)" : "—").font(.system(size: 20, weight: .bold)).foregroundStyle(ink)
                        Text("ready").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 74, height: 74)
                Text(entry.snap.sleepScore > 0 ? "Sleep \(entry.snap.sleepScore)" : "Readiness")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Readiness")
        .description("Your morning readiness score.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 1×1 Weather

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeatherWidget", provider: SnapshotProvider()) { entry in
            let s = entry.snap
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: s.weatherSymbol.isEmpty ? "cloud.fill" : s.weatherSymbol)
                    .font(.system(size: 22)).foregroundStyle(Color(red: 0.18, green: 0.54, blue: 0.88))
                Spacer()
                Text(s.weatherCode >= 0 ? "\(Int(s.weatherTempC))°" : "—°")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(ink)
                HStack(spacing: 3) {
                    Image(systemName: s.outdoorOK ? "figure.walk" : "house.fill")
                        .font(.system(size: 10)).foregroundStyle(s.outdoorOK ? sage : Color(red: 0.85, green: 0.42, blue: 0.29))
                    Text(s.weatherHeadline.isEmpty ? "Weather" : s.weatherHeadline)
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Weather")
        .description("Conditions and whether it's good to get outside.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 1×1 Week progress

struct WeekProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekProgressWidget", provider: SnapshotProvider()) { entry in
            let won = entry.snap.weekDaysWon
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(sage.opacity(0.2), lineWidth: 8)
                    Circle().trim(from: 0, to: CGFloat(won) / 7.0)
                        .stroke(sage, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(won)/7").font(.system(size: 20, weight: .bold)).foregroundStyle(ink)
                }
                .frame(width: 74, height: 74)
                Text("Days won this week").font(.system(size: 10)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Week progress")
        .description("Days you cleared the bar this week.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 1×1 Next session

struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextSessionWidget", provider: SnapshotProvider()) { entry in
            let s = entry.snap
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "dumbbell.fill").font(.system(size: 16)).foregroundStyle(sage)
                Spacer()
                Text("Next session").font(.system(size: 11)).foregroundStyle(.secondary)
                if s.nextSessionEpoch > 0 {
                    Text(s.nextSessionTitle).font(.system(size: 16, weight: .bold)).foregroundStyle(ink).lineLimit(2)
                    Text(Date(timeIntervalSince1970: s.nextSessionEpoch), format: .dateTime.weekday().hour().minute())
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(accentD)
                } else {
                    Text("Nothing scheduled").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Next session")
        .description("Your next gym, PT or mobility session.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 1×1 Upcoming event

struct UpcomingEventWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingEventWidget", provider: SnapshotProvider()) { entry in
            let s = entry.snap
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "gift.fill").font(.system(size: 16)).foregroundStyle(accent)
                Spacer()
                Text("Coming up").font(.system(size: 11)).foregroundStyle(.secondary)
                if s.nextOccasionEpoch > 0 {
                    Text(s.nextOccasionTitle).font(.system(size: 16, weight: .bold)).foregroundStyle(ink).lineLimit(2)
                    Text(Date(timeIntervalSince1970: s.nextOccasionEpoch), format: .dateTime.day().month())
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(accentD)
                } else {
                    Text("No events").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Upcoming event")
        .description("Your next birthday, anniversary or trip.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Rings (shared by the ring-strip + single-ring widgets)

/// Local hex → Color. The app's `Color(hex:)` lives in the app target; the widget stays independent.
private func ringHexColor(_ hex: UInt) -> Color {
    Color(.sRGB,
          red: Double((hex >> 16) & 0xff) / 255,
          green: Double((hex >> 8) & 0xff) / 255,
          blue: Double(hex & 0xff) / 255,
          opacity: 1)
}

/// The arc color: the user's custom color when set, else the score band (`colorHex == 0` means
/// "derive from the band", not black) — same bands the app's Today ring row uses.
private func ringColor(_ r: SnapshotRing) -> Color {
    if r.colorHex != 0 { return ringHexColor(r.colorHex) }
    let frac = Double(r.pct) / 100
    return frac < 0.34 ? coral : (frac < 0.67 ? accentD : sage)
}

/// One ring straight from the snapshot. `SnapshotRing` carries no `available` flag, so a "—"
/// (or empty) display is the app's "no data yet" marker — grey track, no colored arc.
private struct SnapshotRingView: View {
    let ring: SnapshotRing
    var size: CGFloat = 58
    var lineWidth: CGFloat = 6

    private var available: Bool { !ring.display.isEmpty && ring.display != "\u{2014}" }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color(white: 0.5).opacity(0.18), lineWidth: lineWidth)
                if available {
                    Circle().trim(from: 0, to: max(0.01, min(1, Double(ring.pct) / 100)))
                        .stroke(ringColor(ring), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(available ? ring.display : "\u{2014}")
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(available ? ink : Color.secondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, lineWidth + 2)
            }
            .frame(width: size, height: size)
            Text(ring.title)
                .font(.system(size: min(11, size * 0.17))).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// Shown when the snapshot has no rings — an old snapshot decodes `rings` as `[]`, and a fresh
/// install has never published one. Never render 0% arcs for that.
private struct RingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.dashed").font(.system(size: 20)).foregroundStyle(accent)
            Text("Open Win the Day to set up rings")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - 4×2 Ring strip (medium)

struct RingStripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RingStripWidget", provider: SnapshotProvider()) { entry in
            let rings = entry.snap.rings
            VStack(spacing: 8) {
                if rings.isEmpty {
                    RingsPlaceholderView()
                } else {
                    HStack(spacing: 4) {
                        // The app already caps the row at the user's ring count (3 or 4); prefix
                        // again so an oversized snapshot can never overflow the medium family.
                        ForEach(Array(rings.prefix(4).enumerated()), id: \.offset) { _, ring in
                            SnapshotRingView(ring: ring).frame(maxWidth: .infinity)
                        }
                    }
                    if !entry.snap.topTip.isEmpty {
                        Text(entry.snap.topTip)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(2).multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Rings")
        .description("Your ring row and today\u{2019}s tip.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 1×1 Single ring

struct SingleRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SingleRingWidget", provider: SnapshotProvider()) { entry in
            VStack {
                // `rings.first` is the user's own #1 ring — the snapshot preserves their order.
                if let ring = entry.snap.rings.first {
                    SnapshotRingView(ring: ring, size: 92, lineWidth: 9)
                } else {
                    RingsPlaceholderView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Ring")
        .description("Your first ring at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 4×1 Summary (medium)

struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SummaryWidget", provider: SnapshotProvider()) { entry in
            let s = entry.snap
            HStack(spacing: 0) {
                stat(title: "Score", value: "\(s.score)/5", color: s.score >= 3 ? sage : accentD)
                divider
                stat(title: "Prayers", value: "\(s.prayersDone)/5", color: accentD)
                divider
                stat(title: "Water", value: waterStr(s), color: Color(red: 0.18, green: 0.54, blue: 0.88))
                divider
                VStack(spacing: 3) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 13)).foregroundStyle(accent)
                    Text(s.nextPrayerName).font(.system(size: 14, weight: .bold)).foregroundStyle(ink)
                    if let d = s.nextPrayerDate {
                        Text(d, format: .dateTime.hour().minute()).font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text("—").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { widgetBackground() }
        }
        .configurationDisplayName("Daily Summary")
        .description("Score, prayers, water and your next prayer.")
        .supportedFamilies([.systemMedium])
    }

    private func waterStr(_ s: SharedSnapshot) -> String {
        let l = Double(s.waterMl) / 1000.0
        return String(format: "%.1fL", l)
    }

    private func stat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(color)
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1, height: 44)
    }
}
