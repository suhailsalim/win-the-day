import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var health: HealthManager
    @EnvironmentObject var fasting: FastingManager
    @State private var confirmReset = false

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
                    case .settings: SettingsView(confirmReset: $confirmReset)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

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
        .confirmationDialog("Reset all data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) { store.reset() }
            Button("Keep my data", role: .cancel) {}
        } message: {
            Text("This clears every entry on this device. Export a backup first if you\u{2019}re unsure.")
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
                    .foregroundStyle(tab == item.tab ? Theme.accentDark : Color(white: 0.54))
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
                        .fill(Color.white.opacity(0.44))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5)
        )
        .shadow(color: Color(hex: 0x50371E).opacity(0.18), radius: 17, x: 0, y: 10)
    }
}
