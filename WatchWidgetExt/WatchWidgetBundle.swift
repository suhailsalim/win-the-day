import WidgetKit
import SwiftUI

@main
struct WatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchScoreComplication()
        WatchRingComplication()
        WatchPrayerComplication()
        WatchWeekComplication()
        WatchFastingComplication()
        WatchSessionComplication()
        WatchReadinessComplication()
        WatchWeatherComplication()
        WatchSummaryComplication()
    }
}
