import SwiftUI

struct PlanView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var calendar: CalendarManager
    @State private var showRoutine = false
    @State private var showSession = false
    @State private var editSession: ScheduledSession?
    @State private var showOccasion = false
    @State private var editOccasion: Occasion?
    @State private var importMsg = ""
    @State private var showWeekPlan = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle(sub: "Win the week", title: "Plan")
            outlookCard
            todayPlanCard
            generatePlanButton
            upcomingSessionsCard
            eventsCard
            routineButton
        }
        .sheet(isPresented: $showRoutine) { RoutineEditorView() }
        .sheet(isPresented: $showSession) { SessionEditorView() }
        .sheet(item: $editSession) { s in SessionEditorView(editing: s) }
        .sheet(isPresented: $showOccasion) { OccasionEditorView() }
        .sheet(item: $editOccasion) { o in OccasionEditorView(editing: o) }
        .sheet(isPresented: $showWeekPlan) { WeekPlanReviewView() }
        .task { await loadOutlook() }
    }

    private var generatePlanButton: some View {
        Button {
            showWeekPlan = true
            Task {
                let lines = calendar.calAuthorized
                    ? calendar.upcomingEvents(days: 7).prefix(20).map { ev in
                        "\(ev.startDate.map { AppStore.shortDate($0) } ?? "") \(timeStr(ev.startDate ?? Date())): \(ev.title ?? "busy")" }.joined(separator: "\n")
                    : ""
                await store.generateAIWeekPlan(eventsText: lines)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "wand.and.stars").foregroundStyle(Theme.onAccent)
                Text("Generate my week with AI").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.onAccent)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.onAccent.opacity(0.7))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(
                colors: [Theme.adaptive(light: 0x6E7BFF, darkGrey: 0x7C87FF),
                         Theme.adaptive(light: 0x5B43E0, darkGrey: 0x6D57E8)],
                startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private func loadOutlook(force: Bool = false) async {
        if calendar.calAuthorized {
            let lines = calendar.upcomingEvents(days: 7).prefix(10).map { ev -> String in
                let when = ev.startDate.map { AppStore.shortDate($0) } ?? ""
                return "\(when): \(ev.title ?? "Event")"
            }.joined(separator: "\n")
            await store.refreshWeekOutlook(eventsText: lines, force: force)
        } else {
            await store.refreshWeekOutlook(force: force)
        }
    }

    // MARK: - Week outlook

    private var outlookCard: some View {
        GlassCard(padding: 16, cornerRadius: 22, tint: Theme.surfaceOverlay) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles").font(.system(size: 13)).foregroundStyle(Theme.accentDark)
                        Text("Your week ahead").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Button { Task { await loadOutlook(force: true) } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiaryInk)
                    }.buttonStyle(.plain)
                }
                weekGrid
                if store.weekOutlookLoading && store.weekOutlook.isEmpty {
                    Text("Looking at your week…").font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                } else if store.weekOutlook.isEmpty {
                    Text("Tap ↻ for an AI look-ahead of your week.").font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                } else {
                    Text(store.weekOutlook).font(.system(size: 14.5)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                }
            }
        }
        .padding(.top, 14)
    }

    private var weekGrid: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var weekCal = Calendar(identifier: .gregorian); weekCal.firstWeekday = 2
        let start = weekCal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: start) ?? today
                let ds = AppStore.dateString(day)
                let entry = store.data.entries[ds]
                let won = entry.map { store.dayWon($0) } ?? false
                let logged = entry?.isMeaningful ?? false
                let isToday = cal.isDate(day, inSameDayAs: today)
                let isPast = day < today
                VStack(spacing: 4) {
                    Text(shortWeekday(day)).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiaryInk)
                    ZStack {
                        Circle().fill(won ? Theme.sage : (logged ? Theme.accent.opacity(0.5) : Theme.tertiaryInk.opacity(0.12)))
                            .frame(width: 26, height: 26)
                        if won { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.onAccent) }
                        else if isPast && !logged { Image(systemName: "minus").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiaryInk) }
                        else { Text("\(cal.component(.day, from: day))").font(.system(size: 11, weight: .semibold)).foregroundStyle(logged ? Theme.onAccent : Theme.secondaryInk) }
                    }
                    .overlay(Circle().strokeBorder(Theme.accentDark, lineWidth: isToday ? 1.5 : 0).frame(width: 30, height: 30))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func shortWeekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEEEE"
        return f.string(from: d)
    }

    // MARK: - Today's plan

    private var todayPlanCard: some View {
        let routine = store.expectedToday()
        let open = store.data.sessions.filter { Calendar.current.isDateInToday($0.date) && !$0.done }
        let doneToday = store.data.sessions.filter { Calendar.current.isDateInToday($0.date) && $0.done }
        let events = calendar.calAuthorized ? calendar.eventsOn(Date()).prefix(5).map { $0 } : []
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeaderRow(text: "Today's plan", color: Theme.accentDark) {
                if !doneToday.isEmpty {
                    Text("\(doneToday.count) done")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sage)
                }
            }
            if routine.isEmpty && open.isEmpty && events.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(doneToday.isEmpty ? "Nothing planned for today." : "All of today's sessions are done — nice.")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.secondaryInk)
                    HStack(spacing: 8) {
                        planChip("Add a session", "plus") { showSession = true }
                        if !store.data.routine.isEmpty {
                            planChip("Fill from routine", "wand.and.stars") { store.generateWeekFromRoutine(calendar: calendar) }
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassList()
            } else {
                VStack(spacing: 0) {
                    ForEach(open) { s in
                        HStack(spacing: 11) {
                            // Tick it off right here — done sessions feed the week grid & streaks.
                            Button { store.completeSession(s.id) } label: {
                                Image(systemName: "circle").font(.system(size: 20)).foregroundStyle(Theme.tertiaryInk)
                            }.buttonStyle(.plain)
                            Button { editSession = s } label: {
                                HStack(spacing: 11) {
                                    IconTile(symbol: ScheduledSession.symbol(s.kind), colors: [Theme.accent, Theme.accentDark], size: 28, corner: 8)
                                    Text(s.title.isEmpty ? ScheduledSession.label(s.kind) : s.title)
                                        .font(.system(size: 15)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text(timeStr(s.date) + (s.withPT ? " · with PT" : ""))
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(s.date < Date() ? Theme.coral : Theme.tertiaryInk)
                                }
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        Hairline()
                    }
                    ForEach(routine) { b in
                        planRow(symbol: ScheduledSession.symbol(b.kind),
                                title: b.title.isEmpty ? ScheduledSession.label(b.kind) : b.title,
                                detail: String(format: "%02d:%02d · routine", b.hour, b.minute))
                        if b.id != routine.last?.id || !events.isEmpty { Hairline() }
                    }
                    ForEach(Array(events.enumerated()), id: \.offset) { idx, ev in
                        planRow(symbol: "calendar", title: ev.title ?? "Event",
                                detail: ev.startDate.map { timeStr($0) } ?? "")
                        if idx < events.count - 1 { Hairline() }
                    }
                }
                .glassList()
            }
        }
    }

    private func planChip(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundStyle(Theme.accentDark)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(Capsule().fill(Theme.accent.opacity(0.14))
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
    }

    private func planRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 11) {
            IconTile(symbol: symbol, colors: [Theme.accent, Theme.accentDark], size: 28, corner: 8)
            Text(title).font(.system(size: 15)).foregroundStyle(Theme.ink)
            Spacer()
            Text(detail).font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: - Upcoming sessions

    @ViewBuilder private var upcomingSessionsCard: some View {
        let sessions = store.upcomingSessions(days: 7)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderRow(text: "Upcoming sessions", color: Theme.sage) {
                if !store.data.routine.isEmpty {
                    Button { store.generateWeekFromRoutine(calendar: calendar) } label: {
                        Label("Fill week", systemImage: "wand.and.stars").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                    }
                }
                Button { showSession = true } label: {
                    Label("Add", systemImage: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
            }
            weekSessionsProgress
            if sessions.isEmpty {
                Text("No sessions scheduled. Add one or fill the week from your routine.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.secondaryInk)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassList()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.prefix(10).enumerated()), id: \.element.id) { idx, s in
                        let overdue = s.date < Date() && !Calendar.current.isDateInToday(s.date)
                        HStack(spacing: 11) {
                            Button { store.completeSession(s.id) } label: {
                                Image(systemName: "circle").font(.system(size: 20)).foregroundStyle(Theme.tertiaryInk)
                            }.buttonStyle(.plain)
                            Button { editSession = s } label: {
                                HStack(spacing: 11) {
                                    IconTile(symbol: ScheduledSession.symbol(s.kind), colors: [Theme.accent, Theme.accentDark], size: 28, corner: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title.isEmpty ? ScheduledSession.label(s.kind) : s.title).font(.system(size: 15)).foregroundStyle(Theme.ink)
                                        Text("\(AppStore.shortDate(s.date)) \(timeStr(s.date))\(s.withPT ? " · PT" : "")\(overdue ? " · missed" : "")")
                                            .font(.system(size: 12.5)).foregroundStyle(overdue ? Theme.coral : Theme.tertiaryInk)
                                    }
                                    Spacer()
                                    if s.calendarEventID != nil { Image(systemName: "calendar").font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk) }
                                }
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        if idx < min(sessions.count, 10) - 1 { Hairline() }
                    }
                }
                .glassList()
            }
        }
    }

    private var sessionsThisWeek: [ScheduledSession] {
        var weekCal = Calendar(identifier: .gregorian); weekCal.firstWeekday = 2
        guard let week = weekCal.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return store.data.sessions.filter { week.contains($0.date) }
    }

    /// This week's sessions at a glance: done / planned, with a thin progress bar.
    @ViewBuilder private var weekSessionsProgress: some View {
        let thisWeek = sessionsThisWeek
        let done = thisWeek.filter(\.done).count
        if !thisWeek.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("This week").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    Text("\(done)/\(thisWeek.count) sessions done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(done == thisWeek.count ? Theme.sage : Theme.secondaryInk)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.tertiaryInk.opacity(0.15)).frame(height: 5)
                        Capsule().fill(done == thisWeek.count ? Theme.sage : Theme.accentDark)
                            .frame(width: geo.size.width * (Double(done) / Double(max(1, thisWeek.count))), height: 5)
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 4).padding(.bottom, 10)
        }
    }

    // MARK: - Events

    @ViewBuilder private var eventsCard: some View {
        let occ = store.upcomingOccasions(days: 120)
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderRow(text: "Events & travel", color: Theme.accentDark) {
                Button {
                    let n = store.importOccasions(from: calendar)
                    importMsg = n > 0 ? "Imported \(n)" : "Nothing new"
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
                Button { showOccasion = true } label: {
                    Label("Add", systemImage: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
            }
            if !importMsg.isEmpty {
                Text(importMsg).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.bottom, 4)
            }
            if occ.isEmpty {
                Text("Add birthdays, anniversaries, weddings or trips — then let the AI help you plan.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.secondaryInk)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassList()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(occ.prefix(8).enumerated()), id: \.element.id) { idx, o in
                        Button { editOccasion = o } label: {
                            HStack(spacing: 11) {
                                IconTile(symbol: Occasion.symbol(o.type), colors: [Theme.accent, Theme.accentDark], size: 28, corner: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.title).font(.system(size: 15)).foregroundStyle(Theme.ink)
                                    if !o.checklist.isEmpty {
                                        Text("\(o.checklist.filter { $0.done }.count)/\(o.checklist.count) prep done").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                                    }
                                }
                                Spacer()
                                if let d = o.nextDate {
                                    Text("\(store.days(until: d))d").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 11)
                        }.buttonStyle(.plain)
                        if idx < min(occ.count, 8) - 1 { Hairline() }
                    }
                }
                .glassList()
            }
        }
    }

    private var routineButton: some View {
        Button { showRoutine = true } label: {
            HStack {
                Image(systemName: "repeat").foregroundStyle(Theme.accentDark)
                Text("Edit weekly routine").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
            }
            .padding(.horizontal, 16).padding(.vertical, 13).glassList()
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private func timeStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }
}
