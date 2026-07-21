import Foundation
import SwiftUI
import UIKit
import WidgetKit
import UserNotifications

enum Tab: String { case today, plan, trends, health, settings }

enum AIStatus: Equatable { case idle, loading, done, error }

@MainActor
final class AppStore: ObservableObject {
    private let dataKey = "suhail_health_v2"
    private let settingsKey = "suhail_ios_settings_v1"

    @Published var data = AppData()
    @Published var settings = AppSettings()
    @Published var targets = Targets()
    @Published var modules = ModulePrefs()
    @Published var personal = Personalization()
    @Published var onboardingDone = UserDefaults.standard.bool(forKey: "onboarding_done_v1")
    private let targetsKey = "targets_v1"
    private let modulesKey = "modules_v1"
    private let personalKey = "personalize_v1"

    var workVocab: WorkVocab { WorkVocab.forMode(targets.workMode) }

    func pillarTitle(_ p: Pillar) -> String {
        let custom = personal.pillarTitles[p.rawValue]?.trimmingCharacters(in: .whitespaces)
        return (custom?.isEmpty == false) ? custom! : p.title
    }

    func moduleColor(_ key: String) -> Color {
        if let hex = personal.moduleColors[key] { return Color(hex: hex) }
        switch key {
        case "rings": return Theme.accentDark
        case "health": return Color(hex: 0xFB1E4B)
        case "hydration": return Color(hex: 0x2E8AE0)
        case "workStudy": return Color(hex: 0x5B43E0)
        case "fasting": return Color(hex: 0x3B4A7C)
        case "sleep": return Color(hex: 0x6E7BFF)
        case "weather": return Color(hex: 0x2E8AE0)
        case "score": return Theme.sage
        default: return Theme.accentDark
        }
    }

    func updatePersonal(_ change: (inout Personalization) -> Void) {
        change(&personal)
        if let raw = try? JSONEncoder().encode(personal) {
            UserDefaults.standard.set(raw, forKey: personalKey)
        }
        objectWillChange.send()
    }
    @Published var draft: Entry
    @Published var tab: Tab = .today
    @Published var date: String
    @Published var aiStatus: AIStatus = .idle
    @Published var aiErrorMessage: String = ""
    @Published var importMessage: String = ""

    // Time-aware suggestion shown on Today
    @Published var suggestion: String = ""
    @Published var suggestionLoading = false
    private var suggestionSlot: String = ""   // date+timeslot we last fetched for

    // Weather module's AI tips rotator — batched (one call per date+timeslot), never empty.
    @Published var dayTips: [String] = []
    @Published var dayTipsLoading = false
    private var dayTipsSlot: String = ""

    // Coach chat — multiple threads, each its own conversation
    @Published var threads: [CoachThread] = []
    @Published var activeThreadID: String = ""
    @Published var chatLoading = false
    private let threadsKey = "coach_threads_v1"
    private let activeThreadKey = "coach_active_thread_v1"
    private let legacyChatKey = "coach_chat_v1"   // pre-multi-thread single transcript, migrated once

    private let estimator = AIEstimator()

    init() {
        let today = Self.dateString(Date())
        self.date = today
        self.draft = Entry(date: today)
        load()
        if data.habits.isEmpty { data.habits = HabitDef.defaults; persistData() }
        if data.rings.isEmpty { data.rings = RingDef.defaults; persistData() }
        migrateExamIfNeeded()
        self.draft = loadDraft(for: today)
        loadThreads()
    }

    // MARK: - Module reordering

    func moveModule(from offsets: IndexSet, to dest: Int) {
        updateModules { $0.order.move(fromOffsets: offsets, toOffset: dest) }
    }

    // MARK: - Study

    func addStudyHours(_ hours: Double) {
        mutate { $0.studyHours = max(0, $0.studyHours + hours) }
    }

    func addSubject(_ name: String) {
        data.subjects.append(Subject(name: name)); persistData()
    }
    func toggleSubject(_ id: String) {
        if let i = data.subjects.firstIndex(where: { $0.id == id }) { data.subjects[i].done.toggle() }
        persistData()
    }
    func deleteSubject(_ id: String) {
        data.subjects.removeAll { $0.id == id }; persistData()
    }
    func setExam(name: String, date: Date?) {
        updateTargets { $0.examName = name; $0.examDateEpoch = date?.timeIntervalSince1970 ?? 0 }
    }

    // MARK: - Workouts (structured strength / cardio sessions)

    func saveWorkout(_ w: Workout, health: HealthManager) {
        mutate { e in
            if let i = e.workouts.firstIndex(where: { $0.id == w.id }) { e.workouts[i] = w }
            else { e.workouts.append(w) }
            // A logged workout satisfies any manual "moved/walk/gym/run" habit for the day.
            for h in data.habits where h.link == .manual && Self.isMovementHabit(h.title) {
                e.habitState[h.id] = true
            }
            e.nn.moved = true
        }
        if isToday { health.writeWorkout(w, settings: settings) }
    }

    func deleteWorkout(_ id: String) {
        mutate { e in e.workouts.removeAll { $0.id == id } }
    }

    private static func isMovementHabit(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["mov", "walk", "gym", "run", "train", "workout", "exercise", "lift"].contains { t.contains($0) }
    }

    // MARK: - Routine (weekly template)

    func addRoutineBlock(_ b: RoutineBlock) { data.routine.append(b); persistData() }
    func updateRoutineBlock(_ b: RoutineBlock) {
        if let i = data.routine.firstIndex(where: { $0.id == b.id }) { data.routine[i] = b; persistData() }
    }
    func deleteRoutineBlock(_ id: String) { data.routine.removeAll { $0.id == id }; persistData() }

    /// Routine blocks expected on a given weekday (1=Sun…7=Sat); weekday 0 = daily.
    func routineFor(weekday: Int) -> [RoutineBlock] {
        data.routine.filter { $0.weekday == 0 || $0.weekday == weekday }
            .sorted { ($0.hour * 60 + $0.minute) < ($1.hour * 60 + $1.minute) }
    }
    func expectedToday() -> [RoutineBlock] {
        routineFor(weekday: Calendar.current.component(.weekday, from: Date()))
    }

    // MARK: - Week outlook (AI)

    @Published var weekOutlook: String = UserDefaults.standard.string(forKey: "week_outlook") ?? ""
    @Published var weekOutlookLoading = false
    private var weekOutlookWeek: String = UserDefaults.standard.string(forKey: "week_outlook_week") ?? ""

    /// `eventsText` is a short summary of upcoming Apple Calendar events, supplied by the view
    /// (which holds CalendarManager). Mirrors refreshWeeklyReview.
    func refreshWeekOutlook(eventsText: String = "", force: Bool = false) async {
        if !force && weekOutlookWeek == currentWeekID && !weekOutlook.isEmpty { return }
        weekOutlookLoading = true
        let st = weeklyStats()
        let wp = weekProgress()
        let ins = insights().prefix(3).map { "- \($0.title): \($0.detail)" }.joined(separator: "\n")
        let sessions = upcomingSessions(days: 7).prefix(8).map { s in
            "\(Self.shortDate(s.date)) \(ScheduledSession.label(s.kind)): \(s.title.isEmpty ? ScheduledSession.label(s.kind) : s.title)"
        }.joined(separator: "\n")
        let occ = upcomingOccasions(days: 30).prefix(5).map { o in
            "\(o.title) in \(o.nextDate.map { days(until: $0) } ?? 0)d"
        }.joined(separator: "\n")
        let prompt = """
        You are a warm, sharp personal coach writing a short look-ahead for the user's week. Be specific and encouraging, plain text, no headings or bullets, under 70 words. End with ONE clear priority for the week.

        So far this week: \(wp.won)/\(wp.logged) winning days logged, avg score \(String(format: "%.1f", st.avgScore))/5. Targets: ~\(Int(targets.protein))g protein, \(Int(targets.steps)) steps, \(fmtT(targets.studyHours))h \(targets.workMode).
        What's working:\n\(ins.isEmpty ? "(not enough data yet)" : ins)
        Planned sessions:\n\(sessions.isEmpty ? "(none scheduled)" : sessions)
        Upcoming events:\n\(occ.isEmpty ? "(none)" : occ)
        Calendar commitments:\n\(eventsText.isEmpty ? "(calendar not connected)" : eventsText)
        """
        do {
            let text = try await estimator.suggest(prompt: prompt, settings: settings)
            if !text.isEmpty {
                weekOutlook = text
                weekOutlookWeek = currentWeekID
                UserDefaults.standard.set(text, forKey: "week_outlook")
                UserDefaults.standard.set(currentWeekID, forKey: "week_outlook_week")
            }
        } catch {}
        weekOutlookLoading = false
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE d"
        return f.string(from: d)
    }

    // MARK: - AI weekly plan (draft → apply)

    @Published var planDraft: [PlanBlock] = []
    @Published var planLoading = false

