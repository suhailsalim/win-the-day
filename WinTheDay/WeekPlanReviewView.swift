import SwiftUI

struct WeekPlanReviewView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var calendar: CalendarManager
    @Environment(\.dismiss) private var dismiss
    @State private var applied = 0

    private let weekdayNames = ["Today", "Tomorrow"]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if store.planLoading {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("Building your week…").font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                            }.padding(.top, 60)
                        } else if store.planDraft.isEmpty {
                            Text("Couldn\u{2019}t generate a plan. Check your AI provider in Settings and try again.")
                                .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                                .multilineTextAlignment(.center).padding(.top, 60).padding(.horizontal, 20)
                        } else {
                            Text("Review your AI week. Toggle off anything you don\u{2019}t want, then apply — it creates sessions, reminders and calendar events.")
                                .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(0..<7, id: \.self) { day in
                                let blocks = store.planDraft.filter { $0.day == day }
                                if !blocks.isEmpty { daySection(day, blocks) }
                            }
                        }
                    }
                    .padding(16).padding(.bottom, 30)
                }
            }
            .navigationTitle("AI week plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(Theme.tertiaryInk) }
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.planDraft.isEmpty {
                        Button("Apply") {
                            applied = store.applyWeekPlan(calendar: calendar)
                            dismiss()
                        }.font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accentDark)
                    }
                }
            }
        }
    }

    private func daySection(_ day: Int, _ blocks: [PlanBlock]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(text: dayLabel(day), color: Theme.accentDark)
            VStack(spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, b in
                    HStack(spacing: 11) {
                        IconTile(symbol: ScheduledSession.symbol(AppStore.displayKind(b.kind)),
                                 colors: [Theme.accent, Color(hex: 0x3B4A7C)], size: 28, corner: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.title.isEmpty ? ScheduledSession.label(b.kind) : b.title)
                                .font(.system(size: 15)).foregroundStyle(b.enabled ? Theme.ink : Theme.tertiaryInk)
                            Text("\(timeStr(b)) · \(b.durationMin)m").font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk)
                        }
                        Spacer()
                        Toggle("", isOn: bindingFor(b)).labelsHidden().tint(Theme.sage)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    if idx < blocks.count - 1 { Hairline() }
                }
            }
            .glassList()
        }
    }

    private func bindingFor(_ b: PlanBlock) -> Binding<Bool> {
        Binding(
            get: { store.planDraft.first { $0.id == b.id }?.enabled ?? false },
            set: { v in if let i = store.planDraft.firstIndex(where: { $0.id == b.id }) { store.planDraft[i].enabled = v } }
        )
    }

    private func dayLabel(_ day: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: day, to: Date()) ?? Date()
        if day == 0 { return "Today" }
        if day == 1 { return "Tomorrow" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEEE d"
        return f.string(from: d)
    }

    private func timeStr(_ b: PlanBlock) -> String {
        var c = DateComponents(); c.hour = b.hour; c.minute = b.minute
        let d = Calendar.current.date(from: c) ?? Date()
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }
}
