import SwiftUI

/// The daily self-report that sharpens Readiness. Bounded by design — `ScoreEngine` floors the
/// multiplier at 0.85, so this nudges the score, it never overrides the sensors.
struct CheckInSheet: View {
    let initial: DayCheckIn
    let onSave: (DayCheckIn) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var local: DayCheckIn

    init(initial: DayCheckIn, onSave: @escaping (DayCheckIn) -> Void) {
        self.initial = initial; self.onSave = onSave
        _local = State(initialValue: initial)
    }

    private static let intensity = ["None", "Mild", "Moderate", "High"]
    private static let moodWords = ["Low", "Meh", "Good", "Great"]
    private static let drinkWords = ["None", "1", "2", "3+"]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How you actually feel today — it adjusts Readiness by a few points at most, never more.")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                            .padding(.horizontal, 4)

                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 16) {
                                scaleRow("Soreness", Self.intensity, $local.soreness)
                                scaleRow("Stress", Self.intensity, $local.stress)
                                scaleRow("Mood", Self.moodWords, $local.mood)
                            }
                        }

                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 16) {
                                scaleRow("Alcohol", Self.drinkWords, $local.alcohol)
                                Hairline()
                                Toggle(isOn: $local.lateCaffeine) {
                                    Text("Caffeine after ~2pm").font(.system(size: 15)).foregroundStyle(Theme.ink)
                                }
                                Toggle(isOn: $local.illness) {
                                    Text("Feeling ill").font(.system(size: 15)).foregroundStyle(Theme.ink)
                                }
                            }
                            .tint(Theme.accentDark)
                        }

                        if local != DayCheckIn() {
                            Button(role: .destructive) { local = DayCheckIn() } label: {
                                Text("Clear check-in").frame(maxWidth: .infinity).padding(.vertical, 12).glassList()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Daily check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.tertiaryInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave(local); dismiss() }
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func scaleRow(_ label: String, _ words: [String], _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text(words[min(max(0, value.wrappedValue), words.count - 1)])
                    .font(.system(size: 13)).foregroundStyle(Theme.tertiaryInk)
            }
            HStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                    let on = value.wrappedValue == idx
                    Button { value.wrappedValue = idx } label: {
                        Text(word).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? .white : Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(on ? Theme.accentDark : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surfaceOverlay).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
        }
    }
}
