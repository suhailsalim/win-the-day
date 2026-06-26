import WidgetKit
import SwiftUI

@main
struct WatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchScoreComplication()
        WatchPrayerComplication()
        WatchWeekComplication()
        WatchFastingComplication()
        WatchSessionComplication()
        WatchReadinessComplication()
        WatchWeatherComplication()
        WatchSummaryComplication()
    }
}
