import SwiftUI

/// Today's Qur'an module: log the day's pages, see where you are (juz' · surah · page) and how the
/// khatmah plan is tracking. Lives in its own file rather than in `TodayView` because the plan card
/// carries its own setup sheet.
///
/// No Qur'anic text or translation is bundled — position labels only (see `QuranProgress`).
struct QuranModuleView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var prayer: PrayerManager
    @State private var showSetup = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionHeader(text: "Qur'an", color: store.moduleColor("quran"))
                Spacer()
                Button { showSetup = true } label: {
                    Label(store.data.khatmah == nil ? "Plan" : "Edit plan", systemImage: "book.closed")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
                .padding(.trailing, 8).padding(.top, 22)
            }
            card
        }
        .sheet(isPresented: $showSetup) { KhatmahSetupView() }
    }

    private var card: some View {
        let status = store.quranStatus
        let pages = store.draft.quranPages
        return GlassCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 13) {
                    IconTile(symbol: "book.closed.fill",
                             colors: [Theme.adaptive(light: 0x4FA383, darkGrey: 0x5CB496),
                                      Theme.adaptive(light: 0x2F7D5E, darkGrey: 0x3C946F)], size: 36, corner: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pages == 0 ? "No pages logged yet" : "\(pages) page\(pages == 1 ? "" : "s") today")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(subtitle(status))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                stepperRow
                if let status { planBlock(status) } else { noPlanRow }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Logging

    private var stepperRow: some View {
        HStack(spacing: 8) {
            pageButton("+1") { store.addQuranPages(1) }
            pageButton("+5") { store.addQuranPages(5) }
            pageButton("+1 juz\u{2019}") { store.addQuranPages(QuranProgress.pagesInOneJuz) }
            if store.draft.quranPages > 0 {
                pageButton("\u{2212}1") { store.addQuranPages(-1) }
            }
            Spacer(minLength: 0)
        }
    }

    private func pageButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.adaptive(light: 0x2F7D5E, darkGrey: 0x5FBE95))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Theme.adaptive(light: 0x4FA383, darkGrey: 0x5FBE95).opacity(0.18))
                    .overlay(Capsule().strokeBorder(Theme.adaptive(light: 0x2F7D5E, darkGrey: 0x5FBE95).opacity(0.35), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plan

    @ViewBuilder private func planBlock(_ s: QuranProgress.Status) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(QuranProgress.positionLabel(page: s.currentPage))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(s.currentPage)/\(QuranProgress.totalPages)")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.tertiaryInk.opacity(0.15)).frame(height: 8)
                    Capsule().fill(s.isComplete ? Theme.sage : Theme.adaptive(light: 0x2F7D5E, darkGrey: 0x5FBE95))
                        .frame(width: geo.size.width * s.fraction, height: 8)
                }
            }
            .frame(height: 8)
            Text(planLine(s))
                .font(.system(size: 12)).foregroundStyle(s.isComplete ? Theme.sage : Theme.secondaryInk)
            if s.isComplete {
                Button { store.startKhatmah(targetDays: store.data.khatmah?.effectiveTargetDays ?? 30, startPage: 0) } label: {
                    Text("Start another khatmah")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
                .buttonStyle(.plain).padding(.top, 2)
            }
        }
        .padding(.top, 2)
    }

    private var noPlanRow: some View {
        Button { showSetup = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle.fill").font(.system(size: 13)).foregroundStyle(Theme.accentDark)
                Text("Plan a khatmah \u{2014} finish the Qur\u{2019}an by a date")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accentDark)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain).padding(.top, 2)
    }

    // MARK: - Copy

    private func subtitle(_ s: QuranProgress.Status?) -> String {
        let juz = QuranProgress.juzEquivalent(pages: store.draft.quranPages)
        let juzText = juz >= 0.1 ? String(format: " \u{00b7} %.1f juz\u{2019}", juz) : ""
        guard let s else { return "Log what you read today\(juzText)" }
        if s.isComplete { return "Khatmah complete \u{2014} alhamdulillah" }
        return "Today\u{2019}s ask: \(s.dailyTarget) page\(s.dailyTarget == 1 ? "" : "s")\(juzText)"
    }

    /// Never guilt about the past: a missed day just raises today's ask, and the line says where
    /// you stand rather than what you owe.
    private func planLine(_ s: QuranProgress.Status) -> String {
        if s.isComplete {
            let n = store.data.khatmah?.timesCompleted ?? 0
            return n > 1 ? "Finished \(n) khatmahs with this plan" : "All 604 pages \u{2014} finished"
        }
        let day = "Day \(s.dayNumber) of \(max(s.dayNumber, s.dayNumber + s.daysRemaining - 1))"
        let pace: String
        if s.paceDelta > 0 { pace = "\(s.paceDelta) pages ahead" }
        else if s.paceDelta == 0 { pace = "on pace" }
        else { pace = "\(-s.paceDelta) pages behind" }
        let left = s.remainingToday > 0 ? "\(s.remainingToday) to go today" : "today\u{2019}s target met"
        return "\(day) \u{00b7} \(left) \u{00b7} \(pace)"
    }
}

