import ActivityKit
import WidgetKit
import SwiftUI

// NOTE: PrayerActivityAttributes.swift (in the app) must also be a member of this widget target.

struct PrayerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerActivityAttributes.self) { context in
            // Lock screen / banner
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color(red: 0.78, green: 0.53, blue: 0.24).opacity(0.18))
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(Color(red: 0.78, green: 0.53, blue: 0.24))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.attributes.prayerName) time")
                        .font(.headline)
                    Text("Adhan at \(context.attributes.startDate, format: .dateTime.hour().minute())")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(.system(.title3, design: .rounded)).monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70)
                    Text("left").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.96, green: 0.92, blue: 0.86))
            .activitySystemActionForegroundColor(Color(red: 0.11, green: 0.11, blue: 0.12))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.prayerName, systemImage: "moon.stars.fill")
                        .foregroundStyle(Color(red: 0.78, green: 0.53, blue: 0.24))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .monospacedDigit().frame(maxWidth: 60)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Time for \(context.attributes.prayerName) 🕌")
                }
            } compactLeading: {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Color(red: 0.78, green: 0.53, blue: 0.24))
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                    .monospacedDigit().frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Color(red: 0.78, green: 0.53, blue: 0.24))
            }
        }
    }
}
