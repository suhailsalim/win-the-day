import SwiftUI

struct OccasionEditorView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var calendar: CalendarManager
    @Environment(\.dismiss) private var dismiss
    @State private var occasion: Occasion
    @State private var date: Date
    @State private var pasted: String = ""
    @State private var newChecklistItem: String = ""
    @State private var refineText: String = ""
    private let isNew: Bool
    private var hasPlan: Bool { !occasion.checklist.isEmpty || !occasion.itinerary.isEmpty }

    init(editing: Occasion? = nil) {
        let o = editing ?? Occasion(type: "birthday", dateEpoch: Date().timeIntervalSince1970, recurringAnnual: true)
        _occasion = State(initialValue: o)
        _date = State(initialValue: o.dateEpoch > 0 ? Date(timeIntervalSince1970: o.dateEpoch) : Date())
        isNew = editing == nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        typePicker
                        fields
                        contextCard
                        if occasion.type == "travel" {
                            pasteCard
                        }
                        planButton
                        if !occasion.checklist.isEmpty { checklistCard }
                        if !occasion.itinerary.isEmpty { itineraryCard }
                        if hasPlan { refineCard }
                        if !occasion.notes.isEmpty { notesCard }
                        if !isNew { deleteButton }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(isNew ? "New event" : occasion.title.isEmpty ? "Event" : occasion.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundStyle(Theme.tertiaryInk) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
            }
        }
    }

    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Occasion.types, id: \.id) { t in
                    let on = occasion.type == t.id
                    Button { occasion.type = t.id } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.symbol).font(.system(size: 15))
                            Text(t.label).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                        .frame(width: 72).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 13).fill(on ? AnyShapeStyle(Theme.accentDark) : AnyShapeStyle(Theme.surfaceOverlay)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            TextField("Title — e.g. Mum's birthday, Goa wedding", text: $occasion.title)
                .padding(.horizontal, 16).padding(.vertical, 12)
            Hairline()
            TextField("Person (optional)", text: $occasion.person).padding(.horizontal, 16).padding(.vertical, 12)
            Hairline()
            TextField("Location (optional)", text: $occasion.location).padding(.horizontal, 16).padding(.vertical, 12)
            Hairline()
            DatePicker("Date", selection: $date, displayedComponents: .date).padding(.horizontal, 16).padding(.vertical, 8)
            Hairline()
            Toggle("Repeats every year", isOn: $occasion.recurringAnnual).tint(Theme.sage).padding(.horizontal, 16).padding(.vertical, 8)
            if store.settings.calendarSync && calendar.calAuthorized {
                Hairline()
                Toggle("Add to Apple Calendar", isOn: $occasion.calendarSynced).tint(Theme.sage).padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .font(.system(size: 16)).foregroundStyle(Theme.ink)
        .glassList()
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste a booking confirmation (optional)").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                .padding(.horizontal, 16).padding(.top, 10)
            TextField("Flights, hotel, schedule…", text: $pasted, axis: .vertical)
                .lineLimit(3...8).font(.system(size: 14)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .glassList()
    }

    private var planButton: some View {
        Button {
            save(silent: true)
            Task { await store.planOccasion(occasion.id, pasted: pasted.isEmpty ? nil : pasted)
                if let fresh = store.data.occasions.first(where: { $0.id == occasion.id }) { occasion = fresh } }
        } label: {
            HStack {
                if store.occasionPlanLoading { ProgressView().scaleEffect(0.8) }
                else { Image(systemName: "sparkles").foregroundStyle(Theme.onAccent) }
                Text(store.occasionPlanLoading ? "Planning…" : "Plan it with AI").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.onAccent)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accentDark))
        }
        .buttonStyle(.plain)
        .disabled(store.occasionPlanLoading)
    }

    // User's own brief for the AI — always available, feeds "Plan it" and refinements.
    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Context for the AI (optional)").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                .padding(.horizontal, 16).padding(.top, 10)
            TextField("Anything the AI should know — budget, vibe, who's coming, must-dos…",
                      text: $occasion.context, axis: .vertical)
                .lineLimit(2...6).font(.system(size: 14)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .glassList()
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Checklist").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            ForEach($occasion.checklist) { $item in
                HStack(spacing: 10) {
                    Button { item.done.toggle() } label: {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? Theme.sage : Theme.tertiaryInk)
                    }.buttonStyle(.plain)
                    TextField("Item", text: $item.text, axis: .vertical)
                        .font(.system(size: 14)).foregroundStyle(item.done ? Theme.tertiaryInk : Theme.ink)
                        .strikethrough(item.done)
                    Button { occasion.checklist.removeAll { $0.id == item.id } } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.tertiaryInk)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
            HStack(spacing: 8) {
                Image(systemName: "plus.circle").foregroundStyle(Theme.accentDark)
                TextField("Add item", text: $newChecklistItem).font(.system(size: 14)).onSubmit(addChecklistItem)
                if !newChecklistItem.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: addChecklistItem).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .glassList()
    }
    private func addChecklistItem() {
        let t = newChecklistItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        occasion.checklist.append(ChecklistItem(text: t)); newChecklistItem = ""
    }

    private var itineraryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Itinerary").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            ForEach($occasion.itinerary) { $it in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        TextField("Title", text: $it.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                        if let d = it.date { Text(AppStore.shortDate(d)).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk) }
                        Button { occasion.itinerary.removeAll { $0.id == it.id } } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.tertiaryInk)
                        }.buttonStyle(.plain)
                    }
                    TextField("Details", text: $it.detail, axis: .vertical)
                        .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                Hairline()
            }
            Button { occasion.itinerary.append(ItineraryItem(title: "")) } label: {
                Label("Add stop", systemImage: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
            }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .glassList()
    }

    // Give the AI feedback to revise the current plan in place.
    private var refineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Theme.accentDark)
                Text("Refine with AI").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            TextField("What should change? e.g. add a beach day, cheaper options, make it veg",
                      text: $refineText, axis: .vertical)
                .lineLimit(1...4).font(.system(size: 14))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surfaceOverlay))
            Button {
                let fb = refineText
                save(silent: true)
                Task {
                    await store.planOccasion(occasion.id, refine: fb)
                    if let fresh = store.data.occasions.first(where: { $0.id == occasion.id }) { occasion = fresh }
                    refineText = ""
                }
            } label: {
                HStack(spacing: 6) {
                    if store.occasionPlanLoading { ProgressView().scaleEffect(0.8).tint(.white) }
                    Text(store.occasionPlanLoading ? "Revising…" : "Apply changes").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onAccent)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accentDark))
            }
            .buttonStyle(.plain)
            .disabled(store.occasionPlanLoading || refineText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14).glassList()
    }

    private var notesCard: some View {
        Text(occasion.notes).font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).glassList()
    }

    private var deleteButton: some View {
        Button(role: .destructive) { store.deleteOccasion(occasion.id); dismiss() } label: {
            Text("Delete event").frame(maxWidth: .infinity).padding(.vertical, 13).glassList()
        }
    }

    private func save(silent: Bool = false) {
        occasion.dateEpoch = date.timeIntervalSince1970
        if occasion.title.isEmpty { occasion.title = Occasion.label(occasion.type) }
        if store.data.occasions.contains(where: { $0.id == occasion.id }) {
            store.updateOccasion(occasion)
        } else {
            store.addOccasion(occasion)
        }
        if occasion.calendarSynced { store.syncOccasion(occasion.id, calendar: calendar) }
        if !silent { dismiss() }
    }
}
