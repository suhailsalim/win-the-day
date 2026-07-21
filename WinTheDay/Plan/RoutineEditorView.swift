import SwiftUI

struct RoutineEditorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: RoutineBlock?
    @State private var showEditor = false

    private let weekdayNames = ["Every day", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        Text("Set the sessions and habits you want each week. They\u{2019}ll appear on your Plan and can auto-fill your schedule.")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        if store.data.routine.isEmpty {
                            Text("No routine blocks yet — add your first.").font(.system(size: 14))
                                .foregroundStyle(Theme.tertiaryInk).padding(.vertical, 30)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(store.data.routine.sorted { ($0.weekday, $0.hour) < ($1.weekday, $1.hour) }) { b in
                                    Button { editing = b; showEditor = true } label: { row(b) }.buttonStyle(.plain)
                                    Hairline()
                                }
                            }
                            .glassList().padding(.horizontal, 16)
                        }
                        Button { editing = nil; showEditor = true } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentDark)
                                Text("Add routine block").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accentDark)
                                Spacer()
                            }
                            .padding(16).glassList().padding(16)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Weekly routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.accentDark) } }
            .sheet(isPresented: $showEditor) { RoutineBlockEditor(block: editing) }
        }
    }

    private func row(_ b: RoutineBlock) -> some View {
        HStack(spacing: 11) {
            IconTile(symbol: ScheduledSession.symbol(b.kind), colors: [Theme.accent, Theme.accentDark], size: 30, corner: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.title.isEmpty ? ScheduledSession.label(b.kind) : b.title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(Theme.ink)
                Text("\(weekdayNames[b.weekday]) · \(String(format: "%02d:%02d", b.hour, b.minute)) · \(b.durationMin)m\(b.withPT ? " · PT" : "")")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

struct RoutineBlockEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var block: RoutineBlock
    private let isNew: Bool

    init(block: RoutineBlock?) {
        _block = State(initialValue: block ?? RoutineBlock(title: "", kind: "strength"))
        isNew = block == nil
    }

    private let weekdays = ["Every day", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        kindPicker
                        TextField("Title (optional)", text: $block.title)
                            .font(.system(size: 16)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16).padding(.vertical, 13).glassList()
                        VStack(spacing: 0) {
                            Picker("Day", selection: $block.weekday) {
                                ForEach(0..<8, id: \.self) { Text(weekdays[$0]).tag($0) }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 6)
                            Hairline()
                            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                            Hairline()
                            Stepper("Duration: \(block.durationMin) min", value: $block.durationMin, in: 5...240, step: 5)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                            Hairline()
                            Toggle("With personal trainer", isOn: $block.withPT).tint(Theme.sage).padding(.horizontal, 16).padding(.vertical, 8)
                            Hairline()
                            Toggle("Remind me", isOn: $block.remind).tint(Theme.sage).padding(.horizontal, 16).padding(.vertical, 8)
                        }
                        .glassList()
                        if !isNew {
                            Button(role: .destructive) { store.deleteRoutineBlock(block.id); dismiss() } label: {
                                Text("Delete block").frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .glassList()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(isNew ? "New block" : "Edit block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundStyle(Theme.tertiaryInk) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if isNew { store.addRoutineBlock(block) } else { store.updateRoutineBlock(block) }
                        dismiss()
                    }.font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents(); c.hour = block.hour; c.minute = block.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                block.hour = c.hour ?? 7; block.minute = c.minute ?? 0
            })
    }

    private var kindPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ScheduledSession.kinds.filter { $0.id != "pt" }, id: \.id) { k in
                    let on = block.kind == k.id
                    Button { block.kind = k.id } label: {
                        VStack(spacing: 4) {
                            Image(systemName: k.symbol).font(.system(size: 15))
                            Text(k.label).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(on ? .white : Theme.ink)
                        .frame(width: 76).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 13).fill(on ? AnyShapeStyle(Theme.accentDark) : AnyShapeStyle(Theme.surfaceOverlay)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
