import ActivityKit
import WidgetKit
import SwiftUI

// Uses shared StudyActivityAttributes (member of app + widget targets).

struct StudyLiveActivityWidget: Widget {
    private let purple = Color(red: 0.36, green: 0.26, blue: 0.88)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyActivityAttributes.self) { context in
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(purple.opacity(0.18))
                    Image(systemName: "books.vertical.fill").foregroundStyle(purple)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.subject.isEmpty ? "Studying" : context.state.subject).font(.headline)
                    Text(context.state.paused ? "Paused" : "In progress")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                timeView(context.state).font(.system(.title2, design: .rounded)).monospacedDigit()
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.96, green: 0.92, blue: 0.86))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.subject.isEmpty ? "Study" : context.state.subject, systemImage: "books.vertical.fill")
                        .foregroundStyle(purple)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timeView(context.state).monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "books.vertical.fill").foregroundStyle(purple)
            } compactTrailing: {
                timeView(context.state).monospacedDigit().frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "books.vertical.fill").foregroundStyle(purple)
            }
        }
    }

    @ViewBuilder
    private func timeView(_ s: StudyActivityAttributes.ContentState) -> some View {
        if s.paused {
            Text(fmt(s.pausedElapsed))
        } else {
            // Live-counting timer from (now - baseSeconds).
            Text(Date(timeIntervalSinceNow: -s.baseSeconds), style: .timer)
        }
    }

    private func fmt(_ t: Double) -> String {
        let s = Int(t); return String(format: "%d:%02d:%02d", s/3600, (s%3600)/60, s%60)
    }
}
