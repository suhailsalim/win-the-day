import SwiftUI
import HealthKit

struct HealthView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var health: HealthManager

    private var on: Bool { store.settings.healthkit }

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle(sub: "Live from Apple Health", title: "Health")

            banner
            SectionHeader(text: "Today & latest")
            metricsGrid
            SectionHeader(text: "Import reports")
            importSection
            if !store.data.bodyComps.isEmpty || !store.data.labs.isEmpty {
                SectionHeader(text: "Recent imports")
                recentImports
            }
            HStack {
                SectionHeader(text: "Health profile & notes")
                Spacer()
                Button { editNote = nil; showNote = true } label: {
                    Label("Add", systemImage: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }.padding(.trailing, 8).padding(.top, 22)
            }
            notesSection
            footer
        }
        .task { if on { await health.requestAuthorization() } }
        .sheet(item: $importMode) { mode in ImportReportView(mode: mode) }
        .sheet(isPresented: $showNote) { HealthNoteEditor(note: editNote) }
        .sheet(item: $editNote) { n in HealthNoteEditor(note: n) }
    }

    @State private var importMode: ImportReportView.Mode?
    @State private var showNote = false
    @State private var editNote: HealthNote?

    private var notesSection: some View {
        VStack(spacing: 0) {
            if store.data.healthNotes.isEmpty {
                Text("Add conditions, injuries, medications, supplements or goals. Your AI coach uses these to tailor advice.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).glassList()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.data.healthNotes.enumerated()), id: \.element.id) { idx, n in
                        Button { editNote = n } label: {
                            HStack(spacing: 12) {
                                IconTile(symbol: HealthNote.symbol(n.category),
                                         colors: [Color(hex: 0x9D8CFF), Color(hex: 0x5B43E0)], size: 30, corner: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.title.isEmpty ? HealthNote.label(n.category) : n.title)
                                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                                    if !n.text.isEmpty {
                                        Text(n.text).font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk).lineLimit(2)
                                    } else {
                                        Text(HealthNote.label(n.category)).font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 11)
                        }.buttonStyle(.plain)
                        if idx < store.data.healthNotes.count - 1 { Hairline() }
                    }
                }
                .glassList()
                Text("Used to give your AI coach better context. Sent to your selected AI provider with your other data.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk).padding(.horizontal, 4).padding(.top, 6)
            }
        }
    }

    private var importSection: some View {
        VStack(spacing: 0) {
            importRow("InBody / body composition", "figure.arms.open", colors: [Color(hex: 0x7AC0FF), Color(hex: 0x1E8AE0)]) {
                importMode = .bodyComp
            }
            Hairline()
            importRow("Health checkup / labs", "doc.text.magnifyingglass", colors: [Color(hex: 0x9D8CFF), Color(hex: 0x5B43E0)]) {
                importMode = .labs
            }
        }
        .glassList()
    }

    private func importRow(_ title: String, _ symbol: String, colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, colors: colors)
                Text(title).font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentDark)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private var recentImports: some View {
        VStack(spacing: 0) {
            ForEach(store.data.bodyComps.sorted { $0.date > $1.date }.prefix(3)) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("InBody · \(c.date)").font(.system(size: 14)).foregroundStyle(Theme.ink)
                        Text(bodyCompLine(c)).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                Hairline()
            }
            ForEach(store.data.labs.prefix(3)) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(r.title) · \(r.date)").font(.system(size: 14)).foregroundStyle(Theme.ink)
                        Text("\(r.items.count) results · \(r.items.filter { $0.written }.count) to Health")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                if r.id != store.data.labs.prefix(3).last?.id { Hairline() }
            }
        }
        .glassList()
    }

    private func bodyCompLine(_ c: BodyComp) -> String {
        var parts: [String] = []
        if let w = c.weight { parts.append("\(Int(w))kg") }
        if let bf = c.bodyFat { parts.append("\(Int(bf))% fat") }
        if let v = c.visceralFat { parts.append("VF \(Int(v))") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Connect banner

    private var banner: some View {
        GlassCard(padding: 16, cornerRadius: 24, tint: .white.opacity(0.46)) {
            VStack(spacing: 13) {
                HStack(spacing: 12) {
                    IconTile(symbol: "heart.fill", colors: [Color(hex: 0xFF5E7A), Color(hex: 0xFB1E4B)],
                             size: 44, corner: 13)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(statusTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(statusSub).font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    actionButton(on ? "Refresh" : "Connect Apple Health", filled: true) {
                        store.updateSettings { $0.healthkit = true }
                        Task { await health.requestAuthorization() }
                    }
                    actionButton("Open Health", filled: false) {
                        if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    private var statusTitle: String {
        if health.usingPlaceholders { return "Showing sample data" }
        return on ? "Connected to Health" : "Health is off"
    }
    private var statusSub: String {
        if health.usingPlaceholders {
            return "No Health data on this device yet — tap Open Health to grant access, or run on your iPhone."
        }
        return on ? "Reading the metrics below, including data other apps (e.g. Bevel) write to Health."
                  : "Turn on to read steps, weight, recovery and sleep."
    }

    private func actionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(filled ? .white : Theme.accentDark)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(filled
                              ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xECB477), Color(hex: 0xE29A4E)],
                                                             startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Theme.accent.opacity(0.16)))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metric cards

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metric("Steps", value: intStr(health.stepsToday), unit: "today",
                   symbol: "figure.walk", colors: [Color(hex: 0xFF9E6B), Color(hex: 0xF4631E)])
            metric("Active energy", value: intStr(health.activeEnergyToday), unit: "kcal today",
                   symbol: "flame.fill", colors: [Color(hex: 0xFF6FA0), Color(hex: 0xFB1E5B)])
            metric("Body mass", value: health.latestWeight > 0 ? String(format: "%.1f", health.latestWeight) : "—",
                   unit: "kg latest", symbol: "figure.stand", colors: [Color(hex: 0x7AC0FF), Color(hex: 0x1E8AE0)])
            metric("Resting HR", value: health.restingHR > 0 ? intStr(health.restingHR) : "—", unit: "bpm",
                   symbol: "heart.fill", colors: [Color(hex: 0xFF5E7A), Color(hex: 0xFB1E4B)])
            metric("HRV", value: health.hrv > 0 ? intStr(health.hrv) : "—", unit: "ms SDNN",
                   symbol: "waveform.path.ecg", colors: [Color(hex: 0x9D8CFF), Color(hex: 0x5B43E0)])
            metric("Sleep", value: health.sleepHours > 0 ? String(format: "%.1f", health.sleepHours) : "—",
                   unit: "h last night", symbol: "moon.fill", colors: [Color(hex: 0x6E7BFF), Color(hex: 0x3B43C0)])
            metric("Workouts", value: "\(health.workoutsThisWeek)", unit: "this week",
                   symbol: "dumbbell.fill", colors: [Color(hex: 0x5FE08A), Color(hex: 0x16B45A)])
            metric("Logged today", value: loggedCals, unit: "kcal → Health",
                   symbol: "square.and.arrow.up", colors: [Color(hex: 0xFFC36B), Color(hex: 0xF0961E)])
        }
        .padding(.top, 2)
    }

    private var loggedCals: String {
        let c = Double(store.draft.calories) ?? 0
        return c > 0 ? intStr(c) : "—"
    }

    private func metric(_ label: String, value: String, unit: String, symbol: String, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                IconTile(symbol: symbol, colors: colors, size: 28, corner: 8)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(Theme.serif(26)).foregroundStyle(Theme.ink)
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(unit).font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
        )
    }

    private func intStr(_ d: Double) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: Int(d.rounded())), number: .decimal)
    }

    private var footer: some View {
        Text("Data stays on your device. Win the Day reads it locally with your permission and writes your logged calories & protein back. Manage exactly what\u{2019}s shared in Apple Health → Sharing → Apps.")
            .font(.system(size: 12)).foregroundStyle(Color(white: 0.27).opacity(0.45))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.top, 18)
    }
}
