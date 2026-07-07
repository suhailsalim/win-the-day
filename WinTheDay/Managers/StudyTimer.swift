import Foundation
import SwiftUI
import ActivityKit

/// Drives a study/work session: start/pause/resume/stop, with a Live Activity countdown-up.
@MainActor
final class StudyTimer: ObservableObject {
    @Published var running = false
    @Published var paused = false
    @Published var subject = ""
    @Published var elapsed: TimeInterval = 0

    private var runStart: Date?
    private var accumulated: TimeInterval = 0
    private var ticker: Timer?
    private var activity: Activity<StudyActivityAttributes>?

    func start(subject: String) {
        guard !running else { return }
        self.subject = subject
        accumulated = 0
        runStart = Date()
        running = true; paused = false; elapsed = 0
        startTicker()
        startActivity()
    }

    func pause() {
        guard running, !paused, let s = runStart else { return }
        accumulated += Date().timeIntervalSince(s)
        runStart = nil
        paused = true
        elapsed = accumulated
        ticker?.invalidate()
        updateActivity()
    }

    func resume() {
        guard running, paused else { return }
        runStart = Date()
        paused = false
        startTicker()
        updateActivity()
    }

    /// Stops and returns whole minutes studied.
    @discardableResult
    func stop() -> Int {
        if let s = runStart { accumulated += Date().timeIntervalSince(s) }
        let minutes = Int((accumulated / 60).rounded())
        ticker?.invalidate(); ticker = nil
        endActivity()
        running = false; paused = false; runStart = nil
        let result = minutes
        accumulated = 0; elapsed = 0; subject = ""
        return result
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let s = runStart else { return }
        elapsed = accumulated + Date().timeIntervalSince(s)
    }

    // MARK: - Live Activity

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = StudyActivityAttributes.ContentState(
            subject: subject, startedAt: Date(), baseSeconds: 0, paused: false, pausedElapsed: 0)
        do {
            activity = try Activity.request(
                attributes: StudyActivityAttributes(title: "Study session"),
                content: ActivityContent(state: state, staleDate: nil))
        } catch { activity = nil }
    }

    private func updateActivity() {
        guard let activity else { return }
        let state = StudyActivityAttributes.ContentState(
            subject: subject,
            startedAt: runStart ?? Date(),
            baseSeconds: accumulated,
            paused: paused,
            pausedElapsed: elapsed)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func endActivity() {
        guard let activity else { return }
        let a = activity
        self.activity = nil
        Task { await a.end(nil, dismissalPolicy: ActivityUIDismissalPolicy.immediate) }
    }
}