    private func plannerContext() -> String {
        let st = weeklyStats()
        let routineLines = data.routine.map { b -> String in
            let day = b.weekday == 0 ? "daily" : ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][b.weekday]
            return "- \(day) \(String(format: "%02d:%02d", b.hour, b.minute)) \(ScheduledSession.label(b.kind))\(b.withPT ? " (PT)" : "")"
        }.joined(separator: "\n")
        let readinessTrend = sortedEntries().suffix(7).compactMap { $0.readiness > 0 ? "\($0.date):\($0.readiness)" : nil }.joined(separator: ", ")
        let health = healthIndex()
        let work = targets.workMode == "work" ? "work" : "study"
        // Day statuses for the next 7 days (so the AI rests/skips sick & travel days).
        let cal = Calendar.current
        let statusLines = (0..<7).compactMap { off -> String? in
            guard let d = cal.date(byAdding: .day, value: off, to: Date()) else { return nil }
            let s = effectiveStatus(for: Self.dateString(d))
            return s == "normal" ? nil : "day \(off): \(DayStatus.label(s))"
        }.joined(separator: ", ")
        return """
        USER: \(work) mode; targets ~\(Int(targets.protein))g protein, \(Int(targets.steps)) steps, \(fmtT(targets.studyHours))h \(work)/day. Avg daily score \(String(format: "%.1f", st.avgScore))/5.
        ROUTINE TEMPLATE:\n\(routineLines.isEmpty ? "(none set)" : routineLines)
        READINESS (recent): \(readinessTrend.isEmpty ? "n/a" : readinessTrend)
        \(statusLines.isEmpty ? "" : "FLAGGED DAYS (no workouts; travel = light/none, sick = rest only, rest = recovery): \(statusLines)")
        \(weatherContext.isEmpty ? "" : "WEATHER (next days): \(weatherContext)")
        \(health.isEmpty ? "" : "HEALTH PROFILE:\n\(health)")
        """
    }

    /// Weather summary injected into the planner (set by the view from WeatherManager).
    var weatherContext: String = ""

    func generateAIWeekPlan(eventsText: String = "") async {
        planLoading = true
        let ctx = plannerContext() + (eventsText.isEmpty ? "" : "\nCALENDAR COMMITMENTS (don't overlap):\n\(eventsText)")
        do {
            var blocks = try await estimator.generateWeekPlan(context: ctx, settings: settings)
            blocks.sort { ($0.day, $0.hour, $0.minute) < ($1.day, $1.hour, $1.minute) }
            planDraft = blocks
        } catch { planDraft = [] }
        planLoading = false
    }

    /// Remove previously-applied AI-plan sessions (and their calendar events/notifications).
    func clearAIPlan(calendar: CalendarManager? = nil) {
        for s in data.sessions where s.fromAIPlan {
            if let eid = s.calendarEventID { calendar?.removeEvent(id: eid) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["session-\(s.id)"])
        }
        data.sessions.removeAll { $0.fromAIPlan }
        persistData(); publishSnapshot()
    }

    /// Materialise the enabled draft blocks into scheduled sessions for the next 7 days.
    @discardableResult
    func applyWeekPlan(calendar: CalendarManager? = nil) -> Int {
        clearAIPlan(calendar: calendar)
        let cal = Calendar.current
        var added = 0
        let hardKinds: Set<String> = ["pt", "strength", "cardio", "run", "fitnessplus", "workout"]
        for b in planDraft where b.enabled {
            guard let day = cal.date(byAdding: .day, value: b.day, to: Date()) else { continue }
            // Auto-skip hard sessions on protected (sick/travel/rest) days.
            let status = effectiveStatus(for: Self.dateString(day))
            if DayStatus.isProtected(status) && hardKinds.contains(b.kind) { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = b.hour; comps.minute = b.minute
            guard let when = cal.date(from: comps) else { continue }
            let mapped = Self.displayKind(b.kind)
            let s = ScheduledSession(dateEpoch: when.timeIntervalSince1970,
                                     title: b.title.isEmpty ? ScheduledSession.label(mapped) : b.title,
                                     kind: mapped, durationMin: b.durationMin,
                                     withPT: mapped == "pt", remindMin: b.remind ? 15 : 0,
                                     fromAIPlan: true)
            addSession(s, calendar: calendar)
            added += 1
        }
        planDraft = []
        return added
    }

    static func displayKind(_ k: String) -> String {
        let known = Set(ScheduledSession.kinds.map { $0.id })
        if known.contains(k) { return k }
        switch k {
        case "workout", "gym", "lift": return "strength"
        case "meditation", "breathe": return "winddown"
        default: return "custom"
        }
    }

    // MARK: - Countdowns (multiple, e.g. an exam and a deadline at once)

    func addCountdown(name: String, date: Date, kind: String) {
        data.countdowns.append(Countdown(name: name, dateEpoch: date.timeIntervalSince1970, kind: kind))
        persistData()
    }
    func deleteCountdown(_ id: String) {
        data.countdowns.removeAll { $0.id == id }; persistData()
    }
    func days(until date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                        to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
    /// Migrate the old single exam into the countdowns list once.
    func migrateExamIfNeeded() {
        guard data.countdowns.isEmpty, !targets.examName.isEmpty, let d = targets.examDate else { return }
        data.countdowns.append(Countdown(name: targets.examName, dateEpoch: d.timeIntervalSince1970,
                                         kind: targets.workMode))
        persistData()
    }

    /// Record a finished study session (minutes) into today's hours.
    func logStudySession(subject: String, minutes: Int) {
        guard minutes > 0 else { return }
        if !isToday { goTo(date: Self.dateString(Date())) }
        mutate { e in
            e.studySessions.append(StudySession(subject: subject, minutes: minutes))
            e.studyHours += Double(minutes) / 60.0
        }
    }

    // MARK: - Focus mode (ADHD-friendly single-task queue; sessions still run through StudyTimer)

    private let focusQueueKey = "focus_queue_v1"
    @Published var focusQueue: [String] = UserDefaults.standard.stringArray(forKey: "focus_queue_v1") ?? []

    func addFocusTask(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !focusQueue.contains(t) else { return }
        focusQueue.append(t)
        UserDefaults.standard.set(focusQueue, forKey: focusQueueKey)
    }
    func removeFocusTask(_ text: String) {
        focusQueue.removeAll { $0 == text }
        UserDefaults.standard.set(focusQueue, forKey: focusQueueKey)
    }

    // MARK: - Date helpers

    static func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    static func parse(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s) ?? Date()
    }

    var todaySubtitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Self.parse(date))
    }

    // MARK: - Persistence

    private func load() {
        let d = UserDefaults.standard
        if let raw = d.data(forKey: dataKey),
           let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            data = decoded
        }
        if let raw = d.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: raw) {
            settings = decoded
        }
        if let raw = d.data(forKey: targetsKey),
           let decoded = try? JSONDecoder().decode(Targets.self, from: raw) {
            targets = decoded
        }
        if let raw = d.data(forKey: modulesKey),
           let decoded = try? JSONDecoder().decode(ModulePrefs.self, from: raw) {
            modules = decoded
        }
        if let raw = d.data(forKey: personalKey),
           let decoded = try? JSONDecoder().decode(Personalization.self, from: raw) {
            personal = decoded
        }
    }

    func updateTargets(_ change: (inout Targets) -> Void) {
        change(&targets)
        if let raw = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(raw, forKey: targetsKey)
        }
        objectWillChange.send()
    }

    func updateModules(_ change: (inout ModulePrefs) -> Void) {
        change(&modules)
        if let raw = try? JSONEncoder().encode(modules) {
            UserDefaults.standard.set(raw, forKey: modulesKey)
        }
        objectWillChange.send()
    }

    func completeOnboarding() {
        onboardingDone = true
        UserDefaults.standard.set(true, forKey: "onboarding_done_v1")
    }

    func replayOnboarding() {
        onboardingDone = false
        UserDefaults.standard.set(false, forKey: "onboarding_done_v1")
    }

    /// Apply onboarding choices: which pillars/modules are active, plus faith handling.
    func applyOnboarding(areas: Set<Pillar>, faith: String, spiritualityName: String) {
        for i in data.habits.indices {
            let p = data.habits[i].pillar
            if [.health, .spirituality, .work].contains(p) {
                data.habits[i].active = areas.contains(p)
            }
            // A prayer-linked habit only makes sense for Islam.
            if p == .spirituality, data.habits[i].link == .prayer, faith != "islam" {
                data.habits[i].active = false
            }
        }
        // Seed tailored starter habits for any selected area with no active habit yet.
        for p in [Pillar.health, .spirituality, .work, .custom] where areas.contains(p) {
            let hasActive = data.habits.contains { $0.pillar == p && $0.active }
            guard !hasActive else { continue }
            var nextOrder = (data.habits.map(\.order).max() ?? -1) + 1
            for var starter in HabitDef.starters(pillar: p, workMode: targets.workMode, faith: faith) {
                if data.habits.contains(where: { $0.pillar == p && $0.title == starter.title }) { continue }
                starter.order = nextOrder; nextOrder += 1
                data.habits.append(starter)
            }
        }
        persistData()
        updateModules { m in
            m.health = areas.contains(.health)
            m.meals = areas.contains(.health)
            m.hydration = areas.contains(.health)
            m.prayer = areas.contains(.spirituality) && faith == "islam"
            m.workStudy = areas.contains(.work)
        }
        if areas.contains(.spirituality) {
            let nm = spiritualityName.trimmingCharacters(in: .whitespaces)
            if !nm.isEmpty { updatePersonal { $0.pillarTitles[Pillar.spirituality.rawValue] = nm } }
        }
    }

    private func persistData() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: dataKey)
        }
    }

    private func persistSettings() {
        if let raw = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(raw, forKey: settingsKey)
        }
    }

    private func loadDraft(for date: String) -> Entry {
        data.entries[date] ?? Entry(date: date)
    }

    // MARK: - Date navigation (edit any day)

    var isToday: Bool { date == Self.dateString(Date()) }

    /// Switch the working day. The current draft is already autosaved on each edit.
    func goTo(date newDate: String) {
        date = newDate
        draft = loadDraft(for: newDate)
    }

    func goTo(date d: Date) { goTo(date: Self.dateString(d)) }

    func shiftDay(by days: Int) {
        let base = Self.parse(date)
        if let d = Calendar.current.date(byAdding: .day, value: days, to: base) {
            // Don't allow navigating into the future.
            if Self.dateString(d) <= Self.dateString(Date()) { goTo(date: d) }
        }
    }

    var canGoForward: Bool { !isToday }

    /// Friendly label for the current day ("Today", "Yesterday", or a date).
    var dayLabel: String {
        if isToday { return "Today" }
        let cal = Calendar.current
        if let y = cal.date(byAdding: .day, value: -1, to: Date()),
           Self.dateString(y) == date { return "Yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE, d MMM"
        return f.string(from: Self.parse(date))
    }

    /// Mutate the working draft then autosave.
    func mutate(_ change: (inout Entry) -> Void) {
        change(&draft)
        commit()
    }

    /// Set/adjust a meal's eaten time (epoch). Pass nil to clear.
    func setMealTime(_ key: String, _ date: Date?) {
        mutate { e in
            if let date { e.mealTimes[key] = date.timeIntervalSince1970 }
            else { e.mealTimes[key] = nil }
        }
    }

    /// Epoch of the latest meal logged today (for late-meal/readiness checks).
    func lastMealEpoch(_ e: Entry) -> Double? { e.mealTimes.values.max() }
    func dinnerEpoch(_ e: Entry) -> Double? { e.mealTimes["dinner"] }

    /// Meal text plus its time, for prompts (e.g. "rice & curry (1:30 PM)").
    private func mealWithTime(_ e: Entry, _ key: String) -> String {
        let text: String
        switch key {
        case "breakfast": text = e.meals.breakfast
        case "lunch": text = e.meals.lunch
        case "dinner": text = e.meals.dinner
        case "snacks": text = e.meals.snacks
        case "drinks": text = e.meals.drinks
        default: text = ""
        }
        if text.isEmpty { return "-" }
        if let t = e.mealTimes[key] {
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            return "\(text) (\(f.string(from: Date(timeIntervalSince1970: t))))"
        }
        return text
    }

    private func commit() {
        let eating = eatingScoreResult(for: draft)
        draft.eatingScore = eating.available ? eating.score : nil
        if draft.isMeaningful {
            data.entries[draft.date] = draft
        } else {
            data.entries.removeValue(forKey: draft.date)
        }
        persistData()
        publishSnapshot()
    }

    /// Push the bits the home-screen widgets show into the shared App Group.
    func publishSnapshot() {
        guard isToday else { return }   // widgets always reflect today
        var s = SharedStore.load()
        s.nnDone = draftScore
        s.nnTotal = max(1, activeHabits.count)
        s.prayersDone = draft.prayers.count
        s.score = draftScore
        s.waterMl = draft.waterMl
        s.caloriesText = draft.calories.isEmpty ? "—" : draft.calories
        s.proteinText = draft.proteinG.isEmpty ? "—" : draft.proteinG
        let wp = weekProgress()
        s.weekDaysWon = wp.won
        s.weekDaysLogged = wp.logged
        s.workoutsThisWeek = workoutSessionsThisWeek()
        s.studyHoursToday = draft.studyHours
        if let ns = nextSession() {
            s.nextSessionTitle = ns.title.isEmpty ? ScheduledSession.label(ns.kind) : ns.title
            s.nextSessionEpoch = ns.dateEpoch
        } else { s.nextSessionTitle = ""; s.nextSessionEpoch = 0 }
        if let no = upcomingOccasions(days: 120).first, let nd = no.nextDate {
            s.nextOccasionTitle = no.title
            s.nextOccasionEpoch = nd.timeIntervalSince1970
        } else { s.nextOccasionTitle = ""; s.nextOccasionEpoch = 0 }
        s.readiness = draft.readiness
        s.sleepScore = draft.sleepScore
        s.activeScore = draft.activeScore ?? -1
        s.eatingScore = draft.eatingScore ?? -1
        s.projectedWeeklyKg = weeklyEnergyBalance().projectedKg
        s.sleepNeedHours = sleepPlanTonight?.needHours ?? 0
        s.recommendedBedEpoch = sleepPlanTonight?.recommendedBedEpoch ?? 0
        s.dayStatus = effectiveStatus(for: draft.date)
        // Ring row for a future widget pass — prayer times aren't available here (AppStore stays
        // prayer-agnostic), so a prayer ring simply reads unavailable/"—" in the snapshot for now.
        let ringCtx = ringContext(prayerTimes: nil, nextFajr: nil)
        s.rings = visibleRings.map { def in
            let r = RingEngine.compute(def, entry: draft, ctx: ringCtx)
            return SnapshotRing(title: String(def.displayTitle.prefix(24)), pct: Int((r.fraction * 100).rounded()),
                                display: String(r.displayValue.prefix(24)), colorHex: def.colorHex)
        }
        s.topTip = String((dayTips.first ?? "").prefix(120))
        SharedStore.save(s)
        SharedStore.save(s, suite: SharedStore.watchAppGroup)
        WidgetCenter.shared.reloadAllTimelines()
        PhoneSync.shared.sendSnapshot()
    }

    // MARK: - Scheduled sessions (gym / PT / cardio / mobility)

    func addSession(_ s: ScheduledSession, calendar: CalendarManager? = nil) {
        var session = s
        if let cal = calendar, settings.calendarSync, cal.calAuthorized {
            session.calendarEventID = cal.addEvent(
                title: session.title.isEmpty ? ScheduledSession.label(session.kind) : session.title,
                start: session.date, durationMin: session.durationMin,
                notes: session.withPT ? "With PT" : "")
        }
        if let cal = calendar, settings.remindersSync, cal.remindersAuthorized {
            cal.addReminder(title: session.title.isEmpty ? ScheduledSession.label(session.kind) : session.title,
                            due: session.date)
        }
        data.sessions.append(session)
        scheduleSessionNotification(session)
        persistData()
        publishSnapshot()
    }

    func updateSession(_ s: ScheduledSession) {
        guard let i = data.sessions.firstIndex(where: { $0.id == s.id }) else { return }
        data.sessions[i] = s
        scheduleSessionNotification(s)
        persistData()
        publishSnapshot()
    }

    func deleteSession(_ id: String, calendar: CalendarManager? = nil) {
        if let s = data.sessions.first(where: { $0.id == id }), let eid = s.calendarEventID {
            calendar?.removeEvent(id: eid)
        }
        data.sessions.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["session-\(id)"])
        persistData()
        publishSnapshot()
    }

    func completeSession(_ id: String) {
        guard let i = data.sessions.firstIndex(where: { $0.id == id }) else { return }
        data.sessions[i].done = true
        let kind = data.sessions[i].kind
        // Physical sessions satisfy the movement habit for that day.
        if kind != "focus" && Calendar.current.isDateInToday(data.sessions[i].date) {
            if !isToday { goTo(date: Self.dateString(Date())) }
            mutate { e in
                for h in data.habits where h.link == .manual && Self.isMovementHabit(h.title) { e.habitState[h.id] = true }
                e.nn.moved = true
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["session-\(id)"])
        persistData()
        publishSnapshot()
    }

    /// Materialise the next 7 days of routine blocks into concrete sessions (skipping duplicates).
    @discardableResult
    func generateWeekFromRoutine(calendar: CalendarManager? = nil) -> Int {
        let cal = Calendar.current
        var added = 0
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: Date()) else { continue }
            let weekday = cal.component(.weekday, from: day)
            for b in routineFor(weekday: weekday) {
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = b.hour; comps.minute = b.minute
                guard let when = cal.date(from: comps), when > Date() else { continue }
                let exists = data.sessions.contains {
                    $0.fromRoutine && abs($0.dateEpoch - when.timeIntervalSince1970) < 60 && $0.title == b.title && $0.kind == b.kind
                }
                if exists { continue }
                let s = ScheduledSession(dateEpoch: when.timeIntervalSince1970,
                                         title: b.title, kind: b.withPT ? "pt" : b.kind,
                                         durationMin: b.durationMin, withPT: b.withPT,
                                         remindMin: b.remind ? 60 : 0, fromRoutine: true)
                addSession(s, calendar: calendar)
                added += 1
            }
        }
        return added
    }

    private func scheduleSessionNotification(_ s: ScheduledSession) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["session-\(s.id)"])
        guard s.remindMin > 0, !s.done else { return }
        let fireDate = s.date.addingTimeInterval(-Double(s.remindMin) * 60)
        guard fireDate > Date() else { return }
        let content = UNMutableNotificationContent()
        let name = s.title.isEmpty ? ScheduledSession.label(s.kind) : s.title
        content.title = "\(name) soon 💪"
        content.body = s.withPT ? "Session with your PT in \(s.remindMin) min." : "Your \(ScheduledSession.label(s.kind).lowercased()) is in \(s.remindMin) min."
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: "session-\(s.id)", content: content, trigger: trigger))
    }

    /// Scheduled sessions in the next `days`, soonest first (undone).
    func upcomingSessions(days: Int = 7) -> [ScheduledSession] {
        let now = Date()
        let end = now.addingTimeInterval(Double(days) * 86400)
        return data.sessions
            .filter { !$0.done && $0.date >= Calendar.current.startOfDay(for: now) && $0.date <= end }
            .sorted { $0.dateEpoch < $1.dateEpoch }
    }
    func nextSession() -> ScheduledSession? { upcomingSessions(days: 14).first }

    // MARK: - Occasions (events & travel)

    func addOccasion(_ o: Occasion) { data.occasions.append(o); persistData(); publishSnapshot() }
    func updateOccasion(_ o: Occasion) {
        if let i = data.occasions.firstIndex(where: { $0.id == o.id }) { data.occasions[i] = o; persistData(); publishSnapshot() }
    }
    func deleteOccasion(_ id: String) { data.occasions.removeAll { $0.id == id }; persistData(); publishSnapshot() }

    @Published var occasionPlanLoading = false

    /// Ask the AI to fill in an occasion's ideas/checklist/itinerary. Feeds the user's own context
    /// (base comments), any pasted booking, and — when `refine` is set — the CURRENT plan plus the
    /// requested changes, so the AI revises the existing plan rather than starting from scratch.
    func planOccasion(_ id: String, pasted: String? = nil, refine: String? = nil) async {
        guard let o = data.occasions.first(where: { $0.id == id }) else { return }
        occasionPlanLoading = true
        let dateText = o.nextDate.map { Self.dateString($0) } ?? ""
        var ctx: [String] = []
        if !o.context.isEmpty { ctx.append("User's notes / brief: \(o.context)") }
        if let pasted, !pasted.isEmpty { ctx.append("Booking / details: \(pasted)") }
        if let refine, !refine.isEmpty {
            let current = "Current checklist: " + o.checklist.map { $0.text }.joined(separator: "; ")
                + (o.itinerary.isEmpty ? "" : "\nCurrent itinerary: " + o.itinerary.map { "\($0.title) — \($0.detail)" }.joined(separator: "; "))
            ctx.append("Revise the existing plan below per the requested change, keeping what still fits.\n\(current)\nRequested change: \(refine)")
        }
        do {
            let r = try await estimator.planOccasion(title: o.title, type: o.type, person: o.person,
                                                     location: o.location, dateText: dateText,
                                                     pasted: ctx.isEmpty ? nil : ctx.joined(separator: "\n\n"), settings: settings)
            if let i = data.occasions.firstIndex(where: { $0.id == id }) {
                if !r.ideas.isEmpty { data.occasions[i].notes = "Ideas: " + r.ideas.joined(separator: " · ") }
                data.occasions[i].checklist = r.checklist.map { ChecklistItem(text: $0) }
                data.occasions[i].itinerary = r.itinerary
                persistData()
            }
        } catch {}
        occasionPlanLoading = false
    }

    func toggleChecklistItem(occasionID: String, itemID: String) {
        guard let oi = data.occasions.firstIndex(where: { $0.id == occasionID }),
              let ci = data.occasions[oi].checklist.firstIndex(where: { $0.id == itemID }) else { return }
        data.occasions[oi].checklist[ci].done.toggle()
        persistData()
    }

    /// Push an occasion to Apple Calendar/Reminders.
    func syncOccasion(_ id: String, calendar: CalendarManager) {
        guard let i = data.occasions.firstIndex(where: { $0.id == id }), let date = data.occasions[i].nextDate else { return }
        let o = data.occasions[i]
        if settings.calendarSync, calendar.calAuthorized {
            calendar.addEvent(title: o.title, start: Calendar.current.startOfDay(for: date).addingTimeInterval(9*3600),
                              durationMin: 60, notes: o.notes)
        }
        if settings.remindersSync, calendar.remindersAuthorized {
            // A prep reminder a few days before.
            let prep = Calendar.current.date(byAdding: .day, value: -3, to: date) ?? date
            calendar.addReminder(title: "Prep: \(o.title)", due: prep, notes: o.notes)
        }
        data.occasions[i].calendarSynced = true
        persistData()
    }

    /// Import birthdays/anniversaries from Contacts + the Calendar birthdays calendar, de-duped.
    @discardableResult
    func importOccasions(from calendar: CalendarManager) -> Int {
        let imported = calendar.importContactBirthdays() + calendar.occasionsFromCalendar()
        var added = 0
        let cal = Calendar(identifier: .gregorian)
        func key(_ o: Occasion) -> String {
            let md = o.dateEpoch > 0 ? cal.dateComponents([.month, .day], from: Date(timeIntervalSince1970: o.dateEpoch)) : DateComponents()
            return "\(o.person.lowercased())|\(o.type)|\(md.month ?? 0)-\(md.day ?? 0)|\(o.title.lowercased())"
        }
        var seen = Set(data.occasions.map { key($0) })
        for o in imported where !seen.contains(key(o)) {
            data.occasions.append(o); seen.insert(key(o)); added += 1
        }
        if added > 0 { persistData(); publishSnapshot() }
        return added
    }

    /// Occasions whose next occurrence falls in the next `days`, soonest first.
    func upcomingOccasions(days: Int = 60) -> [Occasion] {
        let now = Calendar.current.startOfDay(for: Date())
        let end = now.addingTimeInterval(Double(days) * 86400)
        return data.occasions
            .compactMap { o -> (Occasion, Date)? in o.nextDate.map { (o, $0) } }
            .filter { $0.1 >= now && $0.1 <= end }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    /// Days this calendar week (Mon–Sun) that were logged / won.
    func weekProgress() -> (won: Int, logged: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2   // Monday
        let today = Date()
        guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else { return (0, 0) }
        var won = 0, logged = 0
        var day = interval.start
        while day < interval.end && day <= today {
            if let e = data.entries[Self.dateString(day)], e.isMeaningful {
                logged += 1
                if dayWon(e) { won += 1 }
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? interval.end
        }
        return (won, logged)
    }

    /// Apply an action sent from the Apple Watch (always to today).
    func applyWatchAction(_ action: String, amount: Int?, name: String?) {
        if !isToday { goTo(date: Self.dateString(Date())) }
        switch action {
        case "water":
            addWater(amount ?? 250)
        case "prayer":
            guard let name else { return }
            mutate { d in
                switch name {
                case "fajr": d.prayers.fajr = true; d.nn.fajr = true
                case "dhuhr": d.prayers.dhuhr = true
                case "asr": d.prayers.asr = true
                case "maghrib": d.prayers.maghrib = true
                case "isha": d.prayers.isha = true
                default: break
                }
            }
        case "workout_quick":
            mutate { e in
                e.workouts.append(Workout(kind: "cardio", title: name ?? "Walk", durationMin: 20))
                for h in data.habits where h.link == .manual && Self.isMovementHabit(h.title) { e.habitState[h.id] = true }
                e.nn.moved = true
            }
        default: break
        }
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        persistSettings()
    }

    // MARK: - Configurable habits & scoring

    var activeHabits: [HabitDef] {
        data.habits.filter { $0.active }.sorted { $0.order < $1.order }
    }

    func habits(in pillar: Pillar) -> [HabitDef] {
        activeHabits.filter { $0.pillar == pillar }
    }

    var usedPillars: [Pillar] {
        Pillar.allCases.filter { p in activeHabits.contains { $0.pillar == p } }
    }

    private var waterTargetMl: Double {
        let v = UserDefaults.standard.integer(forKey: "hyd_target")
        return v > 0 ? Double(v) : 3000
    }

    /// Is a habit satisfied for the given day?
    func isSatisfied(_ def: HabitDef, _ e: Entry) -> Bool {
        switch def.link {
        case .manual: return e.habitState[def.id] ?? false
        case .protein: return (Double(e.proteinG) ?? 0) >= targets.protein
        case .prayer: return def.effectivePrayerNames.allSatisfy { e.prayers.isOn($0) }   // multi-prayer goal: all required prayers marked
        case .steps: return (Double(e.steps) ?? 0) >= (def.threshold > 0 ? def.threshold : targets.steps)
        case .activeEnergy: return e.activeKcal >= (def.threshold > 0 ? def.threshold : 400)
        case .water: return Double(e.waterMl) >= (def.threshold > 0 ? def.threshold : waterTargetMl)
        case .studyHours: return e.studyHours >= (def.threshold > 0 ? def.threshold : targets.studyHours)
        case .sleep: return e.sleepScore >= (def.threshold > 0 ? Int(def.threshold) : 70)
        }
    }

    func score(_ e: Entry) -> Int {
        activeHabits.filter { isSatisfied($0, e) }.count
    }

    var draftScore: Int { score(draft) }
    var habitTotal: Int { activeHabits.count }

    /// Did the day clear the bar (≥60% of habits)?
    func dayWon(_ e: Entry) -> Bool {
        let total = activeHabits.count
        guard total > 0 else { return false }
        return Double(score(e)) / Double(total) >= 0.6
    }

    func proteinSatisfied(_ e: Entry) -> Bool {
        (Double(e.proteinG) ?? 0) >= targets.protein
    }

    /// Toggle a manual habit for the current draft.
    func toggleHabit(_ def: HabitDef) {
        guard def.link == .manual else { return }
        mutate { e in e.habitState[def.id] = !(e.habitState[def.id] ?? false) }
    }

    // MARK: - Habit management

    func addHabit(_ h: HabitDef) {
        var def = h
        def.order = (data.habits.map(\.order).max() ?? -1) + 1
        data.habits.append(def)
        persistData(); publishSnapshot()
    }
    func updateHabit(_ h: HabitDef) {
        if let i = data.habits.firstIndex(where: { $0.id == h.id }) { data.habits[i] = h }
        persistData(); publishSnapshot()
    }
    func deleteHabit(_ id: String) {
        data.habits.removeAll { $0.id == id }
        persistData(); publishSnapshot()
    }

    // MARK: - Rings (Today ring row + custom rings)

    /// All rings in editor order (for the ring editor / reorder sheet).
    var allRingsOrdered: [RingDef] { data.rings.sorted { $0.order < $1.order } }

    /// The rings actually shown on Today: enabled, in order, capped to the user's chosen count (3 or 4).
    var visibleRings: [RingDef] {
        Array(allRingsOrdered.filter { $0.enabled }.prefix(settings.visibleRingCount))
    }

    func addRing(_ r: RingDef) {
        var def = r
        def.order = (data.rings.map(\.order).max() ?? -1) + 1
        data.rings.append(def)
        persistData(); publishSnapshot()
    }
    func updateRing(_ r: RingDef) {
        if let i = data.rings.firstIndex(where: { $0.id == r.id }) { data.rings[i] = r }
        persistData(); publishSnapshot()
    }
    func deleteRing(_ id: String) {
        data.rings.removeAll { $0.id == id }
        persistData(); publishSnapshot()
    }
    func setRingEnabled(_ id: String, _ on: Bool) {
        if let i = data.rings.firstIndex(where: { $0.id == id }) { data.rings[i].enabled = on }
        persistData(); publishSnapshot()
    }
    func moveRing(from source: IndexSet, to destination: Int) {
        var ordered = allRingsOrdered
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, var r) in ordered.enumerated() { r.order = i; ordered[i] = r }
        for r in ordered { if let i = data.rings.firstIndex(where: { $0.id == r.id }) { data.rings[i] = r } }
        persistData(); publishSnapshot()
    }
    func setVisibleRingCount(_ n: Int) {
        updateSettings { $0.visibleRingCount = min(4, max(3, n)) }
        publishSnapshot()
    }

    /// Local context a ring might need beyond the day's Entry (targets, hydration target, prayer times).
    /// `prayerTimes`/`nextFajr` come from the caller (TodayView, which already has PrayerManager) —
    /// AppStore stays prayer-agnostic, same pattern as `togglePrayer`.
    func ringContext(prayerTimes: PrayerTimes?, nextFajr: Date?) -> RingEngine.Context {
        RingEngine.Context(waterTargetMl: waterTargetMl, studyGoalHours: targets.studyHours,
                           proteinTargetG: targets.protein, prayerTimes: prayerTimes, nextFajr: nextFajr)
    }
    func ringResult(_ def: RingDef, prayerTimes: PrayerTimes?, nextFajr: Date?) -> RingResult {
        RingEngine.compute(def, entry: draft, ctx: ringContext(prayerTimes: prayerTimes, nextFajr: nextFajr))
    }

    func sortedEntries() -> [Entry] {
        data.entries.values
            .filter { !$0.date.isEmpty }
            .sorted { $0.date < $1.date }
    }

    func streak() -> Int {
        let entries = sortedEntries()
        guard !entries.isEmpty else { return 0 }
        var won: [String: Bool] = [:]
        var byDate: [String: Entry] = [:]
        for e in entries { won[e.date] = dayWon(e); byDate[e.date] = e }
        var cur = Date()
        var st = 0
        for _ in 0..<400 {
            let ds = Self.dateString(cur)
            // Protected days (sick / travel / rest) pause the chain without breaking it.
            if DayStatus.isProtected(effectiveStatus(for: ds)) {
                cur = Calendar.current.date(byAdding: .day, value: -1, to: cur) ?? cur
                continue
            }
            if let w = won[ds] {
                if w { st += 1 } else { break }
            } else if st > 0 {
                break
            }
            cur = Calendar.current.date(byAdding: .day, value: -1, to: cur) ?? cur
        }
        return st
    }

    // MARK: - Day status (sick / travel / rest)

    func setDayStatus(_ status: String) { mutate { $0.status = status } }

    /// Manual status, or auto "travel" if a travel occasion spans that date.
    func effectiveStatus(for dateString: String) -> String {
        if let e = data.entries[dateString], e.status != "normal" { return e.status }
        let day = Calendar.current.startOfDay(for: Self.parse(dateString))
        for o in data.occasions where o.type == "travel" {
            // Single-day travel occasion (or its itinerary spanning the date).
            if let nd = o.nextDate, Calendar.current.isDate(nd, inSameDayAs: day) { return "travel" }
            let dates = o.itinerary.compactMap { $0.date }.map { Calendar.current.startOfDay(for: $0) }
            if let lo = dates.min(), let hi = dates.max(), day >= lo && day <= hi { return "travel" }
        }
        return "normal"
    }

    // MARK: - Score presentation

    func scoreMessage(_ s: Int) -> (title: String, sub: String, color: Color) {
        let total = max(1, habitTotal)
        let ratio = Double(s) / Double(total)
        if s == total {
            return ("Perfect day 🔥", "Every win, done. This is exactly it.", Theme.accentDark)
        } else if ratio >= 0.75 {
            return ("Strong day", "Chain\u{2019}s alive and humming.", Theme.sage)
        } else if ratio >= 0.6 {
            return ("Solid — chain\u{2019}s alive", "You showed up. That\u{2019}s the scoreboard.", Theme.sage)
        } else if s >= 1 {
            return ("You still showed up", "A floor on your worst day still counts.", Theme.secondaryInk)
        } else {
            return ("Tomorrow\u{2019}s a fresh start", "No shame here. The chain forgives a link.", Theme.secondaryInk)
        }
    }

    var tipText: String {
        Content.tips[dayOfYear % Content.tips.count]
    }

    private var dayOfYear: Int {
        let d = Self.parse(date)
        let cal = Calendar(identifier: .gregorian)
        return cal.ordinality(of: .day, in: .year, for: d) ?? 0
    }

    // MARK: - Trends data

    struct StatCard: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let delta: String
        let deltaColor: Color
    }

    var hasTrendData: Bool { !sortedEntries().isEmpty }

    func weightSeries() -> [Double] {
        let pts = sortedEntries().compactMap { e -> Double? in
            let w = Double(e.weight) ?? 0
            return w > 0 ? w : nil
        }
        return [Content.baselineWeight] + pts
    }

    var latestWeight: Double {
        let pts = sortedEntries().compactMap { e -> Double? in
            let w = Double(e.weight) ?? 0
            return w > 0 ? w : nil
        }
        return pts.last ?? Content.baselineWeight
    }

    func statCards() -> [StatCard] {
        let entries = sortedEntries()
        let scores = entries.map { Double(score($0)) }
        let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        let days5 = scores.filter { $0 == 5 }.count
        let cons5 = scores.isEmpty ? 0 : Int((Double(days5) / Double(scores.count) * 100).rounded())
        let wChange = latestWeight - Content.baselineWeight
        return [
            StatCard(label: "Weight now", value: String(format: "%.1f", latestWeight),
                     delta: (wChange <= 0 ? "▾ " : "▴ ") + String(format: "%.1f", abs(wChange)) + "kg",
                     deltaColor: wChange <= 0 ? Theme.sage : Theme.secondaryInk),
            StatCard(label: "Avg score", value: String(format: "%.1f", avg), delta: "/5", deltaColor: Theme.secondaryInk),
            StatCard(label: "5/5 days", value: "\(days5)", delta: "\(cons5)%", deltaColor: Theme.sage),
            StatCard(label: "Streak", value: "\(streak())", delta: "days", deltaColor: Theme.accentDark)
        ]
    }

    func scoreSeries() -> [Int] { sortedEntries().map { score($0) } }
    func proteinSeries() -> [Double] {
        sortedEntries().compactMap { let v = Double($0.proteinG) ?? 0; return v > 0 ? v : nil }
    }
    func calorieSeries() -> [Double] {
        sortedEntries().compactMap { let v = Double($0.calories) ?? 0; return v > 0 ? v : nil }
    }
    func stepsSeries() -> [Double] {
        sortedEntries().compactMap { let v = Double($0.steps) ?? 0; return v > 0 ? v : nil }
    }
    /// Per-day workout volume (Σ reps×weight) for the last `days`, oldest→newest, 0 where none.
    func workoutVolumeSeries(days: Int = 7) -> [Double] {
        let cal = Calendar.current
        return stride(from: days - 1, through: 0, by: -1).map { i in
            let d = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            return data.entries[Self.dateString(d)]?.workouts.reduce(0) { $0 + $1.volume } ?? 0
        }
    }
    func workoutSessionsThisWeek() -> Int {
        let cal = Calendar.current
        return (0..<7).reduce(0) { acc, i in
            let d = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            return acc + (data.entries[Self.dateString(d)]?.workouts.count ?? 0)
        }
    }
    func workoutVolumeThisWeek() -> Double { workoutVolumeSeries(days: 7).reduce(0, +) }

    // MARK: - Insights (rule-based correlations, offline)

    struct Insight: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    /// Discover a few honest patterns across logged days. Needs a handful of days to say anything.
    func insights() -> [Insight] {
        let all = sortedEntries().filter { $0.isMeaningful }
        guard all.count >= 4 else { return [] }
        var out: [Insight] = []

        func avgScore(_ es: [Entry]) -> Double {
            es.isEmpty ? 0 : es.map { Double(score($0)) }.reduce(0, +) / Double(es.count)
        }

        // Protein: days hitting target vs not.
        let hit = all.filter { proteinSatisfied($0) }
        let miss = all.filter { !proteinSatisfied($0) }
        if hit.count >= 2 && miss.count >= 2 {
            let d = avgScore(hit) - avgScore(miss)
            if d >= 0.5 {
                out.append(Insight(icon: "fork.knife",
                    title: "Protein days win more",
                    detail: String(format: "You average %.1f/5 on days you hit protein vs %.1f when you don\u{2019}t.",
                                   avgScore(hit), avgScore(miss))))
            }
        }

        // Workouts: training days vs rest days.
        let trained = all.filter { !$0.workouts.isEmpty }
        let rested = all.filter { $0.workouts.isEmpty }
        if trained.count >= 2 && rested.count >= 2 {
            let d = avgScore(trained) - avgScore(rested)
            if d >= 0.5 {
                out.append(Insight(icon: "dumbbell.fill",
                    title: "Training lifts your whole day",
                    detail: String(format: "Workout days score %.1f/5 vs %.1f on rest days.",
                                   avgScore(trained), avgScore(rested))))
            }
        }

        // Best weekday.
        var byWeekday: [Int: [Entry]] = [:]
        for e in all { byWeekday[weekday(of: e.date), default: []].append(e) }
        let ranked = byWeekday.filter { $0.value.count >= 2 }
            .map { (wd: $0.key, avg: avgScore($0.value)) }
            .sorted { $0.avg > $1.avg }
        if let best = ranked.first, let worst = ranked.last, ranked.count >= 2, best.avg - worst.avg >= 0.6 {
            out.append(Insight(icon: "calendar",
                title: "\(Self.weekdayName(best.wd)) is your strongest day",
                detail: "\(Self.weekdayName(best.wd)) averages \(String(format: "%.1f", best.avg))/5; \(Self.weekdayName(worst.wd)) is your softest at \(String(format: "%.1f", worst.avg))/5."))
        }

        // Streak.
        let st = streak()
        if st >= 2 {
            out.append(Insight(icon: "flame.fill",
                title: "\(st)-day streak alive",
                detail: "You\u{2019}ve cleared the bar \(st) days running. Protect the chain."))
        }

        // Prayer consistency (only if any prayers logged).
        let prayed = all.filter { $0.prayers.count > 0 }
        if prayed.count >= 3 {
            let full = all.filter { $0.prayers.count == 5 }.count
            let pct = Int((Double(full) / Double(all.count) * 100).rounded())
            if pct > 0 {
                out.append(Insight(icon: "moon.stars.fill",
                    title: "All 5 prayers on \(pct)% of days",
                    detail: full >= all.count / 2 ? "Strong consistency — keep it anchored."
                                                  : "Room to anchor the day around salah."))
            }
        }

        return Array(out.prefix(4))
    }

    private func weekday(of dateString: String) -> Int {
        let d = Self.parse(dateString)
        return Calendar(identifier: .gregorian).component(.weekday, from: d)
    }
    private static func weekdayName(_ wd: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return (wd >= 1 && wd <= 7) ? names[wd] : "—"
    }

    /// Body-fat % over time (date-ordered) from imported body-composition records.
    func bodyFatSeries() -> [Double] {
        data.bodyComps.sorted { $0.date < $1.date }.compactMap { $0.bodyFat }.filter { $0 > 0 }
    }
    func leanMassSeries() -> [Double] {
        data.bodyComps.sorted { $0.date < $1.date }.compactMap { $0.leanMass }.filter { $0 > 0 }
    }

    func jogSeries() -> [Double] {
        sortedEntries().compactMap { e -> Double? in
            let run = e.run
            if let m = run.range(of: #"(\d+(?:\.\d+)?)\s*min"#, options: .regularExpression) {
                return Double(run[m].replacingOccurrences(of: "min", with: "").trimmingCharacters(in: .whitespaces))
            }
            if let v = Double(run.trimmingCharacters(in: .whitespaces)) { return v }
            return nil
        }
    }

    // MARK: - AI estimation

    func estimate() async {
        guard draft.meals.hasAny, aiStatus != .loading else { return }
        aiStatus = .loading
        aiErrorMessage = ""
        do {
            let result = try await estimator.estimate(meals: draft.meals, knownFoods: items(of: .food), settings: settings)
            mutate { d in
                d.ai = result
                // AI replaces the meal-derived totals but keeps any quick-logged items added on top.
                let logCal = d.logged.reduce(0) { $0 + $1.calories }
                let logPro = d.logged.reduce(0) { $0 + $1.protein }
                if let c = result.total.calories, c > 0 { d.calories = String(Int((c + logCal).rounded())) }
                if let p = result.total.protein, p > 0 { d.proteinG = String(Int((p + logPro).rounded())) }
            }
            aiStatus = .done
        } catch {
            aiErrorMessage = error.localizedDescription
            aiStatus = .error
        }
    }

    /// Correct one AI-estimated meal's calories; recomputes the whole-day total (+ quick-logged items
    /// on top, matching `estimate()`) so the structured estimate stays the source of truth after editing.
    func updateAIMealCalories(at index: Int, calories: Double) {
        mutate { d in
            guard var ai = d.ai, ai.meals.indices.contains(index) else { return }
            ai.meals[index].calories = max(0, calories)
            ai.total.calories = ai.meals.reduce(0) { $0 + ($1.calories ?? 0) }
            d.ai = ai
            let logCal = d.logged.reduce(0) { $0 + $1.calories * Double(max(1, $1.qty)) }
            d.calories = String(Int(((ai.total.calories ?? 0) + logCal).rounded()))
        }
    }

    /// Verifies the current provider/model/key (or Ollama host) with a tiny round-trip.
    func testAIConnection() async throws -> String {
        try await estimator.testConnection(settings: settings)
    }

    var aiModelLine: String {
        let prov = Providers.provider(settings.provider)
        let model = prov.models.first { $0.id == settings.model } ?? prov.models[0]
        return "Estimated by " + model.name
    }

    // MARK: - Catalog (known supplements & foods)

    func items(of kind: CatalogKind) -> [CatalogItem] {
        data.catalog.filter { $0.kind == kind }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// A short, context-relevant slice of the library for quick-add — tagged to the current meal,
    /// or (for untagged items) favorites/most-used — instead of dumping the whole library as chips.
    func suggestedQuickAddItems(of kind: CatalogKind, mealKey: String?) -> [CatalogItem] {
        let all = items(of: kind)
        let tagged = mealKey.map { key in all.filter { $0.mealTags.contains(key) } } ?? []
        let untaggedFavored = all.filter { $0.mealTags.isEmpty && ($0.favorite || $0.useCount > 0) }
            .sorted { ($0.favorite ? 1 : 0, $0.useCount, $0.lastUsedEpoch) > ($1.favorite ? 1 : 0, $1.useCount, $1.lastUsedEpoch) }
        var seen = Set<String>()
        return (tagged + untaggedFavored).filter { seen.insert($0.id).inserted }.prefix(8).map { $0 }
    }

    func addOrUpdate(_ item: CatalogItem) {
        if let idx = data.catalog.firstIndex(where: { $0.id == item.id }) {
            data.catalog[idx] = item
        } else {
            data.catalog.append(item)
        }
        persistData()
    }

    func deleteCatalogItem(_ id: String) {
        data.catalog.removeAll { $0.id == id }
        persistData()
    }

    /// Build a catalog item from a photo and/or text via the selected AI provider.
    func parseCatalogItem(kind: CatalogKind, text: String?, imageBase64: String?) async throws -> CatalogItem {
        try await estimator.parseItem(kind: kind, text: text, imageBase64: imageBase64, settings: settings)
    }

    /// Look up a scanned barcode against Open Food Facts (free, no key).
    func lookupBarcode(_ code: String, kind: CatalogKind) async -> CatalogItem? {
        let urlStr = "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,nutriments,serving_size"
        guard let url = URL(string: urlStr),
              let (d, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              (obj["status"] as? Int) == 1,
              let product = obj["product"] as? [String: Any] else { return nil }
        let nutr = product["nutriments"] as? [String: Any] ?? [:]
        func num(_ k: String) -> Double {
            if let v = nutr[k] as? Double { return v }
            if let v = nutr[k] as? Int { return Double(v) }
            if let v = nutr[k] as? String { return Double(v) ?? 0 }
            return 0
        }
        var name = (product["product_name"] as? String) ?? ""
        if name.isEmpty { name = (product["brands"] as? String) ?? "Scanned item" }
        let serving = (product["serving_size"] as? String) ?? ""
        let perServing = num("energy-kcal_serving") > 0
        func pick(_ base: String) -> Double { perServing && num("\(base)_serving") > 0 ? num("\(base)_serving") : num("\(base)_100g") }

        // Common micronutrients Open Food Facts exposes (base key, display name, unit).
        let microDefs: [(String, String, String)] = [
            ("sugars", "Sugars", "g"), ("salt", "Salt", "g"), ("sodium", "Sodium", "mg"),
            ("calcium", "Calcium", "mg"), ("iron", "Iron", "mg"), ("potassium", "Potassium", "mg"),
            ("magnesium", "Magnesium", "mg"), ("zinc", "Zinc", "mg"), ("cholesterol", "Cholesterol", "mg"),
            ("vitamin-a", "Vitamin A", "µg"), ("vitamin-c", "Vitamin C", "mg"), ("vitamin-d", "Vitamin D", "µg"),
            ("vitamin-b12", "Vitamin B12", "µg"), ("vitamin-b6", "Vitamin B6", "mg")
        ]
        var micros: [Micro] = []
        for (key, label, unit) in microDefs {
            var v = pick(key)
            if v <= 0 { continue }
            // OFF stores sodium/minerals in grams; convert to mg for readability.
            if unit == "mg" && v < 1 { v *= 1000 }
            if (key == "vitamin-a" || key == "vitamin-d") && v < 0.01 { v *= 1_000_000 } // g→µg fallback
            micros.append(Micro(name: label, amount: (v * 100).rounded() / 100, unit: unit))
        }
        return CatalogItem(
            kind: kind,
            name: name,
            serving: serving.isEmpty ? (perServing ? "1 serving" : "100 g") : serving,
            calories: pick("energy-kcal"),
            protein: pick("proteins"),
            carbs: pick("carbohydrates"),
            fat: pick("fat"),
            fiber: pick("fiber"),
            micros: micros
        )
    }

    /// Copy meals from the most recent earlier logged day into today.
    func repeatPreviousMeals() {
        guard let prior = sortedEntries().last(where: { $0.date < date && $0.meals.hasAny }) else { return }
        mutate { $0.meals = prior.meals }
    }

    var hasPriorMeals: Bool {
        sortedEntries().contains { $0.date < date && $0.meals.hasAny }
    }

    // MARK: - Structured food log (A1) + lookup chain (A2)

    /// Food entries for one meal, in log order.
    func foodEntries(_ mealKey: String) -> [FoodEntry] { draft.foodEntries.filter { $0.mealKey == mealKey } }

    /// Structured day totals from the food log (per-serving × qty).
    var foodTotals: (kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, sodium: Double) {
        draft.foodEntries.reduce(into: (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)) { acc, e in
            acc.0 += e.totalKcal; acc.1 += e.totalProtein; acc.2 += e.totalCarbs
            acc.3 += e.totalFat; acc.4 += e.totalFiber; acc.5 += e.totalSodium
        }
    }

    /// Tier 1+2 search (library → bundled DB), offline & synchronous — for search-as-you-type.
    /// NO network, NO LLM: a food the user already knows never triggers an AI call.
    func searchFood(_ query: String) -> [FoodMatch] { FoodLookup.local(query, catalog: data.catalog) }

    /// Tier 3: explicit Open Food Facts online search (network).
    func searchFoodOnline(_ query: String) async -> [FoodMatch] { await FoodLookup.off(query) }

    /// Add a resolved match as a structured entry — no AI involved.
    func addFoodMatch(_ match: FoodMatch, mealKey: String, qty: Double = 1) {
        addFoodEntry(match.toEntry(mealKey: mealKey, qty: qty))
    }

    /// Hand-entered food (name + calories, optional protein) — the search+manual path.
    func addManualFood(name: String, kcal: Double, protein: Double = 0, mealKey: String, qty: Double = 1) {
        addFoodEntry(FoodEntry(mealKey: mealKey, name: name, qty: qty, servingLabel: "1 serving",
                               kcal: kcal, protein: protein, source: .manual))
    }

    func addFoodEntry(_ entry: FoodEntry) {
        mutate { d in
            d.foodEntries.append(entry)
            d.calories = adjust(d.calories, by: entry.totalKcal)
            d.proteinG = adjust(d.proteinG, by: entry.totalProtein)
        }
    }
    func setFoodQty(_ id: String, qty: Double) {
        mutate { d in
            guard let i = d.foodEntries.firstIndex(where: { $0.id == id }) else { return }
            let old = d.foodEntries[i]
            let newQty = max(0, qty)
            if newQty == 0 {
                d.foodEntries.remove(at: i)
                d.calories = adjust(d.calories, by: -old.totalKcal)
                d.proteinG = adjust(d.proteinG, by: -old.totalProtein)
                return
            }
            d.calories = adjust(d.calories, by: old.kcal * (newQty - old.qty))
            d.proteinG = adjust(d.proteinG, by: old.protein * (newQty - old.qty))
            d.foodEntries[i].qty = newQty
        }
    }
    /// Replace an entry's editable fields (name / per-serving macros) and reconcile day totals.
    func updateFoodEntry(_ entry: FoodEntry) {
        mutate { d in
            guard let i = d.foodEntries.firstIndex(where: { $0.id == entry.id }) else { return }
            let old = d.foodEntries[i]
            d.foodEntries[i] = entry
            d.calories = adjust(d.calories, by: entry.totalKcal - old.totalKcal)
            d.proteinG = adjust(d.proteinG, by: entry.totalProtein - old.totalProtein)
        }
    }
    func removeFoodEntry(_ id: String) {
        mutate { d in
            guard let i = d.foodEntries.firstIndex(where: { $0.id == id }) else { return }
            let e = d.foodEntries.remove(at: i)
            d.calories = adjust(d.calories, by: -e.totalKcal)
            d.proteinG = adjust(d.proteinG, by: -e.totalProtein)
        }
    }

    /// NL → structured entries. Parses the sentence with the LLM, then upgrades each item's numbers
    /// to trusted library/DB values when the name is known (so the AI's guess is only kept for foods
    /// nothing else covers). Returns the count added. Throws if the AI call fails and nothing matched.
    @discardableResult
    func logMealText(_ text: String, mealKey: String) async throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let parsed = try await estimator.parseFoodItems(text: trimmed, settings: settings)
        var added = 0
        for var item in parsed {
            item.mealKey = mealKey
            if let known = FoodLookup.local(item.name, catalog: data.catalog).first(where: { $0.source.trusted }) {
                item.servingLabel = known.servingLabel.isEmpty ? item.servingLabel : known.servingLabel
                item.kcal = known.kcal; item.protein = known.protein; item.carbs = known.carbs
                item.fat = known.fat; item.fiber = known.fiber
                item.sodium = known.sodium > 0 ? known.sodium : item.sodium
                item.micros = known.micros; item.source = known.source
            }
            addFoodEntry(item)
            added += 1
        }
        return added
    }

    // MARK: - Quick logging

    func isLogged(_ itemID: String) -> Bool {
        draft.logged.contains { $0.itemID == itemID }
    }

    /// How many servings/doses of an item are logged today (0 if none).
    func loggedQty(_ itemID: String) -> Int {
        draft.logged.first { $0.itemID == itemID }?.qty ?? 0
    }

    /// Tick a catalog item on/off for today (1 serving ↔ none).
    func toggleLogged(_ item: CatalogItem) {
        setLoggedQty(item, qty: isLogged(item.id) ? 0 : 1)
    }

    func addServing(_ item: CatalogItem) { setLoggedQty(item, qty: loggedQty(item.id) + 1) }
    func removeServing(_ item: CatalogItem) { setLoggedQty(item, qty: loggedQty(item.id) - 1) }

    /// Set the number of servings of a catalog item for today, adjusting calorie/protein totals.
    func setLoggedQty(_ item: CatalogItem, qty: Int) {
        let newQty = max(0, qty)
        mutate { d in
            let current = d.logged.first { $0.itemID == item.id }?.qty ?? 0
            let delta = newQty - current
            guard delta != 0 else { return }
            d.calories = adjust(d.calories, by: item.calories * Double(delta))
            d.proteinG = adjust(d.proteinG, by: item.protein * Double(delta))
            if newQty == 0 {
                d.logged.removeAll { $0.itemID == item.id }
            } else if let idx = d.logged.firstIndex(where: { $0.itemID == item.id }) {
                d.logged[idx].qty = newQty
            } else {
                d.logged.append(LoggedItem(itemID: item.id, name: item.name,
                                           calories: item.calories, protein: item.protein,
                                           carbs: item.carbs, fat: item.fat, fiber: item.fiber,
                                           micros: item.micros, qty: newQty))
            }
            if delta > 0, let idx = data.catalog.firstIndex(where: { $0.id == item.id }) {
                data.catalog[idx].useCount += 1
                data.catalog[idx].lastUsedEpoch = Date().timeIntervalSince1970
            }
        }
    }

    // MARK: - Meal / day text export

    private func entry(for dateString: String) -> Entry? {
        dateString == draft.date ? draft : data.entries[dateString]
    }
    private static let mealKeys = ["breakfast", "snacks", "lunch", "dinner", "drinks"]
    private func mealText(_ e: Entry, key: String) -> String {
        switch key {
        case "breakfast": return e.meals.breakfast
        case "snacks": return e.meals.snacks
        case "lunch": return e.meals.lunch
        case "dinner": return e.meals.dinner
        case "drinks": return e.meals.drinks
        default: return ""
        }
    }
    private func mealLabel(_ key: String) -> String { key.capitalized }

    /// Plain-text export of one meal — its logged text plus the matching AI estimate row, if any.
    func exportMealText(_ dateString: String, mealKey: String) -> String {
        guard let e = entry(for: dateString) else { return "" }
        var lines = ["\(mealLabel(mealKey)) — \(dateString)"]
        let text = mealText(e, key: mealKey)
        if !text.isEmpty { lines.append(text) }
        if let ai = e.ai?.meals.first(where: { $0.label.lowercased().contains(mealKey) }) {
            lines.append(String(format: "%.0f kcal · P%.0fg C%.0fg F%.0fg",
                                ai.calories ?? 0, ai.protein ?? 0, ai.carbs ?? 0, ai.fat ?? 0))
        }
        return lines.joined(separator: "\n")
    }

    /// Day-wise text export: each meal (with its AI estimate if matched), quick-logged items, and totals.
    func exportDayText(_ dateString: String) -> String {
        guard let e = entry(for: dateString), e.isMeaningful else { return "Nothing logged for \(dateString)." }
        var lines = ["Win the Day — \(dateString)", ""]
        for key in Self.mealKeys {
            let structured = e.foodEntries.filter { $0.mealKey == key }
            let text = mealText(e, key: key)
            guard !structured.isEmpty || !text.isEmpty else { continue }
            lines.append(mealLabel(key).uppercased())
            for f in structured {
                let qtyStr = f.qty == f.qty.rounded() ? "×\(Int(f.qty))" : String(format: "×%.2g", f.qty)
                lines.append("\(f.name) \(qtyStr) — \(Int(f.totalKcal)) kcal · P\(Int(f.totalProtein))g")
            }
            if !text.isEmpty { lines.append(text) }
            if let ai = e.ai?.meals.first(where: { $0.label.lowercased().contains(key) }) {
                lines.append(String(format: "%.0f kcal · P%.0fg C%.0fg F%.0fg",
                                    ai.calories ?? 0, ai.protein ?? 0, ai.carbs ?? 0, ai.fat ?? 0))
            }
            lines.append("")
        }
        if !e.logged.isEmpty {
            lines.append("QUICK-LOGGED")
            for item in e.logged {
                let qtyStr = item.qty > 1 ? " ×\(item.qty)" : ""
                lines.append("\(item.name)\(qtyStr) — \(Int(item.calories * Double(item.qty))) kcal")
            }
            lines.append("")
        }
        lines.append("TOTAL")
        lines.append(String(format: "%.0f kcal · %.0fg protein", Double(e.calories) ?? 0, Double(e.proteinG) ?? 0))
        if let es = e.eatingScore { lines.append("Eating score: \(es)/100") }
        return lines.joined(separator: "\n")
    }

    struct DayNutrition {
        var carbs = 0.0, fat = 0.0, fiber = 0.0
        var micros: [Micro] = []   // summed across logged items
    }

    /// Aggregate carbs/fat/fiber + micronutrients from today's quick-logged items.
    func loggedNutrition() -> DayNutrition {
        var n = DayNutrition()
        var byName: [String: (Double, String)] = [:]
        var order: [String] = []
        for item in draft.logged {
            let q = Double(max(1, item.qty))
            n.carbs += item.carbs * q; n.fat += item.fat * q; n.fiber += item.fiber * q
            for m in item.micros {
                if let existing = byName[m.name] {
                    byName[m.name] = (existing.0 + m.amount * q, existing.1)
                } else {
                    byName[m.name] = (m.amount * q, m.unit); order.append(m.name)
                }
            }
        }
        n.micros = order.map { Micro(name: $0, amount: (byName[$0]!.0 * 100).rounded() / 100, unit: byName[$0]!.1) }
        return n
    }

    /// Combined day nutrition from quick-logged items AND the AI meal estimate.
    func dayNutrients() -> DayNutrition {
        var carbs = 0.0, fat = 0.0, fiber = 0.0
        var byName: [String: (Double, String)] = [:]
        var order: [String] = []
        func add(_ ms: [Micro]) {
            for m in ms where m.amount > 0 {
                if let e = byName[m.name] { byName[m.name] = (e.0 + m.amount, e.1) }
                else { byName[m.name] = (m.amount, m.unit); order.append(m.name) }
            }
        }
        for item in draft.logged {
            let q = Double(max(1, item.qty))
            carbs += item.carbs * q; fat += item.fat * q; fiber += item.fiber * q
            add(item.micros.map { Micro(name: $0.name, amount: $0.amount * q, unit: $0.unit) })
        }
        // Structured food entries (A1).
        for e in draft.foodEntries {
            carbs += e.totalCarbs; fat += e.totalFat; fiber += e.totalFiber
            if e.totalSodium > 0 { add([Micro(name: "Sodium", amount: e.totalSodium, unit: "mg")]) }
            add(e.micros.map { Micro(name: $0.name, amount: $0.amount * e.qty, unit: $0.unit) })
        }
        if let t = draft.ai?.total {
            carbs += t.carbs ?? 0; fat += t.fat ?? 0; fiber += t.fiber ?? 0; add(t.micros ?? [])
        }
        var n = DayNutrition(); n.carbs = carbs; n.fat = fat; n.fiber = fiber
        n.micros = order.map { Micro(name: $0, amount: (byName[$0]!.0 * 100).rounded() / 100, unit: byName[$0]!.1) }
        return n
    }

    struct MicroProgress: Identifiable {
        let id = UUID()
        let name: String, unit: String
        let amount: Double, rda: Double, ratio: Double
        let limit: Bool
    }

    /// Today's tracked micronutrients with progress vs reference daily values.
    func microProgress() -> [MicroProgress] {
        let n = dayNutrients()
        var list = n.micros
        if n.fiber > 0 { list.insert(Micro(name: "Fiber", amount: n.fiber, unit: "g"), at: 0) }
        var out: [MicroProgress] = []
        for m in list {
            guard let (rda, unit, limit) = NutritionRDA.target(for: m.name), rda > 0 else { continue }
            out.append(MicroProgress(name: m.name, unit: m.unit.isEmpty ? unit : m.unit,
                                     amount: m.amount, rda: rda, ratio: min(1.5, m.amount / rda), limit: limit))
        }
        return out
    }

    // MARK: - Eating score

    /// Compute the Eating score for `entry` from its own logged nutrition + activity + targets.
    /// Pure/sync (no HealthKit calls) — every input already lives on the entry/targets, so this
    /// can run inline in `commit()` on every edit.
    func eatingScoreResult(for entry: Entry) -> EatingScorer.Result {
        let isDraft = entry.date == draft.date
        let n = isDraft ? dayNutrients() : Self.nutrients(of: entry)
        let microRatios = (isDraft ? microProgress() : Self.microProgress(of: entry, nutrients: n)).map { min(1.5, $0.ratio) }
        let bedRef = entry.sleep?.bedEpoch ?? (entry.date == draft.date ? (sleepPlanTonight?.recommendedBedEpoch ?? 0) : 0)
        let inputs = EatingScorer.Inputs(
            calories: Double(entry.calories) ?? 0, proteinG: Double(entry.proteinG) ?? 0,
            carbsG: n.carbs, fatG: n.fat, microRatios: microRatios,
            weightKg: Double(entry.weight) ?? 0, heightCm: targets.heightCm, ageYears: targets.ageYears,
            sexMale: targets.sexMale, activeKcal: entry.activeKcal, goal: targets.goal,
            proteinTargetG: targets.protein, dinnerEpoch: entry.mealTimes["dinner"] ?? 0, referenceBedEpoch: bedRef)
        return EatingScorer.compute(inputs)
    }

    /// `dayNutrients()`/`microProgress()` read `draft` implicitly; these mirror them for an arbitrary
    /// (typically past, already-saved) entry so the weekly projection can score days that aren't the draft.
    private static func nutrients(of e: Entry) -> DayNutrition {
        var carbs = 0.0, fat = 0.0, fiber = 0.0
        for item in e.logged {
            let q = Double(max(1, item.qty))
            carbs += item.carbs * q; fat += item.fat * q; fiber += item.fiber * q
        }
        if let t = e.ai?.total { carbs += t.carbs ?? 0; fat += t.fat ?? 0; fiber += t.fiber ?? 0 }
        var n = DayNutrition(); n.carbs = carbs; n.fat = fat; n.fiber = fiber
        return n
    }
    private static func microProgress(of e: Entry, nutrients n: DayNutrition) -> [MicroProgress] {
        var byName: [String: (Double, String)] = [:]
        var order: [String] = []
        func add(_ ms: [Micro]) {
            for m in ms where m.amount > 0 {
                if let x = byName[m.name] { byName[m.name] = (x.0 + m.amount, x.1) } else { byName[m.name] = (m.amount, m.unit); order.append(m.name) }
            }
        }
        for item in e.logged { let q = Double(max(1, item.qty)); add(item.micros.map { Micro(name: $0.name, amount: $0.amount * q, unit: $0.unit) }) }
        add(e.ai?.total.micros ?? [])
        var list = order.map { Micro(name: $0, amount: byName[$0]!.0, unit: byName[$0]!.1) }
        if n.fiber > 0 { list.insert(Micro(name: "Fiber", amount: n.fiber, unit: "g"), at: 0) }
        var out: [MicroProgress] = []
        for m in list {
            guard let (rda, unit, limit) = NutritionRDA.target(for: m.name), rda > 0 else { continue }
            out.append(MicroProgress(name: m.name, unit: m.unit.isEmpty ? unit : m.unit, amount: m.amount, rda: rda, ratio: min(1.5, m.amount / rda), limit: limit))
        }
        return out
    }

    struct WeeklyEnergyBalance {
        var daysScored = 0
        var netKcalWeek = 0.0
        var projectedKg = 0.0
        var aggressive = false
        var avgEatingScore: Double?
        var smoothedWeightKg: Double?
    }

    /// Net calorie balance over the last 7 logged days → projected weekly weight change (7700 kcal/kg),
    /// flagged if the rate or any single day's deficit looks aggressive. Weight is a 7-day rolling mean.
    func weeklyEnergyBalance() -> WeeklyEnergyBalance {
        let cal = Calendar.current
        let dates = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: Date()).map(Self.dateString) }
        let entries = dates.compactMap { $0 == draft.date ? draft : data.entries[$0] }
        var bal = WeeklyEnergyBalance()
        var netSum = 0.0, scoredDays = 0, aggressiveDay = false
        var scores: [Double] = []
        for e in entries {
            let r = eatingScoreResult(for: e)
            if r.available { scores.append(Double(r.score)) }
            guard r.tdee > 0, Double(e.calories) ?? 0 > 0 else { continue }
            netSum += r.netKcal
            scoredDays += 1
            if r.netKcal < -500 { aggressiveDay = true }
        }
        bal.daysScored = scoredDays
        bal.netKcalWeek = netSum
        bal.projectedKg = netSum / 7700
        bal.avgEatingScore = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        let weights = entries.compactMap { Double($0.weight) }.filter { $0 > 0 }
        bal.smoothedWeightKg = weights.isEmpty ? nil : weights.reduce(0, +) / Double(weights.count)
        if let w = bal.smoothedWeightKg, w > 0, abs(bal.projectedKg) / w > 0.01 { aggressiveDay = true }
        bal.aggressive = aggressiveDay
        return bal
    }

    private func adjust(_ field: String, by delta: Double) -> String {
        let base = Double(field) ?? 0
        let v = max(0, (base + delta).rounded())
        return v == 0 ? "" : String(Int(v))
    }

    // MARK: - Prayers (tick off after praying)

    /// Toggle a prayer for today. `times`/`nextFajr` (from `PrayerManager`) let us classify
    /// prompt/on-time/later/qadha at the moment of marking; pass nil to mark untimed (`.unknown`).
    func togglePrayer(_ name: PrayerTimes.Name, times: PrayerTimes? = nil, nextFajr: Date? = nil) {
        guard name.isPrayer else { return }
        let key = name.rawValue
        mutate { d in
            if d.prayers.isOn(key) {
                d.prayers.setOn(key, false)
                if name == .fajr { d.nn.fajr = false }
            } else {
                let now = Date()
                let band: PrayerBand = times.map { PrayerClassifier.classify(name, markedAt: now, today: $0, nextFajr: nextFajr) } ?? .unknown
                d.prayers.setOn(key, true, at: now.timeIntervalSince1970, band: band)
                if name == .fajr { d.nn.fajr = true }
            }
        }
    }

    func isPrayed(_ name: PrayerTimes.Name) -> Bool { draft.prayers.isOn(name.rawValue) }
    func prayerBand(_ name: PrayerTimes.Name) -> PrayerBand { draft.prayers.band(name.rawValue) }

    // MARK: - Photos

    func addPhoto(_ image: UIImage) {
        guard let name = PhotoStore.save(image) else { return }
        mutate { $0.photos.append(name) }
    }

    func removePhoto(_ name: String) {
        PhotoStore.delete(name)
        mutate { $0.photos.removeAll { $0 == name } }
    }

    // MARK: - Smart-scale weight auto-fill

    /// Mirror today's steps & active energy into the entry so auto-linked habits can use them.
    func autofillActivity(steps: Double, activeKcal: Double) {
        guard isToday else { return }
        var changed = false
        if steps > 0 && (Double(draft.steps) ?? 0) < steps { changed = true }
        if activeKcal > 0 && draft.activeKcal < activeKcal { changed = true }
        guard changed else { return }
        mutate { e in
            if steps > 0 { e.steps = String(Int(steps)) }
            if activeKcal > 0 { e.activeKcal = activeKcal }
        }
    }

    /// Pull the day's "longest jog" straight from Apple Fitness — the longest run/walk workout's
    /// duration — so the user never types it. Only fills up (never overwrites a larger manual value).
    func autofillJog(from workouts: [HealthWorkout]) {
        guard isToday else { return }
        let longest = workouts.filter { $0.isRunWalk }.map { $0.durationMin }.max() ?? 0
        guard longest >= 1, longest > (Double(draft.run) ?? 0) else { return }
        mutate { $0.run = String(Int(longest.rounded())) }
    }

    /// If the day has no manual weight yet but Health has a body-mass sample, fill it in.
    func autofillWeight(_ kg: Double?) {
        guard isToday, let kg, kg > 0 else { return }
        let current = draft.weight.trimmingCharacters(in: .whitespaces)
        if current.isEmpty || draft.weightFromHealth {
            mutate { d in d.weight = String(format: "%.1f", kg); d.weightFromHealth = true }
        }
    }

    // MARK: - Hydration

    func addWater(_ ml: Int) {
        mutate { $0.waterMl = max(0, $0.waterMl + ml) }
    }

    var waterMl: Int { draft.waterMl }

    // MARK: - Time-of-day meal nudge

    /// Which meal to nudge logging right now, if it's empty.
    var mealNudge: (key: String, label: String)? {
        let h = Calendar.current.component(.hour, from: Date())
        let target: (String, String)?
        switch h {
        case 5..<11: target = ("breakfast", "breakfast")
        case 11..<12: target = ("snacks", "a morning snack")
        case 12..<16: target = ("lunch", "lunch")
        case 16..<19: target = ("snacks", "an evening snack")
        case 19..<24: target = ("dinner", "dinner")
        default: target = nil
        }
        guard let (key, label) = target else { return nil }
        let val: String
        switch key {
        case "breakfast": val = draft.meals.breakfast
        case "snacks": val = draft.meals.snacks
        case "lunch": val = draft.meals.lunch
        case "dinner": val = draft.meals.dinner
        default: val = ""
        }
        return val.trimmingCharacters(in: .whitespaces).isEmpty ? (key, label) : nil
    }

    // MARK: - InBody & lab imports

    func importBodyComp(text: String?, imageBase64: String?, health: HealthManager) async throws -> BodyComp {
        var comp = try await estimator.parseBodyComp(text: text, imageBase64: imageBase64, settings: settings)
        comp.date = date
        data.bodyComps.append(comp)
        persistData()
        // Mirror the weight into today's log + Health.
        if isToday, let w = comp.weight { mutate { d in d.weight = String(format: "%.1f", w) } }
        // If the prize is still visceral fat, keep its current value fresh from the report.
        if let v = comp.visceralFat, targets.prizeName.lowercased().contains("visceral") {
            updateTargets { $0.prizeCurrent = v }
        }
        health.writeBodyComp(comp, settings: settings)
        return comp
    }

    func importLabs(text: String?, imageBase64: String?, health: HealthManager) async throws -> LabRecord {
        let parsed = try await estimator.parseLabs(text: text, imageBase64: imageBase64, settings: settings)
        var items = parsed.items
        let writtenNames = health.writeLabs(items, settings: settings)
        for i in items.indices where writtenNames.contains(items[i].name) { items[i].written = true }
        let record = LabRecord(date: date, title: parsed.title, items: items)
        data.labs.insert(record, at: 0)
        persistData()
        return record
    }

    func addBaselineBodyComp(weight: Double?, visceralFat: Double?, health: HealthManager) {
        var comp = BodyComp(date: date)
        comp.weight = weight
        comp.visceralFat = visceralFat
        data.bodyComps.append(comp)
        persistData()
        health.writeBodyComp(comp, settings: settings)
    }

    var latestVisceralFat: Double? {
        data.bodyComps.sorted { $0.date < $1.date }.last { $0.visceralFat != nil }?.visceralFat
    }

    // MARK: - Readiness & sleep score

    @Published var readinessFactors: [ReadinessFactor] = []
    /// What Readiness would have been on sensor data alone, when today's check-in moved it. 0 = no adjustment.
    @Published var readinessSensorOnly: Int = 0
    @Published var sleepPlanTonight: SleepPlanner.Plan?
    var readinessToday: Int { draft.readiness }

    /// Store the viewed day's self-report check-in. Caller re-runs `computeReadiness` so the ring moves now.
    func updateCheckIn(_ c: DayCheckIn) {
        mutate { $0.checkIn = c }
    }

    /// Last `days` calendar days' Sleep/Readiness/Active scores (oldest→newest, zero/uncomputed dropped)
    /// for the sleep module's mini trend graph.
    func recentScores(days: Int = 14) -> (readiness: [Double], sleep: [Double], active: [Double]) {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date())) else { return ([], [], []) }
        let startStr = Self.dateString(start)
        let entries = sortedEntries().filter { $0.date >= startStr }
        return (entries.compactMap { $0.readiness > 0 ? Double($0.readiness) : nil },
                entries.compactMap { $0.sleepScore > 0 ? Double($0.sleepScore) : nil },
                entries.compactMap { $0.activeScore.map(Double.init) })
    }

    /// Compute the readiness + sleep sub-score for `dateString` from HealthKit + entry data.
    func computeReadiness(for dateString: String, health: HealthManager) async {
        let day = Self.parse(dateString)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: day)) ?? Date()
        let sleep = await health.fetchSleepDetail(nightEnding: day)
        guard let sleep else {   // nothing to score
            if dateString == draft.date { mutate { $0.sleep = nil; $0.readiness = 0; $0.sleepScore = 0; $0.activeScore = nil } }
            readinessFactors = []
            readinessSensorOnly = 0
            return
        }
        async let hrvMedian = health.fetchHRVOvernightMedian(nightEnding: day)
        async let rhr = health.fetchRestingHR(asOf: endOfDay)
        async let resp = health.fetchRespiratoryRateOvernightMedian(nightEnding: day)
        async let hrvStats = health.hrvBaselineStats()
        async let rhrStats = health.rhrBaselineStats()
        async let respStats = health.respBaselineStats()
        async let sampleNights = health.hrvSampleNights()
        let (hrvV, rhrV, respV, hrvB, rhrB, respB, nights) =
            await (hrvMedian, rhr, resp, hrvStats, rhrStats, respStats, sampleNights)

        // Prior-day load (drives strain S), typical load & sleep-need baseline from local history.
        let prevDate = Self.dateString(Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day)
        let prior = data.entries[prevDate]
        let priorKcal = prior?.activeKcal ?? 0
        let recentKcals = data.entries.values.map { $0.activeKcal }.filter { $0 > 0 }
        let typicalKcal = recentKcals.isEmpty ? 0 : recentKcals.reduce(0, +) / Double(recentKcals.count)
        let recentAsleepMin = data.entries.values.compactMap { $0.sleep?.asleepMin }.filter { $0 > 0 }.sorted()
        let sleepNeedBaseline = recentAsleepMin.isEmpty ? 0 : recentAsleepMin[recentAsleepMin.count / 2]

        // Capped 3-night sleep debt vs each of those nights' own recorded duration (proxy for "need").
        var debt = 0.0
        for offset in 1...3 {
            let d = Self.dateString(Calendar.current.date(byAdding: .day, value: -offset, to: day) ?? day)
            if let asleep = data.entries[d]?.sleep?.asleepMin, asleep > 0 {
                debt += max(0, (sleepNeedBaseline > 0 ? sleepNeedBaseline : 480) - asleep)
            }
        }

        // Up to the last 4 nights' mid-sleep times (incl. tonight) for the Consistency sub-score.
        var midSleeps: [Double] = []
        for offset in 0...3 {
            let d = Self.dateString(Calendar.current.date(byAdding: .day, value: -offset, to: day) ?? day)
            if let m = data.entries[d]?.sleep?.midSleepEpoch, m > 0 { midSleeps.append(m) }
        }
        if sleep.midSleepEpoch > 0 && !midSleeps.contains(sleep.midSleepEpoch) { midSleeps.append(sleep.midSleepEpoch) }

        let baselines = ScoreEngine.Baselines(
            lnHrvMean: hrvB?.mean ?? 0, lnHrvSD: hrvB?.sd ?? 0,
            rhrMean: rhrB?.mean ?? 0, rhrSD: rhrB?.sd ?? 0,
            respMean: respB?.mean ?? 0, respSD: respB?.sd ?? 0,
            sleepNeedBaselineMin: sleepNeedBaseline, typicalActiveKcal: typicalKcal, sampleNights: nights)

        let checkIn: DayCheckIn = dateString == draft.date ? draft.checkIn : (data.entries[dateString]?.checkIn ?? DayCheckIn())
        let inputs = ScoreEngine.Inputs(
            sleep: sleep, hrvOvernightMedian: hrvV ?? 0, restingHR: rhrV ?? 0, respiratoryRate: respV ?? 0,
            priorDaySleepDebtMin: debt, recentMidSleepEpochs: midSleeps, activeKcal: priorKcal,
            checkIn: checkIn, baselines: baselines)
        let r = ScoreEngine.compute(inputs)
        readinessFactors = r.factors

        // Transparency: what the same inputs score with the self-report removed. The engine is pure
        // and cheap, so running it twice is cheaper than threading a second number through it.
        if checkIn != DayCheckIn() {
            var sensorOnly = inputs
            sensorOnly.checkIn = DayCheckIn()
            let base = ScoreEngine.compute(sensorOnly).readiness
            readinessSensorOnly = base != r.readiness ? base : 0
        } else {
            readinessSensorOnly = 0
        }

        if dateString == draft.date {
            let planS = ScoreEngine.strain(activeKcal: priorKcal, typicalActiveKcal: typicalKcal)
            let recentWakeEpochs = sortedEntries().suffix(14).compactMap { $0.sleep?.wakeEpoch }.filter { $0 > 0 }
            sleepPlanTonight = SleepPlanner.plan(baselineNeedMin: sleepNeedBaseline, strainS: planS,
                                                 debtMin: debt, recentWakeEpochs: recentWakeEpochs)
        }

        if dateString == draft.date {
            mutate { $0.sleep = sleep; $0.readiness = r.readiness; $0.sleepScore = r.sleepScore
                     $0.activeScore = r.activeAvailable ? r.activeScore : nil }
        } else if var e = data.entries[dateString] {
            e.sleep = sleep; e.readiness = r.readiness; e.sleepScore = r.sleepScore
            e.activeScore = r.activeAvailable ? r.activeScore : nil
            data.entries[dateString] = e
            persistData()
        }
    }

    /// Readiness series (last N logged days, oldest→newest) for Trends.
    func readinessSeries() -> [Double] {
        sortedEntries().compactMap { $0.readiness > 0 ? Double($0.readiness) : nil }
    }

    // MARK: - Health notes & index

    func addHealthNote(_ n: HealthNote) {
        var note = n
        if note.dateEpoch == 0 { note.dateEpoch = Date().timeIntervalSince1970 }
        data.healthNotes.append(note); persistData()
    }
    func updateHealthNote(_ n: HealthNote) {
        if let i = data.healthNotes.firstIndex(where: { $0.id == n.id }) { data.healthNotes[i] = n; persistData() }
    }
    func deleteHealthNote(_ id: String) { data.healthNotes.removeAll { $0.id == id }; persistData() }

    /// A compact health profile fed to the AI (latest body comp, recent labs, user notes).
    func healthIndex() -> String {
        var parts: [String] = []
        if let bc = data.bodyComps.sorted(by: { $0.date < $1.date }).last {
            var f: [String] = []
            if let w = bc.weight { f.append("weight \(fmtT(w))kg") }
            if let bf = bc.bodyFat { f.append("body fat \(fmtT(bf))%") }
            if let lm = bc.leanMass { f.append("lean \(fmtT(lm))kg") }
            if let v = bc.visceralFat { f.append("visceral \(fmtT(v))") }
            if !f.isEmpty { parts.append("Body comp (\(bc.date)): " + f.joined(separator: ", ")) }
        }
        if let lab = data.labs.sorted(by: { $0.date < $1.date }).last, !lab.items.isEmpty {
            let items = lab.items.prefix(12).map { "\($0.name) \(fmtT($0.value))\($0.unit)" }.joined(separator: ", ")
            parts.append("Labs — \(lab.title) (\(lab.date)): \(items)")
        }
        if !data.healthNotes.isEmpty {
            let grouped = Dictionary(grouping: data.healthNotes, by: { $0.category })
            for cat in ["condition", "medication", "injury", "goal", "note"] {
                guard let notes = grouped[cat], !notes.isEmpty else { continue }
                let line = notes.map { n in n.title.isEmpty ? n.text : (n.text.isEmpty ? n.title : "\(n.title): \(n.text)") }
                    .joined(separator: "; ")
                parts.append("\(HealthNote.label(cat))s: \(line)")
            }
        }
        return parts.isEmpty ? "" : parts.joined(separator: "\n")
    }

    // MARK: - Weekly review

    @Published var weeklyReview = UserDefaults.standard.string(forKey: "weekly_review") ?? ""
    @Published var weeklyReviewLoading = false
    private var weeklyReviewWeek = UserDefaults.standard.string(forKey: "weekly_review_week") ?? ""

    struct WeeklyStats {
        var daysLogged = 0
        var avgScore = 0.0
        var perfectDays = 0
        var weightChange: Double?
        var avgProtein: Double?
        var prayersDone = 0
        var prayersPossible = 0
    }

    func weeklyStats() -> WeeklyStats {
        let cal = Calendar.current
        let dates = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: Date()).map(Self.dateString) }
        let es = dates.compactMap { data.entries[$0] }.sorted { $0.date < $1.date }
        var st = WeeklyStats()
        st.daysLogged = es.count
        let scores = es.map { Double(score($0)) }
        st.avgScore = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        st.perfectDays = scores.filter { $0 == 5 }.count
        let proteins = es.compactMap { Double($0.proteinG) }.filter { $0 > 0 }
        st.avgProtein = proteins.isEmpty ? nil : proteins.reduce(0, +) / Double(proteins.count)
        let weights = es.compactMap { Double($0.weight) }.filter { $0 > 0 }
        if let first = weights.first, let last = weights.last, weights.count > 1 { st.weightChange = last - first }
        st.prayersDone = es.reduce(0) { $0 + $1.prayers.count }
        st.prayersPossible = es.count * 5
        return st
    }

    private var currentWeekID: String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }

    func refreshWeeklyReview(force: Bool = false) async {
        if !force && weeklyReviewWeek == currentWeekID && !weeklyReview.isEmpty { return }
        weeklyReviewLoading = true
        let st = weeklyStats()
        let wChange = st.weightChange.map { String(format: "%+.1f kg", $0) } ?? "n/a"
        let prot = st.avgProtein.map { "\(Int($0))g" } ?? "n/a"
        let health = healthIndex()
        let prompt = """
        You are a warm, sharp personal coach. Write this week's review. The user's priority "prize" metric is \(targets.prizeName) (\(fmtT(targets.prizeCurrent))\(targets.prizeUnit) → \(targets.prizeLowerIsBetter ? "≤" : "≥")\(fmtT(targets.prizeTarget))\(targets.prizeUnit)), with a protein target of ~\(Int(targets.protein))g/day.

        This week: logged \(st.daysLogged)/7 days, average score \(String(format: "%.1f", st.avgScore))/5, \(st.perfectDays) perfect days, weight change \(wChange), average protein \(prot), prayers \(st.prayersDone)/\(st.prayersPossible).
        \(health.isEmpty ? "" : "\nHealth profile:\n\(health)\n")
        Write 2–3 warm sentences on how the week went, then ONE specific focus for next week. Plain text, no headings or bullet points, under 60 words.
        """
        do {
            let text = try await estimator.suggest(prompt: prompt, settings: settings)
            if !text.isEmpty {
                weeklyReview = text
                weeklyReviewWeek = currentWeekID
                UserDefaults.standard.set(text, forKey: "weekly_review")
                UserDefaults.standard.set(currentWeekID, forKey: "weekly_review_week")
            }
        } catch {}
        weeklyReviewLoading = false
    }

    private func fmtT(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d) }

    /// A Sunday-evening reminder to check the weekly review.
    func scheduleWeeklyReviewNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-review"])
        var comps = DateComponents()
        comps.weekday = 1   // Sunday
        comps.hour = 19
        let content = UNMutableNotificationContent()
        content.title = "Your week in review 📊"
        content.body = "See how the week went and set next week\u{2019}s focus."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "weekly-review", content: content, trigger: trigger))
    }

    // MARK: - Daily suggestion

    private var timeSlot: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "morning"
        case 11..<15: return "midday"
        case 15..<19: return "afternoon"
        case 19..<23: return "evening"
        default: return "latenight"
        }
    }

    func refreshSuggestion(force: Bool = false) async {
        let slot = date + "/" + timeSlot
        if !force && slot == suggestionSlot && !suggestion.isEmpty { return }
        suggestionLoading = true
        let prompt = suggestionPrompt()
        do {
            let text = try await estimator.suggest(prompt: prompt, settings: settings)
            if !text.isEmpty { suggestion = text; suggestionSlot = slot }
        } catch {
            // Leave any previous suggestion in place; silent on failure.
        }
        suggestionLoading = false
    }

    // MARK: - Weather module tips rotator

    private let dayTipsKey = "day_tips_v1"
    private let dayTipsSlotKey = "day_tips_slot_v1"

    /// Refreshes the tips rotator — at most one AI call per (date, time-slot); loads the cached
    /// slot from a previous launch first so the panel is never empty on appear.
    func refreshDayTips(force: Bool = false) async {
        let slot = date + "/" + timeSlot
        if dayTips.isEmpty, dayTipsSlot.isEmpty {
            let ud = UserDefaults.standard
            if ud.string(forKey: dayTipsSlotKey) == slot, let saved = ud.stringArray(forKey: dayTipsKey), !saved.isEmpty {
                dayTips = saved; dayTipsSlot = slot
            }
        }
        if !force && slot == dayTipsSlot && !dayTips.isEmpty { return }
        dayTipsLoading = true
        do {
            let tips = try await estimator.suggestTips(prompt: dayTipsPrompt(), settings: settings)
            if !tips.isEmpty {
                dayTips = tips; dayTipsSlot = slot
                UserDefaults.standard.set(tips, forKey: dayTipsKey)
                UserDefaults.standard.set(slot, forKey: dayTipsSlotKey)
            } else if dayTips.isEmpty {
                dayTips = fallbackDayTips()
            }
        } catch {
            if dayTips.isEmpty { dayTips = fallbackDayTips() }
        }
        dayTipsLoading = false
    }

    private func dayTipsPrompt() -> String {
        let d = draft
        var facts = ["Time of day: \(timeSlot)."]
        if !weatherContext.isEmpty {
            facts.append("Weather: \(weatherContext.split(separator: ";").first.map(String.init) ?? weatherContext).")
        }
        if d.sleep != nil { facts.append("Readiness \(d.readiness)/100, sleep score \(d.sleepScore)/100.") }
        if let es = d.eatingScore { facts.append("Eating score \(es)/100.") }
        if !d.calories.isEmpty {
            facts.append("Logged \(d.calories) kcal, \(d.proteinG.isEmpty ? "0" : d.proteinG)g protein so far, target \(Int(targets.calories)) kcal / \(Int(targets.protein))g protein.")
        }
        if let plan = sleepPlanTonight {
            facts.append(String(format: "Aim for %.1fh sleep tonight.", plan.needHours))
        }
        if DayStatus.isProtected(d.status) { facts.append("Day flagged: \(DayStatus.label(d.status)) — keep it gentle.") }

        return """
        You are a sharp, encouraging personal coach inside "Win the Day". Give 4 short, varied, specific tips for right now, grounded ONLY in these real facts (never invent numbers):
        \(facts.joined(separator: " "))

        Mix categories across the 4 tips: one about food/hydration, one about movement/rest, one about weather or the day's plan, one about readiness/sleep. Each tip \u{2264}18 words, no greeting, no numbering, plain sentences.
        Respond with ONLY this JSON: {"tips":["...","...","...","..."]}
        """
    }

    /// Deterministic local tips so the rotator is never empty — used when the AI call fails or
    /// returns nothing usable (e.g. Apple Intelligence / a non-JSON local model).
    private func fallbackDayTips() -> [String] {
        var tips: [String] = []
        switch timeSlot {
        case "morning": tips.append("Start with a glass of water before your first meal.")
        case "midday": tips.append("A short walk after lunch helps digestion and afternoon focus.")
        case "afternoon": tips.append("A two-minute stretch resets focus better than more caffeine.")
        case "evening": tips.append("Wind screens down an hour before bed for better sleep.")
        default: tips.append("Keep lights low if you're up late — it protects tomorrow's sleep.")
        }
        if draft.readiness > 0 && draft.readiness < 45 {
            tips.append("Readiness is low today — an easier session beats pushing through.")
        } else {
            tips.append("Stay consistent — small daily wins compound.")
        }
        if let es = draft.eatingScore, es < 60 {
            tips.append("A protein-forward next meal will help your eating score.")
        } else {
            tips.append("Balance your next plate with some colour — veggies count.")
        }
        tips.append(weatherContext.isEmpty ? "Check the weather tile for today's outdoor advice."
                    : "Check today's outdoor window before you plan a walk or run.")
        return tips
    }

    private func suggestionPrompt() -> String {
        let d = draft
        let sc = score(d)
        let nnDone = Content.nnDefs.filter { key, _ in
            switch key {
            case "fajr": return d.nn.fajr
            case "protein": return proteinSatisfied(d)
            case "moved": return d.nn.moved
            case "phone": return d.nn.phone
            case "side": return d.nn.side
            default: return false
            }
        }.map { $0.label }
        let pending = Content.nnDefs.map { $0.label }.filter { !nnDone.contains($0) }
        return """
        You are a warm, no-nonsense health coach inside a daily tracker app called "Win the Day". The user is on a fat-loss program: priority is dropping visceral fat, ~120g protein/day, 2000 kcal target, gut-friendly Kerala/South-Indian eating, recovering a neck/shoulder issue (no heavy overhead work).

        Time of day: \(timeSlot).
        Today so far — score \(sc)/5, calories logged: \(d.calories.isEmpty ? "none" : d.calories), protein: \(d.proteinG.isEmpty ? "none" : d.proteinG)g.
        Done: \(nnDone.isEmpty ? "nothing yet" : nnDone.joined(separator: ", ")).
        Still open: \(pending.isEmpty ? "all done" : pending.joined(separator: ", ")).\(DayStatus.isProtected(d.status) ? "\n        Day flagged: \(DayStatus.label(d.status)) — keep it gentle." : "")\(weatherContext.isEmpty ? "" : "\n        Weather today: \(weatherContext.split(separator: ";").first.map(String.init) ?? weatherContext)")

        Give ONE specific, encouraging suggestion for right now (max 22 words). No greeting, no preamble, no quotes — just the suggestion sentence.
        """
    }

    // MARK: - Coach chat (multiple threads + tool calling)

    /// Passthrough to the active thread's messages — kept so `CoachChatView` barely changed.
    var chatMessages: [ChatMessage] {
        threads.first { $0.id == activeThreadID }?.messages ?? []
    }
    var activeThread: CoachThread? { threads.first { $0.id == activeThreadID } }
    /// Threads newest-first, for the chat list.
    var threadsOrdered: [CoachThread] { threads.sorted { $0.updatedEpoch > $1.updatedEpoch } }

    private func loadThreads() {
        if let raw = UserDefaults.standard.data(forKey: threadsKey),
           let saved = try? JSONDecoder().decode([CoachThread].self, from: raw), !saved.isEmpty {
            threads = saved
            activeThreadID = UserDefaults.standard.string(forKey: activeThreadKey) ?? saved[0].id
            if !threads.contains(where: { $0.id == activeThreadID }) { activeThreadID = threadsOrdered.first?.id ?? "" }
            return
        }
        // One-time migration: fold the old single transcript into thread #1.
        if let raw = UserDefaults.standard.data(forKey: legacyChatKey),
           let msgs = try? JSONDecoder().decode([ChatMessage].self, from: raw), !msgs.isEmpty {
            var t = CoachThread()
            t.title = msgs.first { $0.isUser }?.text.prefix(40).description ?? "Earlier chat"
            t.messages = msgs
            threads = [t]
            activeThreadID = t.id
            persistThreads()
            UserDefaults.standard.removeObject(forKey: legacyChatKey)
        }
    }

    private func persistThreads() {
        if let raw = try? JSONEncoder().encode(threads) {
            UserDefaults.standard.set(raw, forKey: threadsKey)
        }
        UserDefaults.standard.set(activeThreadID, forKey: activeThreadKey)
    }

    /// Create a new thread, make it active, and return its id.
    @discardableResult
    func newThread() -> String {
        let t = CoachThread()
        threads.append(t)
        activeThreadID = t.id
        persistThreads()
        return t.id
    }
    func switchThread(_ id: String) {
        guard threads.contains(where: { $0.id == id }) else { return }
        activeThreadID = id
        persistThreads()
    }
    func renameThread(_ id: String, title: String) {
        guard let i = threads.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        threads[i].title = trimmed.isEmpty ? "New chat" : String(trimmed.prefix(60))
        persistThreads()
    }
    func deleteThread(_ id: String) {
        threads.removeAll { $0.id == id }
        if activeThreadID == id { activeThreadID = threadsOrdered.first?.id ?? "" }
        persistThreads()
    }
    /// Clear the active thread's messages without deleting the thread itself.
    func clearChat() {
        guard let i = threads.firstIndex(where: { $0.id == activeThreadID }) else { return }
        threads[i].messages = []
        threads[i].updatedEpoch = Date().timeIntervalSince1970
        persistThreads()
    }

    func sendChat(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chatLoading else { return }
        if activeThreadID.isEmpty || !threads.contains(where: { $0.id == activeThreadID }) { newThread() }
        guard let i = threads.firstIndex(where: { $0.id == activeThreadID }) else { return }

        threads[i].messages.append(ChatMessage(role: "user", text: trimmed))
        if threads[i].title == "New chat" { threads[i].title = String(trimmed.prefix(40)) }
        threads[i].updatedEpoch = Date().timeIntervalSince1970
        persistThreads()
        chatLoading = true

        // Send the last ~16 turns; the model pulls anything else it needs via tools.
        let history = Array(threads[i].messages.suffix(16))
        let leanSystem = """
        You are "Coach", a warm, sharp, concise personal coach living inside the user's daily tracker app "Win the Day". Answer in 1–4 short sentences unless asked for detail. Call the available tools to read the user's real data before answering anything about their day, week, meals, prayers, readiness or targets — never invent numbers. You can give meal ideas, training/recovery tips, study/focus advice and motivation. If asked something you can't know, say so briefly.
        """
        do {
            let reply = try await estimator.chatWithTools(system: leanSystem, history: history,
                                                           tools: CoachToolRegistry.all, store: self, settings: settings)
            let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            threads[i].messages.append(ChatMessage(role: "assistant",
                                                    text: clean.isEmpty ? "I didn\u{2019}t catch that — try rephrasing?" : clean))
        } catch {
            threads[i].messages.append(ChatMessage(role: "assistant",
                                                    text: "Couldn\u{2019}t reach the AI: \(error.localizedDescription)"))
        }
        threads[i].messages = Array(threads[i].messages.suffix(60))
        threads[i].updatedEpoch = Date().timeIntervalSince1970
        persistThreads()
        chatLoading = false
    }

    // MARK: - Coach tool executors (read-only; run synchronously — everything here is already local)

    private func toolDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return Self.dateString(Date()) }
        return raw
    }

    func toolGetDay(_ dateArg: String?) -> String {
        let d = toolDate(dateArg)
        guard let e = entry(for: d), e.isMeaningful else { return "No log for \(d)." }
        var lines = ["Day \(d) — score \(score(e))/\(activeHabits.count), status: \(DayStatus.label(e.status))"]
        lines.append("Calories: \(e.calories.isEmpty ? "none" : e.calories), protein: \(e.proteinG.isEmpty ? "none" : e.proteinG)g, water: \(e.waterMl)ml")
        lines.append("Meals — B:\(mealWithTime(e, "breakfast")) | L:\(mealWithTime(e, "lunch")) | D:\(mealWithTime(e, "dinner")) | S:\(mealWithTime(e, "snacks")) | Drinks:\(mealWithTime(e, "drinks"))")
        lines.append("Prayers: \(e.prayers.count)/5, study/focus: \(fmtT(e.studyHours))h")
        return lines.joined(separator: "\n")
    }

    func toolGetRecentDays(_ n: Int) -> String {
        let recent = data.entries.values.filter { $0.isMeaningful }.sorted { $0.date > $1.date }.prefix(n)
        guard !recent.isEmpty else { return "No recent logged days." }
        return recent.map { e in
            "\(e.date): score \(score(e))/\(activeHabits.count), \(e.calories.isEmpty ? "?" : e.calories) kcal, P\(e.proteinG.isEmpty ? "?" : e.proteinG)g, prayers \(e.prayers.count)/5, study \(fmtT(e.studyHours))h"
        }.joined(separator: "\n")
    }

    func toolGetWeekStats() -> String {
        let st = weeklyStats()
        let wChange = st.weightChange.map { String(format: "%+.1f kg", $0) } ?? "n/a"
        let prot = st.avgProtein.map { "\(Int($0))g" } ?? "n/a"
        return "This week: \(st.daysLogged)/7 days logged, avg score \(String(format: "%.1f", st.avgScore))/\(activeHabits.count), \(st.perfectDays) perfect days, weight change \(wChange), avg protein \(prot), prayers \(st.prayersDone)/\(st.prayersPossible)."
    }

    func toolGetReadiness(_ dateArg: String?) -> String {
        let d = toolDate(dateArg)
        guard let e = entry(for: d) else { return "No data for \(d)." }
        var lines = ["Readiness for \(d):"]
        lines.append("Sleep \(e.sleepScore)/100, Readiness \(e.readiness)/100" +
                     (e.activeScore.map { ", Active \($0)/100" } ?? ", Active: not computed") +
                     (e.eatingScore.map { ", Eating \($0)/100" } ?? ", Eating: not enough data"))
        if d == draft.date, !readinessFactors.isEmpty {
            lines.append("Factors: " + readinessFactors.prefix(5).map { "\($0.label) \($0.delta >= 0 ? "+" : "")\($0.delta)" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    func toolGetFoodLog(_ dateArg: String?) -> String { exportDayText(toolDate(dateArg)) }

    func toolGetPrayers(_ dateArg: String?) -> String {
        let d = toolDate(dateArg)
        guard let e = entry(for: d) else { return "No data for \(d)." }
        let names = ["fajr", "dhuhr", "asr", "maghrib", "isha"]
        let lines = names.map { "\($0.capitalized): \(e.prayers.band($0).label)" }
        return "Prayers \(d) (\(e.prayers.count)/5 marked):\n" + lines.joined(separator: "\n")
    }

    func toolGetHealthIndex() -> String {
        let h = healthIndex()
        return h.isEmpty ? "No health profile recorded yet." : h
    }

    func toolGetTargets() -> String {
        let prizeArrow = targets.prizeLowerIsBetter ? "≤" : "≥"
        return "Targets: \(Int(targets.calories)) kcal, \(Int(targets.protein))g protein, \(Int(targets.steps)) steps, \(fmtT(targets.studyHours))h study/focus. Priority metric \"\(targets.prizeName)\": \(fmtT(targets.prizeCurrent))\(targets.prizeUnit) \u{2192} \(prizeArrow)\(fmtT(targets.prizeTarget))\(targets.prizeUnit). Mode: \(targets.workMode == "work" ? "Work" : "Study")."
    }

    /// System preamble: who the user is, today's numbers, targets, prize, recent days.
    func coachContext() -> String {
        let d = draft
        let st = weeklyStats()
        let wChange = st.weightChange.map { String(format: "%+.1f kg", $0) } ?? "n/a"
        let prot = st.avgProtein.map { "\(Int($0))g" } ?? "n/a"
        let prizeArrow = targets.prizeLowerIsBetter ? "≤" : "≥"

        // Compact recent-day summary (last 5 logged days).
        let recent = data.entries.values
            .filter { $0.isMeaningful }
            .sorted { $0.date > $1.date }
            .prefix(5)
            .map { e -> String in
                "\(e.date): score \(score(e))/5, \(e.calories.isEmpty ? "?" : e.calories) kcal, " +
                "P\(e.proteinG.isEmpty ? "?" : e.proteinG)g, prayers \(e.prayers.count)/5, study \(fmtT(e.studyHours))h"
            }
            .joined(separator: "\n")

        let health = healthIndex()
        let healthSection = health.isEmpty ? "" : "\n\nHEALTH PROFILE\n\(health)"

        return """
        You are "Coach", a warm, sharp, concise personal coach living inside the user's daily tracker app "Win the Day". Answer in 1–4 short sentences unless asked for detail. Use the user's real data below, including the HEALTH PROFILE, to tailor advice (respect conditions, injuries, meds and goals). Be specific and practical; never invent numbers you weren't given. You can give meal ideas, training/recovery tips, study/focus advice and motivation. If asked something you can't know, say so briefly.

        USER CONFIG
        - Pillars/focus: \(targets.workMode == "work" ? "Work" : "Study") mode; prize metric "\(targets.prizeName)" \(fmtT(targets.prizeCurrent))\(targets.prizeUnit) → \(prizeArrow)\(fmtT(targets.prizeTarget))\(targets.prizeUnit).
        - Daily targets: ~\(Int(targets.protein))g protein, \(Int(targets.calories)) kcal, \(Int(targets.steps)) steps, \(fmtT(targets.studyHours))h study/focus.

        TODAY (\(d.date)) so far
        - Score \(score(d))/5, calories \(d.calories.isEmpty ? "none" : d.calories), protein \(d.proteinG.isEmpty ? "none" : d.proteinG)g, water \(d.waterMl)ml, prayers \(d.prayers.count)/5, study \(fmtT(d.studyHours))h.
        - Meals: B:\(mealWithTime(d, "breakfast")) | L:\(mealWithTime(d, "lunch")) | D:\(mealWithTime(d, "dinner")) | S:\(mealWithTime(d, "snacks"))

        THIS WEEK
        - \(st.daysLogged)/7 days logged, avg score \(String(format: "%.1f", st.avgScore))/5, \(st.perfectDays) perfect days, weight change \(wChange), avg protein \(prot), prayers \(st.prayersDone)/\(st.prayersPossible).

        RECENT DAYS
        \(recent.isEmpty ? "(no recent entries)" : recent)\(healthSection)
        """
    }

    // MARK: - Data export / import / reset

    /// Serialize a complete backup: every persisted UserDefaults blob plus the referenced photos.
    /// In-memory state is flushed first so the archive matches what's on screen.
    private func makeBackupData() -> Data? {
        persistData()
        persistSettings()
        var names: Set<String> = []
        for entry in data.entries.values { names.formUnion(entry.photos) }
        let archive = BackupService.makeArchive(photoNames: names)
        return try? JSONEncoder().encode(archive)
    }

    /// Build a complete backup and write it to a temp file for the share/export sheet.
    func exportJSON() -> URL? {
        guard let raw = makeBackupData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("win-the-day-backup-\(Self.dateString(Date())).json")
        try? raw.write(to: url)
        return url
    }

    // MARK: - Automatic local backup

    @Published var lastAutoBackup: Date? = UserDefaults.standard.object(forKey: "last_auto_backup") as? Date

    private var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// The visible-in-Files rolling backup the app refreshes whenever it goes to the background.
    var autoBackupURL: URL { documentsDir.appendingPathComponent("Win the Day - latest backup.json") }

    func writeAutoBackup() {
        guard let raw = makeBackupData() else { return }
        try? raw.write(to: autoBackupURL)
        let now = Date()
        UserDefaults.standard.set(now, forKey: "last_auto_backup")
        lastAutoBackup = now
    }

    // MARK: - Restore (two steps: preview, then commit)

    /// Parsed and validated, waiting on the user's confirmation. Nothing has been written yet.
    @Published var pendingRestore: BackupArchive?
    @Published var pendingSummary: BackupSummary?
    /// Set once a restore has landed — managers still hold their pre-restore state, so the UI asks
    /// for a relaunch rather than trying to re-init every one of them live.
    @Published var restoreNeedsRelaunch = false

    /// Read + validate a backup file and stage it for confirmation. Writes nothing.
    func prepareImport(from url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url) else {
            importMessage = BackupService.RestoreError.unreadable.localizedDescription
            return
        }
        do {
            let archive = try BackupService.parse(raw)
            importMessage = ""
            pendingSummary = BackupService.summary(archive)
            pendingRestore = archive
        } catch {
            importMessage = (error as? LocalizedError)?.errorDescription
                ?? BackupService.RestoreError.unreadable.localizedDescription
        }
    }

    func cancelPendingRestore() {
        pendingRestore = nil
        pendingSummary = nil
    }

    /// Commit the staged archive, then reload everything this store owns. Managers (prayer,
    /// hydration, fasting) keep their in-memory copies until the app is relaunched.
    func commitPendingRestore() {
        guard let archive = pendingRestore else { return }
        do {
            try BackupService.restore(archive)
        } catch {
            importMessage = (error as? LocalizedError)?.errorDescription
                ?? BackupService.RestoreError.unreadable.localizedDescription
            cancelPendingRestore()
            return
        }
        cancelPendingRestore()
        reloadFromDefaults()
        importMessage = "Restored \(data.entries.count) days."
        restoreNeedsRelaunch = true
    }

    /// Re-read every key this store caches in memory, after a restore replaced them on disk.
    private func reloadFromDefaults() {
        let d = UserDefaults.standard
        data = AppData(); settings = AppSettings(); targets = Targets()
        modules = ModulePrefs(); personal = Personalization()
        load()
        threads = []; activeThreadID = ""
        loadThreads()
        onboardingDone = d.bool(forKey: "onboarding_done_v1")
        focusQueue = d.stringArray(forKey: focusQueueKey) ?? []
        weekOutlook = d.string(forKey: "week_outlook") ?? ""
        weekOutlookWeek = d.string(forKey: "week_outlook_week") ?? ""
        weeklyReview = d.string(forKey: "weekly_review") ?? ""
        weeklyReviewWeek = d.string(forKey: "weekly_review_week") ?? ""
        dayTips = []; dayTipsSlot = ""
        draft = loadDraft(for: date)
        publishSnapshot()
    }

    func reset() {
        data = AppData()
        persistData()
        draft = Entry(date: date)
        importMessage = ""
    }

    // MARK: - Settings actions

    func setProvider(_ id: String) {
        let p = Providers.provider(id)
        updateSettings { $0.provider = id; $0.model = p.models.first?.id ?? "" }
    }
    func setModel(_ id: String) { updateSettings { $0.model = id } }
    func toggleHealthKit() { updateSettings { $0.healthkit.toggle() } }
}

private extension JSONEncoder {
    func encodeFormatted<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(value)
    }
}
