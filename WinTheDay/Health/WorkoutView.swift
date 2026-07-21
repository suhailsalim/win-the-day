import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var health: HealthManager
    @Environment(\.dismiss) private var dismiss

    @State private var workout: Workout
    private let isNew: Bool

    init(editing: Workout? = nil) {
        _workout = State(initialValue: editing ?? Workout())
        isNew = editing == nil
    }

    private static let templates: [(name: String, kind: String, exercises: [String])] = [
        ("Push", "strength", ["Bench press", "Shoulder press", "Triceps pushdown"]),
        ("Pull", "strength", ["Lat pulldown", "Seated row", "Biceps curl"]),
        ("Legs", "strength", ["Squat", "Leg press", "Calf raise"]),
        ("Full body", "strength", ["Squat", "Bench press", "Row"]),
        ("Run / cardio", "cardio", [])
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        kindPicker
                        if isNew { templatesRow }
                        titleField
                        ForEach($workout.exercises) { $ex in
                            exerciseCard($ex)
                        }
                        addExerciseButton
                        footerFields
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isNew ? "Log workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.tertiaryInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.accentDark : Theme.tertiaryInk.opacity(0.5))
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        workout.kind == "cardio" || workout.exercises.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            || !workout.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(Workout.kinds, id: \.id) { k in
                let on = workout.kind == k.id
                Button { workout.kind = k.id } label: {
                    VStack(spacing: 4) {
                        Image(systemName: k.symbol).font(.system(size: 15))
                        Text(k.label).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(on ? .white : Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 13).fill(on ? AnyShapeStyle(Theme.accentDark) : AnyShapeStyle(Theme.surfaceOverlay)))
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.surfaceStroke.opacity(on ? 0 : 1), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var templatesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.templates, id: \.name) { t in
                    Button { applyTemplate(t) } label: {
                        Text(t.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.surfaceOverlay))
                            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var titleField: some View {
        TextField("Label (optional) — e.g. Push day", text: $workout.title)
            .font(.system(size: 16)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 13)
            .glassList()
    }

    private func exerciseCard(_ ex: Binding<Exercise>) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Exercise", text: ex.name)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Button { workout.exercises.removeAll { $0.id == ex.wrappedValue.id } } label: {
                        Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Theme.tertiaryInk)
                    }.buttonStyle(.plain)
                }
                ForEach(Array(ex.sets.enumerated()), id: \.element.id) { idx, $set in
                    HStack(spacing: 10) {
                        Text("Set \(idx + 1)").font(.system(size: 13)).foregroundStyle(Theme.secondaryInk).frame(width: 44, alignment: .leading)
                        stepper(value: Binding(get: { Double($set.wrappedValue.reps) },
                                               set: { $set.wrappedValue.reps = Int($0) }),
                                label: "reps", step: 1, min: 1)
                        stepper(value: $set.weightKg, label: "kg", step: 2.5, min: 0)
                        if ex.wrappedValue.sets.count > 1 {
                            Button { ex.wrappedValue.sets.removeAll { $0.id == set.id } } label: {
                                Image(systemName: "minus.circle").font(.system(size: 16)).foregroundStyle(Theme.tertiaryInk)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button { ex.wrappedValue.sets.append(StrengthSet(reps: ex.wrappedValue.sets.last?.reps ?? 10,
                                                                 weightKg: ex.wrappedValue.sets.last?.weightKg ?? 0)) } label: {
                    Label("Add set", systemImage: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }.buttonStyle(.plain)
            }
        }
    }

    private func stepper(value: Binding<Double>, label: String, step: Double, min: Double) -> some View {
        HStack(spacing: 0) {
            Button { value.wrappedValue = Swift.max(min, value.wrappedValue - step) } label: {
                Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentDark).frame(width: 30, height: 30)
            }.buttonStyle(.plain)
            Text("\(fmt(value.wrappedValue)) \(label)").font(.system(size: 13.5)).foregroundStyle(Theme.ink)
                .frame(minWidth: 58)
            Button { value.wrappedValue += step } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentDark).frame(width: 30, height: 30)
            }.buttonStyle(.plain)
        }
        .background(Capsule().fill(Theme.surfaceOverlay))
        .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
    }

    private var addExerciseButton: some View {
        Button { workout.exercises.append(Exercise()) } label: {
            HStack {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentDark)
                Text("Add exercise").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentDark)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 13).glassList()
        }.buttonStyle(.plain)
    }

    private var footerFields: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Duration").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                stepper(value: Binding(get: { Double(workout.durationMin) },
                                       set: { workout.durationMin = Int($0) }),
                        label: "min", step: 5, min: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            Hairline()
            TextField("Notes — e.g. neck felt fine, easy pace", text: $workout.note, axis: .vertical)
                .font(.system(size: 15)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .glassList()
    }

    private func applyTemplate(_ t: (name: String, kind: String, exercises: [String])) {
        workout.kind = t.kind
        if workout.title.isEmpty { workout.title = t.name }
        if !t.exercises.isEmpty {
            workout.exercises = t.exercises.map { Exercise(name: $0, sets: [StrengthSet(), StrengthSet(), StrengthSet()]) }
        }
    }

    private func save() {
        workout.title = workout.title.trimmingCharacters(in: .whitespaces)
        workout.exercises.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        store.saveWorkout(workout, health: health)
        dismiss()
    }

    private func fmt(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d) }
}
