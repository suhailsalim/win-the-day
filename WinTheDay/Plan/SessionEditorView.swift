import SwiftUI

struct SessionEditorView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var calendar: CalendarManager
    @Environment(\.dismiss) private var dismiss
    @State private var session: ScheduledSession
    @State private var when: Date
    private let isNew: Bool

    init(editing: ScheduledSession? = nil, defaultDate: Date = Date().addingTimeInterval(3600)) {
        let s = editing ?? ScheduledSession(dateEpoch: defaultDate.timeIntervalSince1970, kind: "strength")
        _session = State(initialValue: s)
        _when = State(initialValue: s.dateEpoch > 0 ? s.date : defaultDate)
        isNew = editing == nil
    }

    private let reminderOptions = [0, 15, 30, 60, 120]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        kindPicker
                        TextField("Title (optional) — e.g. Leg day with Sam", text: $session.title)
                            .font(.system(size: 16)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16).padding(.vertical, 13).glassList()
                        VStack(spacing: 0) {
                            DatePicker("When", selection: $when).padding(.horizontal, 16).padding(.vertical, 8)
                            Hairline()
                            Stepper("Duration: \(session.durationMin) min", value: $session.durationMin, in: 5...240, step: 5)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                            Hairline()
                            TextField("Location (optional)", text: $session.location)
                                .padding(.horizontal, 16).padding(.vertical, 11)
                            Hairline()
                            Toggle("With personal trainer", isOn: $session.withPT).tint(Theme.sage).padding(.horizontal, 16).padding(.vertical, 8)
                            Hairline()
                            Picker("Remind", selection: $session.remindMin) {
                                ForEach(reminderOptions, id: \.self) { m in
                                    Text(m == 0 ? "No reminder" : "\(m) min before").tag(m)
                                }
                            }.padding(.horizontal, 16).padding(.vertical, 6)
                        }
                        .glassList()
                        if store.settings.calendarSync && calendar.calAuthorized {
                            Text("Will also be added to your Apple Calendar.")
                                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                        }
                        if !isNew {
                            Button(role: .destructive) { store.deleteSession(session.id, calendar: calendar); dismiss() } label: {
                                Text("Delete session").frame(maxWidth: .infinity).padding(.vertical, 13).glassList()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(isNew ? "New session" : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundStyle(Theme.tertiaryInk) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
            }
        }
    }

    private func save() {
        session.dateEpoch = when.timeIntervalSince1970
        if session.withPT && session.kind != "pt" { session.kind = "pt" }
        if isNew { store.addSession(session, calendar: calendar) } else { store.updateSession(session) }
        dismiss()
    }

    private var kindPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ScheduledSession.kinds, id: \.id) { k in
                    let on = session.kind == k.id
                    Button { session.kind = k.id; if k.id == "pt" { session.withPT = true } } label: {
                        VStack(spacing: 4) {
                            Image(systemName: k.symbol).font(.system(size: 15))
                            Text(k.label).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(on ? .white : Theme.ink)
                        .frame(width: 80).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 13).fill(on ? AnyShapeStyle(Theme.accentDark) : AnyShapeStyle(Color.white.opacity(0.55))))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
