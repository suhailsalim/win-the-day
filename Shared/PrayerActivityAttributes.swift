import Foundation
import ActivityKit

/// Shared between the app and the Widget Extension. When you add the widget target in Xcode,
/// add THIS file to the widget target too (File Inspector → Target Membership).
struct PrayerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endDate: Date          // when the 20-minute window closes
    }
    var prayerName: String
    var startDate: Date            // when the adhan began
}
