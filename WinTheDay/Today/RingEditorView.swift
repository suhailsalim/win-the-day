import SwiftUI

/// Choose which 3–4 rings show on Today, reorder them, and manage custom rings.
struct RingEditorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var creatingRing: RingDef?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Rings shown on Today", selection: Binding(
                        get: { store.settings.visibleRingCount },
                        set: { store.setVisibleRingCount($0) })) {
                        Text("3").tag(3)
                        Text("4").tag(4)
                        Text("5").tag(5)
                        Text("6").tag(6)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("All your rings are kept — this just picks how many show at once. 5 or 6 wrap onto a second row. Reorder below to choose which ones.")
                }
                Section {
                    ForEach(store.allRingsOrdered) { ring in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ring.displayTitle).font(.system(size: 16))
                                    .foregroundStyle(ring.enabled ? Theme.ink : Theme.tertiaryInk)
                                Text(ring.source == .custom ? ring.metric.label : "Built-in")
                                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { ring.enabled },
                                set: { store.setRingEnabled(ring.id, $0) }))
                                .labelsHidden().tint(Theme.sage)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if ring.source == .custom { creatingRing = ring } }
                        .swipeActions(edge: .trailing) {
                            if ring.source == .custom {
                                Button(role: .destructive) { store.deleteRing(ring.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                    .onMove { offs, dest in store.moveRing(from: offs, to: dest) }
                } footer: {
                    Text("Drag to reorder. Only the first \(store.settings.visibleRingCount) enabled rings show on Today. Tap a custom ring to edit it.")
                }
                Section {
                    Button { creatingRing = RingDef(source: .custom) } label: {
                        Label("Add a custom ring", systemImage: "plus.circle.fill")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(WarmBackground())
            .navigationTitle("Rings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .sheet(item: $creatingRing) { RingCreatorView(ring: $0) }
        }
        .tint(Theme.accentDark)
    }
}

/// Create/edit a custom ring: which local metric it tracks, its goal, title and color.
struct RingCreatorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var ring: RingDef
    private var isNew: Bool { !store.data.rings.contains { $0.id == ring.id } }

    private static let swatches: [UInt] = [0xD86B4A, 0x3B4A7C, 0xE0B341, 0x6FA84A, 0x2E8AE0, 0x6E7BFF, 0x9C5FE0, 0xE05F9C]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Title").frame(width: 70, alignment: .leading).foregroundStyle(Theme.ink)
                                TextField(ring.metric.label, text: $ring.title).multilineTextAlignment(.trailing)
                            }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 13)
                            Hairline()
                            HStack {
                                Text("Tracks").font(.system(size: 16)).foregroundStyle(Theme.ink)
                                Spacer()
                                Picker("", selection: $ring.metric) {
                                    ForEach(RingMetric.allCases.filter { $0 != .unknown && $0.isAvailable }) { m in
                                        Text(m.label).tag(m)
                                    }
                                }.labelsHidden().tint(Theme.accentDark)
                            }.padding(.horizontal, 16).padding(.vertical, 6)
                            if ring.metric.usesGoal {
                                Hairline()
                                HStack {
                                    Text(goalLabel).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Theme.ink)
                                    TextField("goal", value: $ring.goal, format: .number)
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                                }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 13)
                            }
                            Hairline()
                            HStack {
                                Text("Color").font(.system(size: 16)).foregroundStyle(Theme.ink)
                                Spacer()
                                HStack(spacing: 8) {
                                    swatchButton(0)   // "auto" — derive from the score band
                                    ForEach(Self.swatches, id: \.self) { swatchButton($0) }
                                }
                            }.padding(.horizontal, 16).padding(.vertical, 10)
                        }
                        .glassList()

                        if !isNew {
                            Button(role: .destructive) { store.deleteRing(ring.id); dismiss() } label: {
                                Text("Delete").frame(maxWidth: .infinity)
                            }.padding(.top, 22)
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isNew ? "New ring" : "Edit ring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if isNew { store.addRing(ring) } else { store.updateRing(ring) }
                        dismiss()
                    }.fontWeight(.semibold).disabled(ring.metric == .unknown)
                }
            }
        }
        .tint(Theme.accentDark)
    }

    private func swatchButton(_ hex: UInt) -> some View {
        Button { ring.colorHex = hex } label: {
            Circle()
                .fill(hex == 0 ? AnyShapeStyle(Theme.tertiaryInk.opacity(0.2)) : AnyShapeStyle(Color(hex: hex)))
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Theme.ink, lineWidth: ring.colorHex == hex ? 2 : 0))
        }.buttonStyle(.plain)
    }

    private var goalLabel: String {
        switch ring.metric {
        case .hydrationPct: return "Goal (ml)"
        case .studyGoalPct: return "Goal (hours)"
        case .proteinPct: return "Goal (g)"
        case .stepsPct: return "Goal (steps)"
        case .caloriesPct: return "Budget (kcal)"
        default: return "Goal"
        }
    }
}

extension RingMetric {
    /// Steps/calories/hydration etc. read their target straight from the app's daily targets, so
    /// the per-ring goal field only shows where it actually does something.
    var usesGoal: Bool { self != .habitsPct }
}

/// Big ring + caption for one ring, opened by tapping it on Today.
struct RingDetailView: View {
    let ring: RingDef
    let result: RingResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                VStack(spacing: 18) {
                    RingGaugeView(fraction: result.fraction, value: result.displayValue, label: ring.displayTitle,
                                 color: Theme.accentDark, available: result.available, size: 180, lineWidth: 22)
                        .padding(.top, 30)
                    Text(result.caption).font(.system(size: 15)).foregroundStyle(Theme.secondaryInk)
                    if !result.factors.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(result.factors) { f in
                                Text("\(f.label) — \(f.note)").font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                            }
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer()
                }
            }
            .navigationTitle(ring.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }
        .tint(Theme.accentDark)
    }
}
