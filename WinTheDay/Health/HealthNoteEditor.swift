import SwiftUI

struct HealthNoteEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var note: HealthNote
    private let isNew: Bool

    init(note: HealthNote?) {
        _note = State(initialValue: note ?? HealthNote(category: "condition"))
        isNew = note == nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        categoryPicker
                        VStack(spacing: 0) {
                            TextField("Title — e.g. Right shoulder, Whey protein", text: $note.title)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                            Hairline()
                            TextField("Details (optional) — dose, limits, history…", text: $note.text, axis: .vertical)
                                .lineLimit(3...8)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .font(.system(size: 16)).foregroundStyle(Theme.ink)
                        .glassList()
                        Text("Your AI coach reads this to tailor advice (it\u{2019}s sent to your selected AI provider with your other data).")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                        if !isNew {
                            Button(role: .destructive) { store.deleteHealthNote(note.id); dismiss() } label: {
                                Text("Delete note").frame(maxWidth: .infinity).padding(.vertical, 13).glassList()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(isNew ? "New note" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundStyle(Theme.tertiaryInk) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accentDark)
                        .disabled(note.title.trimmingCharacters(in: .whitespaces).isEmpty && note.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HealthNote.categories, id: \.id) { c in
                    let on = note.category == c.id
                    Button { note.category = c.id } label: {
                        VStack(spacing: 4) {
                            Image(systemName: c.symbol).font(.system(size: 15))
                            Text(c.label).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(on ? .white : Theme.ink)
                        .frame(width: 84).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 13).fill(on ? AnyShapeStyle(Theme.accentDark) : AnyShapeStyle(Theme.surfaceOverlay)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func save() {
        if store.data.healthNotes.contains(where: { $0.id == note.id }) {
            store.updateHealthNote(note)
        } else {
            store.addHealthNote(note)
        }
        dismiss()
    }
}
