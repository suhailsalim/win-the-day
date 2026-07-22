import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var health: HealthManager
    @EnvironmentObject var fasting: FastingManager

    var body: some View {
        ZStack(alignment: .bottom) {
            WarmBackground()

            ScrollView {
                Group {
                    switch store.tab {
                    case .today:    TodayView()
                    case .plan:     PlanView()
                    case .trends:   TrendsView()
                    case .health:   HealthView()
                    case .settings: SettingsView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
                // Pin the content to exactly the scroll viewport's width. A vertical ScrollView
                // otherwise lets a single child that refuses the proposed width (a fixed frame, a
                // Chart, etc.) make the whole content wider than the screen — which is what allowed
                // the entire page (and tab bar) to pan/rubber-band sideways. Clamping here means any
                // stray over-wide subview is clipped instead of becoming horizontally scrollable.
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Re-identify the scroll view per tab so switching tabs starts at the top instead of
            // inheriting the previous tab's scroll offset.
            .id(store.tab)

            TabBar(tab: $store.tab)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
        .task {
            if store.settings.healthkit { await health.requestAuthorization() }
            store.scheduleWeeklyReviewNotification()
            PhoneSync.shared.onAction = { action, amount, name in
                switch action {
                case "fast_start": fasting.startFast()
                case "fast_end": fasting.endFast()
                default: store.applyWatchAction(action, amount: amount, name: name)
                }
            }
            PhoneSync.shared.activate()
        }
        .fullScreenCover(isPresented: .constant(!store.onboardingDone)) {
            OnboardingView()
        }
    }
}

// MARK: - Floating glass tab bar

struct TabBar: View {
    @Binding var tab: Tab
    @Namespace private var ns

    private let items: [(tab: Tab, label: String, symbol: String)] = [
        (.today, "Today", "checkmark.circle"),
        (.plan, "Plan", "calendar"),
        (.trends, "Trends", "chart.line.uptrend.xyaxis"),
        (.health, "Health", "heart"),
        (.settings, "Settings", "slider.horizontal.3")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { tab = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 20, weight: .regular))
                        Text(item.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(tab == item.tab ? Theme.accentDark : Theme.tertiaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if tab == item.tab {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Theme.accent.opacity(0.22))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 0.5)
                                )
                                .matchedGeometryEffect(id: "cap", in: ns)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Theme.surfaceOverlay)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 0.5)
        )
        .shadow(color: Theme.adaptive(light: 0x2A3350, darkGrey: 0x000000).opacity(0.18), radius: 17, x: 0, y: 10)
    }
}
