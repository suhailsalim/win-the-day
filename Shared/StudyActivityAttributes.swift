import Foundation
import ActivityKit

/// Shared between the app and the widget extension for the study-session Live Activity.
struct StudyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var subject: String
        var startedAt: Date          // when the (current run) started
        var baseSeconds: Double      // accumulated seconds before the current run
        var paused: Bool
        var pausedElapsed: Double    // total seconds when paused (frozen display)
    }
    var title: String
}
