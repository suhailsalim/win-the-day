import SwiftUI
@preconcurrency import UserNotifications

/// Routes a tapped `winddown-` notification to the wind-down sheet. Kept tiny on purpose: the app
/// had no `UNUserNotificationCenter` delegate at all, and this one only ever answers the question
/// "did the user open us from the wind-down nudge?".
@MainActor
final class WindDownRouter: NSObject, ObservableObject {
    /// Flips true when the wind-down notification is tapped; `TodayView` presents the sheet on it.
    @Published var open = false

    func start() { UNUserNotificationCenter.current().delegate = self }
}

// `@preconcurrency` so this `@MainActor` type can satisfy the SDK's non-isolated delegate
// requirement (AGENTS.md: notification callbacks are the usual strict-concurrency snag).
extension WindDownRouter: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix(AppStore.windDownIDPrefix) {
            open = true
        }
        completionHandler()
    }
}

/// The evening ritual, three short pages: close today, check in with the body, name tomorrow's one
/// thing. Everything renders from live store state — page 1's habit taps write straight through, so
/// a snapshot taken at open would go stale the moment the user ticks something.
struct WindDownView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var health: HealthManager
    @EnvironmentObject var hydration: HydrationManager
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    @State private var checkIn = DayCheckIn()
    @State private var focus = ""
    /// The day this run is planning for, frozen at open so a wind-down that crosses midnight
    /// doesn't quietly re-target while the sheet is up.
    @State private var targetDay = ""

    private static let intensity = ["None", "Mild", "Moderate", "High"]
    private static let moodWords = ["Low", "Meh", "Good", "Great"]
    private static let drinkWords = ["None", "1", "2", "3+"]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                VStack(spacing: 0) {
                    TabView(selection: $page) {
                        pageScroll { todayPage }.tag(0)
                        pageScroll { bodyPage }.tag(1)
                        pageScroll { tomorrowPage }.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    footer
                }
            }
            .navigationTitle("Wind down")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { dismiss() }.foregroundStyle(Theme.tertiaryInk)
                }
            }
        }
        .presentationDetents([.large])
        .task {
            // The ritual is always about the day being lived — the user may have been reading an
            // older day when the nudge arrived.
            if !store.isToday { store.goTo(date: Date()) }
            targetDay = store.windDownTargetDate
            checkIn = store.draft.checkIn
            focus = store.mainFocus(for: targetDay)
        }
    }

    private func pageScroll<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 14) { content() }.padding(16).padding(.bottom, 24) }
    }

    // MARK: - Page 1 — today

    @ViewBuilder private var todayPage: some View {
        let msg = store.scoreMessage(store.draftScore)
        Text("How today actually went — anything still open is one tap away.")
            .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk).padding(.horizontal, 4)

        GlassCard(padding: 16) {
            HStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(store.draftScore)").font(Theme.serif(40)).foregroundStyle(msg.color)
                    Text("/\(store.habitTotal)").font(.system(size: 19)).foregroundStyle(Theme.quaternaryInk)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(msg.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(msg.sub).font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 0)
            }
        }

        let open = store.activeHabits.filter { !store.isSatisfied($0, store.draft) }
        if open.isEmpty {
            GlassCard(padding: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 14)).foregroundStyle(Theme.sage)
                    Text("Every habit is closed. Good day.").font(.system(size: 14)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
            }
        } else {
            Text("STILL OPEN").font(.system(size: 11, weight: .semibold)).tracking(0.3)
                .foregroundStyle(Theme.tertiaryInk).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(open.enumerated()), id: \.element.id) { idx, def in
                    openHabitRow(def)
                    if idx < open.count - 1 { Hairline() }
                }
            }
            .glassList()
        }

        let gaps = numberGaps
        if !gaps.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(gaps.enumerated()), id: \.offset) { idx, gap in
                    HStack {
                        Text(gap.0).font(.system(size: 15)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(gap.1).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondaryInk)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    if idx < gaps.count - 1 { Hairline() }
                }
            }
            .glassList()
        }
    }

    /// Water and protein, as a plain "how far short" line each. Nothing to tap — logging those lives
    /// on the Today screen, and the wind-down is for noticing, not for a second data-entry surface.
    private var numberGaps: [(String, String)] {
        var out: [(String, String)] = []
        let waterGap = max(0, hydration.targetMl - store.waterMl)
        out.append(("Water", waterGap == 0 ? "Target hit 💧" : "\(waterGap) ml short"))
        let protein = Double(store.draft.proteinG) ?? 0
        let target = store.targets.protein
        if target > 0 {
            let gap = Int((target - protein).rounded())
            out.append(("Protein", gap <= 0 ? "Target hit" : "\(gap)g short of \(Int(target))g"))
        }
        return out
    }

    private func openHabitRow(_ def: HabitDef) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(def.title).font(.system(size: 16)).foregroundStyle(Theme.ink)
                if def.link.isAuto {
                    Text("Auto · \(def.link.label)").font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                }
            }
            Spacer()
            if def.link == .manual {
                ToggleRow(on: false) { store.toggleHabit(def) }
            } else {
                Image(systemName: "circle").font(.system(size: 22))
                    .foregroundStyle(Theme.tertiaryInk.opacity(0.3))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    // MARK: - Page 2 — body (same fields, same write path, as CheckInSheet)

    @ViewBuilder private var bodyPage: some View {
        Text("How you actually feel today — it adjusts Readiness by a few points at most, never more.")
            .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk).padding(.horizontal, 4)

        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                scaleRow("Soreness", Self.intensity, $checkIn.soreness)
                scaleRow("Stress", Self.intensity, $checkIn.stress)
                scaleRow("Mood", Self.moodWords, $checkIn.mood)
            }
        }

        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                scaleRow("Alcohol", Self.drinkWords, $checkIn.alcohol)
                Hairline()
                Toggle(isOn: $checkIn.lateCaffeine) {
                    Text("Caffeine after ~2pm").font(.system(size: 15)).foregroundStyle(Theme.ink)
                }
                Toggle(isOn: $checkIn.illness) {
                    Text("Feeling ill").font(.system(size: 15)).foregroundStyle(Theme.ink)
                }
            }
            .tint(Theme.accentDark)
        }
    }

    private func scaleRow(_ label: String, _ words: [String], _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text(words[min(max(0, value.wrappedValue), words.count - 1)])
                    .font(.system(size: 13)).foregroundStyle(Theme.tertiaryInk)
            }
            HStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                    let on = value.wrappedValue == idx
                    Button { value.wrappedValue = idx } label: {
                        Text(word).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(on ? Theme.accentDark : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surfaceOverlay).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
        }
    }

    // MARK: - Page 3 — tomorrow

    @ViewBuilder private var tomorrowPage: some View {
        Text("One thing for \(targetDayLabel). Pick the thing that would make it a win on its own.")
            .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk).padding(.horizontal, 4)

        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Main focus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                TextField("e.g. finish the physiology deck", text: $focus, axis: .vertical)
                    .font(.system(size: 16)).foregroundStyle(Theme.ink)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.sentences)
            }
        }

        if let plan = store.sleepPlanTonight {
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 12)).foregroundStyle(Theme.accentDark)
                        Text("Tonight's plan").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                    }
                    Text(String(format: "Aim for %.1fh — bedtime around %@", plan.needHours,
                                clockStr(Date(timeIntervalSince1970: plan.recommendedBedEpoch))))
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                    Text("Dinner cutoff was \(clockStr(Date(timeIntervalSince1970: plan.dinnerCutoffEpoch))).")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
            }
        }
    }

    /// "tomorrow" normally, but after midnight the day being planned is the calendar day we're
    /// already in — say so rather than lying about it.
    private var targetDayLabel: String {
        targetDay == AppStore.dateString(Date()) ? "today" : "tomorrow"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if page > 0 {
                Button { withAnimation { page -= 1 } } label: {
                    Text("Back").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentDark)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Capsule().fill(Theme.accentDark.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            Button {
                if page < 2 { withAnimation { page += 1 } } else { finish() }
            } label: {
                Text(page < 2 ? "Next" : "Done").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Capsule().fill(Theme.accentDark))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    /// Save both halves and leave. Nothing here runs when the sheet is skipped or swiped away.
    private func finish() {
        if checkIn != store.draft.checkIn {
            store.updateCheckIn(checkIn)
            Task { await store.computeReadiness(for: store.date, health: health) }
        }
        if !targetDay.isEmpty { store.setMainFocus(focus, for: targetDay) }
        dismiss()
    }

    private func clockStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}