/// Set up (or end) the khatmah plan: how long, and where to start from.
struct KhatmahSetupView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var prayer: PrayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var targetDays = 30
    @State private var startPage = 0

    private static let presets = [30, 60, 90]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Finish in").font(.system(size: 16)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(targetDays) days").font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryInk)
                            }.padding(.horizontal, 16).padding(.vertical, 13)
                            Hairline()
                            FlowLayout(spacing: 8) {
                                ForEach(Self.presets, id: \.self) { d in
                                    chip("\(d) days", on: targetDays == d) { targetDays = d }
                                }
                                if let ramadan = ramadanDaysLeft {
                                    chip("By end of Ramadan (\(ramadan)d)", on: targetDays == ramadan) { targetDays = ramadan }
                                }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 13)
                            Hairline()
                            HStack {
                                Text("Start from page").frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(Theme.ink)
                                TextField("0", value: $startPage, format: .number)
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                            }.font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 13)
                        }
                        .glassList()

                        Text("\(perDay) pages a day \u{00b7} \(QuranProgress.positionLabel(page: max(1, startPage)))")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.top, 10)

                        Text("Missed days are redistributed over the days that are left \u{2014} the plan re-does its own maths every morning.")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.top, 6)

                        if store.data.khatmah != nil {
                            Button(role: .destructive) { store.endKhatmah(); dismiss() } label: {
                                Text("End this plan").frame(maxWidth: .infinity)
                            }.padding(.top, 22)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(store.data.khatmah == nil ? "New khatmah" : "Khatmah plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.startKhatmah(targetDays: targetDays, startPage: startPage)
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
            .onAppear {
                if let plan = store.data.khatmah {
                    targetDays = plan.effectiveTargetDays
                    // Default to continuing from where the reader actually is, not the old start.
                    startPage = store.quranStatus?.currentPage ?? plan.effectiveStartPage
                }
            }
        }
        .tint(Theme.accentDark)
    }

    private var perDay: Int {
        QuranProgress.flatDailyPages(KhatmahPlan(targetDays: targetDays, startPage: startPage))
    }

    /// Days left in the current Hijri month, offered as a preset while Ramadan mode is on.
    private var ramadanDaysLeft: Int? {
        guard prayer.ramadanMode else { return nil }
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.timeZone = .current
        let now = Date()
        guard let range = cal.range(of: .day, in: .month, for: now) else { return nil }
        let day = cal.component(.day, from: now)
        let left = range.count - day + 1
        return left > 0 ? left : nil
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? .white : Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.accentDark) : AnyShapeStyle(Theme.surfaceOverlay))
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(on ? 0 : 0.35), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
    }
}
