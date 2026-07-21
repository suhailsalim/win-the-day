import SwiftUI

/// Medication & supplement schedules. This screen records *what the user chose to schedule* and
/// how often they marked it taken. It never suggests a dose, a time, or a change to either.
struct RegimenEditorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Regimen?

    private var items: [Regimen] {
        store.data.regimens.sorted {
            $0.active == $1.active ? $0.name.lowercased() < $1.name.lowercased() : $0.active && !$1.active
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        if items.isEmpty {
                            Text("Nothing scheduled yet. Add what you already take and the app will keep the record — it never advises on doses.")
                                .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20).padding(.top, 24)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { idx, r in
                                    Button { editing = r } label: { row(r) }.buttonStyle(.plain)
                                    if idx < items.count - 1 { Hairline() }
                                }
                            }
                            .glassList()
                        }
                        Button { editing = Regimen() } label: {
                            Label("Add a medication or supplement", systemImage: "plus.circle.fill")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentDark)
                                .frame(maxWidth: .infinity).padding(.vertical, 14).glassList()
                        }
                        .buttonStyle(.plain).padding(.top, 16)

                        Text("Tracking only \u{2014} Win the Day records adherence and never gives dosing or interaction advice. Talk to your doctor or pharmacist about anything you take.")
                            .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16).padding(.top, 18)
                    }
                    .padding(16).padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Meds & supplements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .sheet(item: $editing) { RegimenDetailView(regimen: $0) }
        }
        .tint(Theme.accentDark)
    }

    private func row(_ r: Regimen) -> some View {
        HStack {
            Image(systemName: r.kind.symbol).font(.system(size: 14))
                .foregroundStyle(store.moduleColor("regimen")).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name.isEmpty ? "Untitled" : r.name).font(.system(size: 16)).foregroundStyle(Theme.ink)
                Text(r.active ? subtitle(r) : "Off").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
            }
            Spacer()
            if r.active, let a = store.regimenAdherence(r), a.scheduled > 0 {
                let pct = Int((Double(a.taken) / Double(a.scheduled) * 100).rounded())
                Text("\(pct)%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(pct < 80 ? Theme.coral : Theme.sage)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func subtitle(_ r: Regimen) -> String {
        var bits: [String] = []
        if !r.dose.isEmpty { bits.append(r.dose) }
        let slots = r.slots.map { $0.label.lowercased() }
        if !slots.isEmpty { bits.append(slots.joined(separator: " \u{00b7} ")) }
        bits.append(r.isDaily ? "daily" : RegimenDetailView.weekdaySummary(r.daysOfWeek))
        if r.withFood { bits.append("with food") }
        return bits.joined(separator: " \u{00b7} ")
    }
}

