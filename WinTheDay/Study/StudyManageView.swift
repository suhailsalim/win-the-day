import SwiftUI

struct StudyManageView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var studyTimer: StudyTimer
    @Environment(\.dismiss) private var dismiss

    @State private var newSubject = ""
    @State private var sessionSubject = ""
    @State private var newCdName = ""
    @State private var newCdKind = "study"
    @State private var newCdDate = Date()

    private var vocab: WorkVocab { store.workVocab }

    private var modeCard: some View {
        HStack(spacing: 0) {
            ForEach(["study", "work"], id: \.self) { mode in
                let on = store.targets.workMode == mode
                Button { store.updateTargets { $0.workMode = mode } } label: {
                    Text(mode == "study" ? "Study" : "Work")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(on ? .white : Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(on ? Color(hex: 0x5B43E0) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .glassList()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        SectionHeader(text: "Mode")
                        modeCard
                        SectionHeader(text: "Start a \(vocab.session.lowercased())")
                        startCard
                        SectionHeader(text: "Countdowns")
                        countdownsCard
                        SectionHeader(text: "Daily \(vocab.hours.lowercased()) target")
                        targetCard
                        SectionHeader(text: vocab.items)
                        subjectsCard
                    }
                    .padding(16).padding(.bottom, 30)
                }
                .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Work & study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } }
            }
        }
        .tint(Theme.accentDark)
    }

    private var countdownsCard: some View {
        VStack(spacing: 0) {
            ForEach(store.data.countdowns) { cd in
                HStack {
                    Image(systemName: cd.kind == "work" ? "flag.checkered" : "graduationcap.fill")
                        .foregroundStyle(Color(hex: 0x5B43E0))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cd.name).font(.system(size: 15)).foregroundStyle(Theme.ink)
                        Text(cd.date, format: .dateTime.day().month().year()).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    }
                    Spacer()
                    Text("\(max(0, store.days(until: cd.date)))d").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x5B43E0))
                    Button { store.deleteCountdown(cd.id) } label: {
                        Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Color(hex: 0xD86B4A))
                    }.buttonStyle(.plain).padding(.leading, 8)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                Hairline()
            }
            // Add row
            HStack(spacing: 0) {
                ForEach(["study", "work"], id: \.self) { k in
                    Button { newCdKind = k } label: {
                        Text(k == "study" ? "Exam/study" : "Deadline/work")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(newCdKind == k ? .white : Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(newCdKind == k ? Color(hex: 0x5B43E0) : Color.clear)
                    }.buttonStyle(.plain)
                }
            }
            .clipShape(Capsule()).overlay(Capsule().strokeBorder(Color(hex: 0x5B43E0).opacity(0.3), lineWidth: 0.5))
            .padding(.horizontal, 16).padding(.top, 12)
            HStack {
                TextField(newCdKind == "work" ? "e.g. Q3 launch" : "e.g. NEET PG", text: $newCdName).font(.system(size: 15))
            }.padding(.horizontal, 16).padding(.vertical, 10)
            DatePicker("Date", selection: $newCdDate, in: Date()..., displayedComponents: .date)
                .font(.system(size: 15)).tint(Theme.accentDark).padding(.horizontal, 16)
            Button {
                let t = newCdName.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { store.addCountdown(name: t, date: newCdDate, kind: newCdKind); newCdName = "" }
            } label: {
                Label("Add countdown", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x5B43E0))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.plain)
        }
        .glassList()
    }

    private var startCard: some View {
        VStack(spacing: 10) {
            if studyTimer.running {
                Text("A session is already running. Stop it from the Today screen first.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(store.targets.workMode == "work" ? "What are you working on? (optional)" : "What are you studying? (optional)", text: $sessionSubject)
                    .font(.system(size: 15)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
                if !store.data.subjects.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(store.data.subjects) { s in
                            Button { sessionSubject = s.name } label: {
                                Text(s.name).font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color(hex: 0x5B43E0))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Capsule().fill(Color(hex: 0x6FA8FF).opacity(0.18)))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button {
                    studyTimer.start(subject: sessionSubject)
                    dismiss()
                } label: {
                    Label("Start timer", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Color(hex: 0x5B43E0)))
                }.buttonStyle(.plain)
            }
        }
        .padding(16).glassList()
    }


    private var targetCard: some View {
        HStack {
            Text("Hours per day").font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer()
            Text(String(format: "%.0f h", store.targets.studyHours)).foregroundStyle(Theme.tertiaryInk)
            HStack(spacing: 0) {
                Button { store.updateTargets { $0.studyHours = max(1, $0.studyHours - 1) } } label: { Image(systemName: "minus").frame(width: 38, height: 32) }
                Button { store.updateTargets { $0.studyHours += 1 } } label: { Image(systemName: "plus").frame(width: 38, height: 32) }
            }
            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accentDark)
            .background(Capsule().fill(Color.white.opacity(0.6)))
        }
        .padding(.horizontal, 16).padding(.vertical, 10).glassList()
    }

    private var subjectsCard: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Add a \(vocab.itemSingular)", text: $newSubject).font(.system(size: 15))
                Button {
                    let t = newSubject.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { store.addSubject(t); newSubject = "" }
                } label: { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentDark) }
            }.padding(.horizontal, 16).padding(.vertical, 12)
            ForEach(store.data.subjects) { s in
                Hairline()
                HStack {
                    Button { store.toggleSubject(s.id) } label: {
                        Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(s.done ? Theme.sage : Color(white: 0.47).opacity(0.3))
                    }.buttonStyle(.plain)
                    Text(s.name).font(.system(size: 15)).foregroundStyle(Theme.ink).strikethrough(s.done)
                    Spacer()
                    Button { store.deleteSubject(s.id) } label: {
                        Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Color(hex: 0xD86B4A))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 16).padding(.vertical, 11)
            }
        }
        .glassList()
    }
}
