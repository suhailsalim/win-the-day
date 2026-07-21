import WidgetKit
import SwiftUI

@main
struct PrayerWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextPrayerWidget()
        NonNegotiablesWidget()
        SummaryWidget()
        RingStripWidget()
        SingleRingWidget()
        FastingWidget()
        WeekProgressWidget()
        ReadinessWidget()
        WeatherWidget()
        NextSessionWidget()
        UpcomingEventWidget()
        HydrationWidget()
        LockNonNegotiablesWidget()
        LockNextPrayerWidget()
        LockSummaryWidget()
        LockFastingWidget()
        LockWeekProgressWidget()
        LockReadinessWidget()
        LockWeatherWidget()
        PrayerLiveActivityWidget()
        StudyLiveActivityWidget()
    }
}
