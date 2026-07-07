import SwiftUI

/// A small sheet to set or clear the time a meal was eaten.
struct MealTimeSheet: View {
    let label: String
    let initial: Date
    let onSet: (Date) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(label: String, initial: Date, onSet: @escaping (Date) -> Void, onClear: @escaping () -> Void) {
        self.label = label; self.initial = initial; self.onSet = onSet; self.onClear = onClear
        _time = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                VStack(spacing: 18) {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .padding(16).glassList()
                    Button(role: .destructive) { onClear() } label: {
                        Text("Clear time").frame(maxWidth: .infinity).padding(.vertical, 12).glassList()
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("\(label) time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundStyle(Theme.tertiaryInk) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Set") { onSet(time) }.font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