struct RegimenDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var regimen: Regimen
    @State private var startDate = Date()
    @State private var hasStart = false
    private var isNew: Bool { !store.data.regimens.contains { $0.id == regimen.id } }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Name").frame(width: 74, alignment: .leading).foregroundStyle(Theme.ink)
                                TextField("e.g. Vitamin D", text: $regimen.name).multilineTextAlignment(.trailing)
                            }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 13)
                            Hairline()
                            HStack {
                                Text("Dose").frame(width: 74, alignment: .leading).foregroundStyle(Theme.ink)
                                TextField("as prescribed / on the label", text: $regimen.dose).multilineTextAlignment(.trailing)
                            }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 13)
                            Hairline()
                            HStack {
                                Text("Type").font(.system(size: 16)).foregroundStyle(Theme.ink)
                                Spacer()
                                Picker("", selection: $regimen.kind) {
                                    ForEach(RegimenKind.allCases) { Text($0.label).tag($0) }
                                }.labelsHidden().tint(Theme.accentDark)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 6)
                        }
                        .glassList()

                        SectionHeader(text: "When")
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Times of day")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondaryInk)
                                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
                            FlowLayout(spacing: 8) {
                                ForEach(RegimenSlot.allCases) { slot in
                                    chip(slot.label, on: regimen.timesOfDay.contains(slot.rawValue)) { toggleSlot(slot) }
                                }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 12)
                            Hairline()
                            Text("Days")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondaryInk)
                                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
                            FlowLayout(spacing: 8) {
                                ForEach(Self.weekdaysInUserOrder(), id: \.self) { wd in
                                    chip(Self.shortSymbol(wd), on: regimen.daysOfWeek.contains(wd)) { toggleWeekday(wd) }
                                }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 12)
                            Hairline()
                            HStack {
                                Text("With food").foregroundStyle(Theme.ink)
                                Spacer()
                                ToggleRow(on: regimen.withFood) { regimen.withFood.toggle() }
                            }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 11)
                            Hairline()
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Reminders").foregroundStyle(Theme.ink)
                                    Text("A nudge at each time of day you picked.")
                                        .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                                }
                                Spacer()
                                ToggleRow(on: regimen.remind) { regimen.remind.toggle() }
                            }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 11)
                            Hairline()
                            HStack {
                                Text("Started on").foregroundStyle(Theme.ink)
                                Spacer()
                                if hasStart {
                                    DatePicker("", selection: $startDate, in: ...Date(), displayedComponents: .date)
                                        .labelsHidden().tint(Theme.accentDark)
                                }
                                ToggleRow(on: hasStart) { hasStart.toggle() }
                            }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 9)
                            Hairline()
                            HStack {
                                Text("Active").foregroundStyle(Theme.ink)
                                Spacer()
                                ToggleRow(on: regimen.active) { regimen.active.toggle() }
                            }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 11)
                        }
                        .glassList()

                        if !isNew, let a = store.regimenAdherence(regimen), a.scheduled > 0 {
                            let pct = Int((Double(a.taken) / Double(a.scheduled) * 100).rounded())
                            Text("Last 30 days: \(a.taken) of \(a.scheduled) scheduled doses marked (\(pct)%).")
                                .font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                                .padding(.horizontal, 6).padding(.top, 14)
                        }

                        if !isNew {
                            Button(role: .destructive) { store.deleteRegimen(regimen.id); dismiss() } label: {
                                Text("Delete").frame(maxWidth: .infinity)
                            }.padding(.top, 22)
                            Text("Past days keep their record.")
                                .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                                .frame(maxWidth: .infinity).padding(.top, 4)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isNew ? "New item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } }
            }
            .onAppear {
                hasStart = regimen.startEpoch > 0
                if regimen.startEpoch > 0 { startDate = Date(timeIntervalSince1970: regimen.startEpoch) }
            }
        }
        .tint(Theme.accentDark)
    }

    private var canSave: Bool {
        !regimen.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !regimen.timesOfDay.isEmpty && !regimen.daysOfWeek.isEmpty
    }

    private func save() {
        var r = regimen
        r.name = r.name.trimmingCharacters(in: .whitespaces)
        r.dose = r.dose.trimmingCharacters(in: .whitespaces)
        r.timesOfDay = RegimenSlot.sorted(r.timesOfDay).map(\.rawValue)   // keep canonical order
        r.startEpoch = hasStart ? Calendar.current.startOfDay(for: startDate).timeIntervalSince1970 : 0
        if isNew { store.addRegimen(r) } else { store.updateRegimen(r) }
        dismiss()
    }

    private func toggleSlot(_ slot: RegimenSlot) {
        if let i = regimen.timesOfDay.firstIndex(of: slot.rawValue) {
            guard regimen.timesOfDay.count > 1 else { return }   // at least one time of day
            regimen.timesOfDay.remove(at: i)
        } else {
            regimen.timesOfDay.append(slot.rawValue)
        }
    }

    private func toggleWeekday(_ wd: Int) {
        if regimen.daysOfWeek.contains(wd) {
            guard regimen.daysOfWeek.count > 1 else { return }   // at least one day
            regimen.daysOfWeek.remove(wd)
        } else {
            regimen.daysOfWeek.insert(wd)
        }
    }

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? .white : Theme.secondaryInk)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().fill(on ? Theme.accentDark : Theme.tertiaryInk.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Weekdays (stored 1–7 Sunday-based; only the *display* order follows the user's calendar)

    static func weekdaysInUserOrder() -> [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    static func shortSymbol(_ weekday: Int) -> String {
        let syms = Calendar.current.shortWeekdaySymbols
        guard weekday >= 1, weekday <= syms.count else { return "?" }
        return syms[weekday - 1]
    }

    static func weekdaySummary(_ days: Set<Int>) -> String {
        weekdaysInUserOrder().filter { days.contains($0) }.map { shortSymbol($0) }.joined(separator: " ")
    }
}
