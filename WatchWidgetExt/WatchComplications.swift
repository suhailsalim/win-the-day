import WidgetKit
import SwiftUI

private let accent = Color(red: 0.78, green: 0.52, blue: 0.18)
private let sage = Color(red: 0.24, green: 0.66, blue: 0.46)

struct WatchEntry: TimelineEntry {
    let date: Date
    let snap: SharedSnapshot
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry { WatchEntry(date: Date(), snap: SharedSnapshot()) }
    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntry(date: Date(), snap: SharedStore.load(suite: SharedStore.watchAppGroup)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let entry = WatchEntry(date: Date(), snap: SharedStore.load(suite: SharedStore.watchAppGroup))
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

private func timeStr(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "h:mm"; return f.string(from: d)
}

// Score ring — circular & corner
struct WatchScoreComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchScoreComplication", provider: WatchProvider()) { entry in
            let done = entry.snap.nnDone, total = max(1, entry.snap.nnTotal)
            Gauge(value: Double(done), in: 0...Double(total)) {
                Image(systemName: "checkmark.seal.fill")
            } currentValueLabel: {
                Text("\(done)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Score")
        .description("Non-negotiables done today.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

// Next prayer — inline
struct WatchPrayerComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchPrayerComplication", provider: WatchProvider()) { entry in
            if let d = entry.snap.nextPrayerDate {
                Label("\(entry.snap.nextPrayerName) \(timeStr(d))", systemImage: "moon.stars.fill")
                    .containerBackground(.clear, for: .widget)
            } else {
                Label("Prayers", systemImage: "moon.stars.fill")
                    .containerBackground(.clear, for: .widget)
            }
        }
        .configurationDisplayName("Next Prayer")
        .description("Your next prayer.")
        .supportedFamilies([.accessoryInline, .accessoryCorner])
    }
}

// Week progress — circular & corner
struct WatchWeekComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchWeekComplication", provider: WatchProvider()) { entry in
            Gauge(value: Double(entry.snap.weekDaysWon), in: 0...7) {
                Image(systemName: "trophy.fill")
            } currentValueLabel: {
                Text("\(entry.snap.weekDaysWon)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Week")
        .description("Days won this week.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

// Fasting — inline & circular
struct WatchFastingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchFastingComplication", provider: WatchProvider()) { entry in
            let s = entry.snap
            let hrs = s.fastStartEpoch > 0 ? max(0, (Date().timeIntervalSince1970 - s.fastStartEpoch) / 3600) : 0
            if s.fastingActive {
                Label(String(format: "Fast %.0fh", hrs), systemImage: "timer")
                    .containerBackground(.clear, for: .widget)
            } else {
                Label("No fast", systemImage: "timer").containerBackground(.clear, for: .widget)
            }
        }
        .configurationDisplayName("Fasting")
        .description("Your fasting window.")
        .supportedFamilies([.accessoryInline, .accessoryCorner])
    }
}

// Next session — inline & corner
struct WatchSessionComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchSessionComplication", provider: WatchProvider()) { entry in
            let s = entry.snap
            if s.nextSessionEpoch > 0 {
                Label("\(s.nextSessionTitle) \(timeStr(Date(timeIntervalSince1970: s.nextSessionEpoch)))", systemImage: "dumbbell.fill")
                    .containerBackground(.clear, for: .widget)
            } else {
                Label("No session", systemImage: "dumbbell.fill").containerBackground(.clear, for: .widget)
            }
        }
        .configurationDisplayName("Next session")
        .description("Your next training session.")
        .supportedFamilies([.accessoryInline, .accessoryCorner])
    }
}

// Readiness — circular & corner
struct WatchReadinessComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchReadinessComplication", provider: WatchProvider()) { entry in
            Gauge(value: Double(entry.snap.readiness), in: 0...100) {
                Image(systemName: "bolt.heart.fill")
            } currentValueLabel: {
                Text(entry.snap.readiness > 0 ? "\(entry.snap.readiness)" : "—")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Readiness")
        .description("Your readiness score.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

// Weather — inline & corner
struct WatchWeatherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchWeatherComplication", provider: WatchProvider()) { entry in
            let s = entry.snap
            Label(s.weatherCode >= 0 ? "\(Int(s.weatherTempC))° \(s.outdoorOK ? "outdoor ok" : "indoor")" : "Weather",
                  systemImage: s.weatherSymbol.isEmpty ? "cloud.fill" : s.weatherSymbol)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Weather")
        .description("Conditions and outdoor advice.")
        .supportedFamilies([.accessoryInline, .accessoryCorner])
    }
}

// Summary — rectangular
struct WatchSummaryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchSummaryComplication", provider: WatchProvider()) { entry in
            let s = entry.snap
            VStack(alignment: .leading, spacing: 2) {
                Label("\(s.score)/\(max(1, s.nnTotal)) · \(s.prayersDone)/5 prayers", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                if let d = s.nextPrayerDate {
                    Label("\(s.nextPrayerName) \(timeStr(d))", systemImage: "moon.stars.fill").font(.system(size: 12))
                }
            }
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Summary")
        .description("Score, prayers and next prayer.")
        .supportedFamilies([.accessoryRectangular])
    }
}
