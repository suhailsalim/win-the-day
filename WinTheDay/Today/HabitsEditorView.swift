import SwiftUI

struct HabitsEditorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: HabitDef?

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Pillar.allCases) { pillar in
                            let items = store.data.habits.filter { $0.pillar == pillar }.sorted { $0.order < $1.order }
                            if !items.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: pillar.icon).font(.system(size: 11)).foregroundStyle(Color(hex: pillar.hex))
                                    SectionHeader(text: pillar.title)
                                }
                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, h in
                                        Button { editing = h } label: { row(h) }.buttonStyle(.plain)
                                        if idx < items.count - 1 { Hairline() }
                                    }
                                }
                                .glassList()
                            }
                        }
                        Button { editing = HabitDef(title: "", pillar: .custom) } label: {
                            Label("Add a non-negotiable", systemImage: "plus.circle.fill")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentDark)
                                .frame(maxWidth: .infinity).padding(.vertical, 14).glassList()
                        }
                        .buttonStyle(.plain).padding(.top, 16)
                    }
                    .padding(16).padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Non-negotiables")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .sheet(item: $editing) { HabitDetailView(habit: $0) }
        }
        .tint(Theme.accentDark)
    }

    private func row(_ h: HabitDef) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(h.title.isEmpty ? "Untitled" : h.title).font(.system(size: 16)).foregroundStyle(Theme.ink)
                Text(h.active ? h.link.label : "Off").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct HabitDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var habit: HabitDef
    private var isNew: Bool { !store.data.habits.contains { $0.id == habit.id } }

    private let prayerNames = ["fajr", "dhuhr", "asr", "maghrib", "isha"]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Title").frame(width: 70, alignment: .leading).foregroundStyle(Theme.ink)
                                TextField("e.g. Revise 1 subject", text: $habit.title).multilineTextAlignment(.trailing)
                            }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 13)
                            Hairline()
                            pickerRow("Pillar") {
                                Picker("", selection: $habit.pillar) {
                                    ForEach(Pillar.allCases) { Text($0.title).tag($0) }
                                }.labelsHidden().tint(Theme.accentDark)
                            }
                            Hairline()
                            pickerRow("Completes by") {
                                Picker("", selection: $habit.link) {
                                    ForEach(HabitLinkType.allCases) { Text($0.label).tag($0) }
                                }.labelsHidden().tint(Theme.accentDark)
                            }
                            if habit.link == .prayer {
                                Hairline()
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Prayers required")
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondaryInk)
                                        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                                    Text("This goal auto-closes once every prayer below is marked.")
                                        .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                                        .padding(.horizontal, 16).padding(.bottom, 8)
                                    ForEach(prayerNames, id: \.self) { p in
                                        Button { toggleRequiredPrayer(p) } label: {
                                            HStack {
                                                Text(p.capitalized).foregroundStyle(Theme.ink)
                                                Spacer()
                                                Image(systemName: habit.prayerNames.contains(p) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(habit.prayerNames.contains(p) ? Theme.accentDark : Color(white: 0.27).opacity(0.3))
                                            }
                                            .font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 10)
                                        }.buttonStyle(.plain)
                                        if p != prayerNames.last { Hairline() }
                                    }
                                }
                                .onAppear { if habit.prayerNames.isEmpty { habit.prayerNames = [habit.prayerName] } }
                            }
                            if habit.link == .steps || habit.link == .activeEnergy || habit.link == .studyHours || habit.link == .quran {
                                Hairline()
                                HStack {
                                    Text(thresholdLabel).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Theme.ink)
                                    TextField("target", value: $habit.threshold, format: .number)
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                                }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 13)
                            }
                            Hairline()
                            HStack {
                                Text("Active (counts to score)").foregroundStyle(Theme.ink)
                                Spacer()
                                ToggleRow(on: habit.active) { habit.active.toggle() }
                            }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 11)
                        }
                        .glassList()

                        if !isNew {
                            Button(role: .destructive) { store.deleteHabit(habit.id); dismiss() } label: {
                                Text("Delete").frame(maxWidth: .infinity)
                            }.padding(.top, 22)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isNew ? "New habit" : "Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if isNew { store.addHabit(habit) } else { store.updateHabit(habit) }
                        dismiss()
                    }.fontWeight(.semibold).disabled(habit.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } }
            }
        }
        .tint(Theme.accentDark)
    }

    private func toggleRequiredPrayer(_ p: String) {
        if habit.prayerNames.contains(p) {
            guard habit.prayerNames.count > 1 else { return }   // a goal must require at least one prayer
            habit.prayerNames.removeAll { $0 == p }
        } else {
            habit.prayerNames.append(p)
        }
    }

    private var thresholdLabel: String {
        switch habit.link {
        case .steps: return "Steps target"
        case .activeEnergy: return "Active kcal target"
        case .studyHours: return "Study hours target"
        case .quran: return "Qur'an pages target (0 = khatmah pace)"
        default: return "Target"
        }
    }

    private func pickerRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer()
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }
}
