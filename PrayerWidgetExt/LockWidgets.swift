import WidgetKit
import SwiftUI

// Lock Screen (accessory) widgets — reuse SnapshotProvider from HomeWidgets.swift.

struct LockNonNegotiablesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockNonNegotiablesWidget", provider: SnapshotProvider()) { entry in
            let done = entry.snap.nnDone, total = max(1, entry.snap.nnTotal)
            Gauge(value: Double(done), in: 0...Double(total)) {
                Image(systemName: "checkmark.seal.fill")
            } currentValueLabel: {
                Text("\(done)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Non-negotiables")
        .description("Your 5 non-negotiables progress.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockNextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockNextPrayerWidget", provider: SnapshotProvider()) { entry in
            if let d = entry.snap.nextPrayerDate {
                Label("\(entry.snap.nextPrayerName) \(timeStr(d))", systemImage: "moon.stars.fill")
                    .containerBackground(.clear, for: .widget)
            } else {
                Label("Prayer times", systemImage: "moon.stars.fill")
                    .containerBackground(.clear, for: .widget)
            }
        }
        .configurationDisplayName("Next Prayer")
        .description("Your next prayer, inline.")
        .supportedFamilies([.accessoryInline])
    }
}

struct LockSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockSummaryWidget", provider: SnapshotProvider()) { entry in
            let s = entry.snap
            VStack(alignment: .leading, spacing: 2) {
                Label("\(s.score)/5 today · \(s.prayersDone)/5 prayers", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                if let d = s.nextPrayerDate {
                    Label("\(s.nextPrayerName) \(timeStr(d))", systemImage: "moon.stars.fill")
                        .font(.system(size: 12))
                }
            }
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Day Summary")
        .description("Score, prayers and next prayer.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockFastingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockFastingWidget", provider: SnapshotProvider()) { entry in
            let s = entry.snap
            Gauge(value: fastProgress(s), in: 0...1) {
                Image(systemName: "timer")
            } currentValueLabel: {
                Text(s.fastingActive ? String(format: "%.0f", fastElapsedHours(s)) : "—")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Fasting")
        .description("Your fasting window progress.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockWeekProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockWeekProgressWidget", provider: SnapshotProvider()) { entry in
            let won = entry.snap.weekDaysWon
            Gauge(value: Double(won), in: 0...7) {
                Image(systemName: "trophy.fill")
            } currentValueLabel: {
                Text("\(won)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Week progress")
        .description("Days won this week.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockReadinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockReadinessWidget", provider: SnapshotProvider()) { entry in
            Gauge(value: Double(entry.snap.readiness), in: 0...100) {
                Image(systemName: "bolt.heart.fill")
            } currentValueLabel: {
                Text(entry.snap.readiness > 0 ? "\(entry.snap.readiness)" : "—")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Readiness")
        .description("Your readiness score.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockWeatherWidget", provider: SnapshotProvider()) { entry in
            let s = entry.snap
            Label(s.weatherCode >= 0 ? "\(Int(s.weatherTempC))° · \(s.weatherHeadline)" : "Weather",
                  systemImage: s.weatherSymbol.isEmpty ? "cloud.fill" : s.weatherSymbol)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Weather")
        .description("Conditions and outdoor advice.")
        .supportedFamilies([.accessoryInline])
    }
}

private func timeStr(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "h:mm"; return f.string(from: d)
}
