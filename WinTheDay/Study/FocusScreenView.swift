import SwiftUI
import UserNotifications

/// ADHD-friendly full-screen focus mode: one task at a time (Now/Next), a depleting ring instead
/// of a ticking number, and gentle presets — not the classic 25/5 Pomodoro, which is often too
/// short to get into a task. Runs on the existing `StudyTimer` engine (so it gets the same Live
/// Activity + `Entry.studyHours` tracking as a study/work session — a completed focus block IS a
/// tracked-hours session, just entered from a friendlier screen).
struct FocusScreenView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var studyTimer: StudyTimer
    @Environment(\.dismiss) private var dismiss

    @State private var taskName = ""
    @State private var newTaskText = ""
    @AppStorage("focus_duration_min") private var durationMin = 45

    private static let presets = [25, 45, 50, 60]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        if studyTimer.running {
                            runningState
                        } else {
                            idleState
                        }
                    }
                    .padding(20).padding(.top, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.foregroundStyle(Theme.accentDark) } }
            .onAppear { if taskName.isEmpty { taskName = store.focusQueue.first ?? "" } }
        }
        .tint(Theme.accentDark)
    }

    // MARK: Idle — pick a task + duration, start

    private var idleState: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("What's the ONE thing?").font(Theme.serif(22)).foregroundStyle(Theme.ink)
                Text("Pick a single task — you can queue the rest below.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk).multilineTextAlignment(.center)
            }
            TextField("e.g. Write the intro paragraph", text: $taskName)
                .font(.system(size: 16)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surfaceOverlay))

            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.self) { m in
                    Button { durationMin = m } label: {
                        Text("\(m)m").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(durationMin == m ? Theme.onAccent : Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Capsule().fill(durationMin == m ? AnyShapeStyle(Theme.accentDark) : AnyShapeStyle(Theme.surfaceOverlay)))
                    }.buttonStyle(.plain)
                }
            }

            Button { start() } label: {
                Label("Start focusing", systemImage: "play.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accentDark))
            }.buttonStyle(.plain).disabled(taskName.trimmingCharacters(in: .whitespaces).isEmpty)

            nextUpSection
        }
    }

    private var nextUpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEXT UP").font(.system(size: 11, weight: .semibold)).tracking(0.3).foregroundStyle(Theme.tertiaryInk)
            ForEach(store.focusQueue.filter { $0 != taskName }, id: \.self) { t in
                HStack {
                    Text(t).font(.system(size: 14)).foregroundStyle(Theme.ink)
                    Spacer()
                    Button { taskName = t } label: {
                        Text("Now").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentDark)
                    }.buttonStyle(.plain)
                    Button { store.removeFocusTask(t) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.tertiaryInk)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceOverlay))
            }
            HStack {
                TextField("Add a task to queue", text: $newTaskText)
                    .font(.system(size: 14)).padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceOverlay))
                Button {
                    store.addFocusTask(newTaskText); newTaskText = ""
                } label: { Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.accentDark) }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: Running — depleting ring, single task, gentle controls

    private var runningState: some View {
        let target = Double(durationMin * 60)
        let fraction = target > 0 ? min(1, studyTimer.elapsed / target) : 0
        let remaining = max(0, target - studyTimer.elapsed)
        return VStack(spacing: 22) {
            RingGaugeView(fraction: fraction, value: timeFmt(remaining), label: studyTimer.paused ? "paused" : "left",
                         color: Theme.accentDark, size: 220, lineWidth: 16)
                .padding(.top, 12)
            Text(studyTimer.subject.isEmpty ? "Focusing" : studyTimer.subject)
                .font(Theme.serif(20)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button(studyTimer.paused ? "Resume" : "Pause") {
                    studyTimer.paused ? studyTimer.resume() : studyTimer.pause()
                }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentDark)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent.opacity(0.18)))
                Button("Done") { finish() }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accentDark))
            }
            if !store.focusQueue.filter({ $0 != studyTimer.subject }).isEmpty {
                Text("Next: \(store.focusQueue.first { $0 != studyTimer.subject } ?? "")")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk)
            }
        }
    }

    private func timeFmt(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func start() {
        let t = taskName.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        studyTimer.start(subject: t)
        store.removeFocusTask(t)
        scheduleGentleNudge(after: TimeInterval(durationMin * 60))
    }

    private func finish() {
        let mins = studyTimer.stop()
        store.logStudySession(subject: studyTimer.subject, minutes: mins)
        taskName = store.focusQueue.first ?? ""
    }

    /// One local notification when the preset elapses — a nudge, not an interruption; the
    /// session keeps running past it, same as the existing study timer.
    private func scheduleGentleNudge(after seconds: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Focus block done \u{1F44F}"
        content.body = "Take a breath — stop and log it, or keep going if you're in flow."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(5, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: "focus-block-done", content: content, trigger: trigger))
    }
}
