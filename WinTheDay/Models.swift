import Foundation

// MARK: - Entry model (one per calendar day, keyed yyyy-MM-dd)

struct Meals: Codable, Equatable {
    var breakfast = ""
    var snacks = ""
    var lunch = ""
    var dinner = ""
    var drinks = ""

    var all: [String] { [breakfast, snacks, lunch, dinner, drinks] }
    var hasAny: Bool { all.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
}

struct NonNegotiables: Codable, Equatable {
    var fajr = false
    var protein = false
    var moved = false
    var phone = false
    var side = false

    var anyTrue: Bool { fajr || protein || moved || phone || side }
}

struct AIMeal: Codable, Equatable, Identifiable {
    var label: String
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var note: String?
    var id: String { label }
}

struct AITotals: Codable, Equatable {
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var micros: [Micro]?
}

struct AIResult: Codable, Equatable {
    var meals: [AIMeal]
    var total: AITotals
}

struct Entry: Codable, Equatable, Identifiable {
    var date: String                 // yyyy-MM-dd
    var meals = Meals()
    var nn = NonNegotiables()
    var training = ""
    var run = ""
    var weight = ""
    var steps = ""
    var sms = ""                     // sleep / mood / stress
    var calories = ""
    var proteinG = ""
    var ai: AIResult?
    var logged: [LoggedItem] = []     // quick-logged catalog items applied to today's totals
    var photos: [String] = []         // filenames in Documents/photos
    var prayers = PrayerLog()
    var weightFromHealth = false      // weight was auto-filled from a smart-scale sample
    var waterMl = 0                   // hydration logged for the day
    var habitState: [String: Bool] = [:]   // manual-habit completion (habitID → done)
    var activeKcal = 0.0              // active energy for the day (from Health), for auto habits
    var studyHours = 0.0             // hours studied/worked
    var studySessions: [StudySession] = []
    var workouts: [Workout] = []     // structured gym/cardio sessions
    var mealTimes: [String: Double] = [:]   // meal key (breakfast/…) → epoch when eaten
    var sleep: SleepBreakdown?       // last night's sleep detail (from Health)
    var readiness: Int = 0           // 0–100 readiness score (cached)
    var sleepScore: Int = 0          // 0–100 sleep sub-score (cached)
    var status: String = "normal"    // normal | sick | travel | rest (protected days)

    var id: String { date }

    init(date: String) { self.date = date }

    /// Tolerant decoding: missing keys fall back to defaults so older saved data never fails to load
    /// (and adding new fields in future builds won't wipe existing entries).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        meals = (try? c.decode(Meals.self, forKey: .meals)) ?? Meals()
        nn = (try? c.decode(NonNegotiables.self, forKey: .nn)) ?? NonNegotiables()
        training = (try? c.decode(String.self, forKey: .training)) ?? ""
        run = (try? c.decode(String.self, forKey: .run)) ?? ""
        weight = (try? c.decode(String.self, forKey: .weight)) ?? ""
        steps = (try? c.decode(String.self, forKey: .steps)) ?? ""
        sms = (try? c.decode(String.self, forKey: .sms)) ?? ""
        calories = (try? c.decode(String.self, forKey: .calories)) ?? ""
        proteinG = (try? c.decode(String.self, forKey: .proteinG)) ?? ""
        ai = try? c.decodeIfPresent(AIResult.self, forKey: .ai)
        logged = (try? c.decode([LoggedItem].self, forKey: .logged)) ?? []
        photos = (try? c.decode([String].self, forKey: .photos)) ?? []
        prayers = (try? c.decode(PrayerLog.self, forKey: .prayers)) ?? PrayerLog()
        weightFromHealth = (try? c.decode(Bool.self, forKey: .weightFromHealth)) ?? false
        waterMl = (try? c.decode(Int.self, forKey: .waterMl)) ?? 0
        habitState = (try? c.decode([String: Bool].self, forKey: .habitState)) ?? [:]
        activeKcal = (try? c.decode(Double.self, forKey: .activeKcal)) ?? 0
        studyHours = (try? c.decode(Double.self, forKey: .studyHours)) ?? 0
        studySessions = (try? c.decode([StudySession].self, forKey: .studySessions)) ?? []
        workouts = (try? c.decode([Workout].self, forKey: .workouts)) ?? []
        mealTimes = (try? c.decode([String: Double].self, forKey: .mealTimes)) ?? [:]
        sleep = try? c.decodeIfPresent(SleepBreakdown.self, forKey: .sleep)
        readiness = (try? c.decode(Int.self, forKey: .readiness)) ?? 0
        sleepScore = (try? c.decode(Int.self, forKey: .sleepScore)) ?? 0
        status = (try? c.decode(String.self, forKey: .status)) ?? "normal"
        // Migrate legacy non-negotiables into the new manual-habit state.
        if habitState.isEmpty {
            if nn.moved { habitState["moved"] = true }
            if nn.phone { habitState["phone"] = true }
            if nn.side { habitState["side"] = true }
        }
    }

    /// Does this entry hold anything worth saving?
    var isMeaningful: Bool {
        if meals.hasAny { return true }
        if nn.anyTrue { return true }
        if status != "normal" { return true }
        if !logged.isEmpty || !photos.isEmpty || prayers.anyTrue || waterMl > 0 || !workouts.isEmpty { return true }
        return [training, run, weight, steps, sms, calories, proteinG]
            .contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

struct PrayerLog: Codable, Equatable {
    var fajr = false, dhuhr = false, asr = false, maghrib = false, isha = false
    var anyTrue: Bool { fajr || dhuhr || asr || maghrib || isha }
    var count: Int { [fajr, dhuhr, asr, maghrib, isha].filter { $0 }.count }
    func isOn(_ name: String) -> Bool {
        switch name {
        case "fajr": return fajr
        case "dhuhr": return dhuhr
        case "asr": return asr
        case "maghrib": return maghrib
        case "isha": return isha
        default: return false
        }
    }
}

/// Reference daily values for common nutrients (adult ballpark; some are upper limits).
enum NutritionRDA {
    static let table: [(key: String, rda: Double, unit: String, limit: Bool)] = [
        ("fiber", 30, "g", false), ("sugar", 50, "g", true), ("sodium", 2300, "mg", true),
        ("salt", 6, "g", true), ("cholesterol", 300, "mg", true), ("calcium", 1000, "mg", false),
        ("iron", 18, "mg", false), ("potassium", 3500, "mg", false), ("magnesium", 400, "mg", false),
        ("zinc", 11, "mg", false), ("vitamin a", 900, "µg", false), ("vitamin c", 90, "mg", false),
        ("vitamin d", 20, "µg", false), ("vitamin b12", 2.4, "µg", false), ("vitamin b6", 1.3, "mg", false),
        ("vitamin e", 15, "mg", false), ("folate", 400, "µg", false)
    ]
    /// Returns (rda, unit, isLimit) for a nutrient name, matching the most specific key.
    static func target(for name: String) -> (Double, String, Bool)? {
        let n = name.lowercased()
        for e in table.sorted(by: { $0.key.count > $1.key.count }) where n.contains(e.key) {
            return (e.rda, e.unit, e.limit)
        }
        return nil
    }
}

// MARK: - Pillars & configurable habits

enum Pillar: String, Codable, CaseIterable, Identifiable {
    case health, spirituality, work, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .health: return "Health"
        case .spirituality: return "Spirituality"
        case .work: return "Work & Study"
        case .custom: return "Personal"
        }
    }
    var icon: String {
        switch self {
        case .health: return "heart.fill"
        case .spirituality: return "moon.stars.fill"
        case .work: return "books.vertical.fill"
        case .custom: return "star.fill"
        }
    }
    var hex: UInt {
        switch self {
        case .health: return 0xFB1E4B
        case .spirituality: return 0xC8843E
        case .work: return 0x5B43E0
        case .custom: return 0x16A06A
        }
    }
}

/// How a habit is marked complete.
enum HabitLinkType: String, Codable, CaseIterable, Identifiable {
    case manual, protein, prayer, steps, activeEnergy, water, studyHours, sleep
    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual: return "Manual tap"
        case .protein: return "Protein ≥ target"
        case .prayer: return "A prayer prayed"
        case .steps: return "Steps ≥ target"
        case .activeEnergy: return "Active energy ≥ target"
        case .water: return "Water ≥ target"
        case .studyHours: return "Study hours ≥ target"
        case .sleep: return "Slept well (score ≥ target)"
        }
    }
    var isAuto: Bool { self != .manual }
}

struct HabitDef: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var pillar: Pillar = .custom
    var link: HabitLinkType = .manual
    var prayerName: String = "fajr"   // for .prayer
    var threshold: Double = 0          // for steps/activeEnergy/studyHours (0 = use global target)
    var active: Bool = true
    var order: Int = 0
}

struct StudySession: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var subject: String
    var minutes: Int
}

struct Subject: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var done: Bool = false
}

// MARK: - Strength / workout logging

struct StrengthSet: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var reps: Int = 10
    var weightKg: Double = 0

    init(reps: Int = 10, weightKg: Double = 0) { self.reps = reps; self.weightKg = weightKg }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        reps = (try? c.decode(Int.self, forKey: .reps)) ?? 0
        weightKg = (try? c.decode(Double.self, forKey: .weightKg)) ?? 0
    }
}

struct Exercise: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String = ""
    var sets: [StrengthSet] = [StrengthSet()]

    init(name: String = "", sets: [StrengthSet] = [StrengthSet()]) { self.name = name; self.sets = sets }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        sets = (try? c.decode([StrengthSet].self, forKey: .sets)) ?? []
    }
    /// Σ reps × weight across all sets.
    var volume: Double { sets.reduce(0) { $0 + Double($1.reps) * $1.weightKg } }
}

struct Workout: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var kind: String = "strength"      // strength | cardio | mobility | other
    var title: String = ""             // optional label e.g. "Push day"
    var exercises: [Exercise] = []
    var durationMin: Int = 0
    var note: String = ""
    var healthWritten: Bool = false

    init(kind: String = "strength", title: String = "", exercises: [Exercise] = [],
         durationMin: Int = 0, note: String = "") {
        self.kind = kind; self.title = title; self.exercises = exercises
        self.durationMin = durationMin; self.note = note
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "strength"
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        exercises = (try? c.decode([Exercise].self, forKey: .exercises)) ?? []
        durationMin = (try? c.decode(Int.self, forKey: .durationMin)) ?? 0
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        healthWritten = (try? c.decode(Bool.self, forKey: .healthWritten)) ?? false
    }

    var volume: Double { exercises.reduce(0) { $0 + $1.volume } }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    static let kinds: [(id: String, label: String, symbol: String)] = [
        ("strength", "Strength", "dumbbell.fill"),
        ("cardio", "Cardio", "figure.run"),
        ("mobility", "Mobility", "figure.cooldown"),
        ("other", "Other", "figure.mixed.cardio")
    ]
    static func label(_ kind: String) -> String { kinds.first { $0.id == kind }?.label ?? "Workout" }
    static func symbol(_ kind: String) -> String { kinds.first { $0.id == kind }?.symbol ?? "dumbbell.fill" }
}

/// A named target date (exam, deadline, launch…). Multiple can run at once.
struct Countdown: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var dateEpoch: Double
    var kind: String = "study"   // "study" or "work" (icon only)
    var date: Date { Date(timeIntervalSince1970: dateEpoch) }
}

// MARK: - Routine template & scheduled sessions

/// A recurring slot in the weekly routine. `weekday` 1–7 (Sun–Sat), 0 = every day.
struct RoutineBlock: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var weekday: Int = 0
    var title: String = ""
    var kind: String = "strength"     // strength|cardio|run|walk|mobility|focus|custom
    var hour: Int = 7
    var minute: Int = 0
    var durationMin: Int = 45
    var withPT: Bool = false
    var remind: Bool = true

    init(weekday: Int = 0, title: String = "", kind: String = "strength",
         hour: Int = 7, minute: Int = 0, durationMin: Int = 45, withPT: Bool = false, remind: Bool = true) {
        self.weekday = weekday; self.title = title; self.kind = kind
        self.hour = hour; self.minute = minute; self.durationMin = durationMin
        self.withPT = withPT; self.remind = remind
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        weekday = (try? c.decode(Int.self, forKey: .weekday)) ?? 0
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "strength"
        hour = (try? c.decode(Int.self, forKey: .hour)) ?? 7
        minute = (try? c.decode(Int.self, forKey: .minute)) ?? 0
        durationMin = (try? c.decode(Int.self, forKey: .durationMin)) ?? 45
        withPT = (try? c.decode(Bool.self, forKey: .withPT)) ?? false
        remind = (try? c.decode(Bool.self, forKey: .remind)) ?? true
    }
}

/// A concrete planned session (one-off, or materialised from a RoutineBlock).
struct ScheduledSession: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var dateEpoch: Double = 0
    var title: String = ""
    var kind: String = "strength"     // pt|strength|cardio|run|walk|fitnessplus|mobility|custom
    var durationMin: Int = 45
    var location: String = ""
    var withPT: Bool = false
    var remindMin: Int = 60
    var calendarEventID: String? = nil
    var done: Bool = false
    var fromRoutine: Bool = false
    var fromAIPlan: Bool = false

    init(dateEpoch: Double = 0, title: String = "", kind: String = "strength", durationMin: Int = 45,
         location: String = "", withPT: Bool = false, remindMin: Int = 60, fromRoutine: Bool = false,
         fromAIPlan: Bool = false) {
        self.dateEpoch = dateEpoch; self.title = title; self.kind = kind; self.durationMin = durationMin
        self.location = location; self.withPT = withPT; self.remindMin = remindMin
        self.fromRoutine = fromRoutine; self.fromAIPlan = fromAIPlan
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        dateEpoch = (try? c.decode(Double.self, forKey: .dateEpoch)) ?? 0
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "strength"
        durationMin = (try? c.decode(Int.self, forKey: .durationMin)) ?? 45
        location = (try? c.decode(String.self, forKey: .location)) ?? ""
        withPT = (try? c.decode(Bool.self, forKey: .withPT)) ?? false
        remindMin = (try? c.decode(Int.self, forKey: .remindMin)) ?? 60
        calendarEventID = try? c.decodeIfPresent(String.self, forKey: .calendarEventID)
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        fromRoutine = (try? c.decode(Bool.self, forKey: .fromRoutine)) ?? false
        fromAIPlan = (try? c.decode(Bool.self, forKey: .fromAIPlan)) ?? false
    }
    var date: Date { Date(timeIntervalSince1970: dateEpoch) }

    static let kinds: [(id: String, label: String, symbol: String)] = [
        ("pt", "PT session", "figure.strengthtraining.traditional"),
        ("strength", "Strength", "dumbbell.fill"),
        ("cardio", "Cardio", "figure.run"),
        ("run", "Run", "figure.run"),
        ("walk", "Walk", "figure.walk"),
        ("fitnessplus", "Fitness+", "applelogo"),
        ("mobility", "Mobility / stretch", "figure.cooldown"),
        ("stretch", "Stretch", "figure.flexibility"),
        ("cooldown", "Cooldown", "figure.cooldown"),
        ("winddown", "Wind-down", "moon.zzz.fill"),
        ("work", "Work block", "briefcase.fill"),
        ("focus", "Focus / study", "brain.head.profile"),
        ("meal", "Meal", "fork.knife"),
        ("custom", "Other", "calendar")
    ]
    static func symbol(_ k: String) -> String { kinds.first { $0.id == k }?.symbol ?? "calendar" }
    static func label(_ k: String) -> String { kinds.first { $0.id == k }?.label ?? "Session" }
}

/// A single AI-proposed plan slot before it's applied to the week (transient draft).
struct PlanBlock: Identifiable, Equatable {
    var id = UUID().uuidString
    var day: Int = 0        // 0 = today, …6
    var hour: Int = 7
    var minute: Int = 0
    var durationMin: Int = 30
    var kind: String = "work"
    var title: String = ""
    var note: String = ""
    var remind: Bool = true
    var enabled: Bool = true
}

// MARK: - Occasions & travel (events to plan for)

struct ChecklistItem: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var text: String
    var done: Bool = false
    init(text: String, done: Bool = false) { self.text = text; self.done = done }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
    }
}

struct ItineraryItem: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var dateEpoch: Double = 0
    var title: String = ""
    var detail: String = ""
    init(dateEpoch: Double = 0, title: String = "", detail: String = "") {
        self.dateEpoch = dateEpoch; self.title = title; self.detail = detail
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        dateEpoch = (try? c.decode(Double.self, forKey: .dateEpoch)) ?? 0
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
    }
    var date: Date? { dateEpoch > 0 ? Date(timeIntervalSince1970: dateEpoch) : nil }
}

struct Occasion: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title: String = ""
    var type: String = "custom"        // birthday | anniversary | wedding | travel | custom
    var dateEpoch: Double = 0
    var recurringAnnual: Bool = false
    var person: String = ""
    var location: String = ""
    var notes: String = ""
    var checklist: [ChecklistItem] = []
    var itinerary: [ItineraryItem] = []
    var calendarSynced: Bool = false
    var source: String = "manual"      // manual | contacts | calendar

    init(title: String = "", type: String = "custom", dateEpoch: Double = 0,
         recurringAnnual: Bool = false, person: String = "", location: String = "", source: String = "manual") {
        self.title = title; self.type = type; self.dateEpoch = dateEpoch
        self.recurringAnnual = recurringAnnual; self.person = person; self.location = location; self.source = source
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        type = (try? c.decode(String.self, forKey: .type)) ?? "custom"
        dateEpoch = (try? c.decode(Double.self, forKey: .dateEpoch)) ?? 0
        recurringAnnual = (try? c.decode(Bool.self, forKey: .recurringAnnual)) ?? false
        person = (try? c.decode(String.self, forKey: .person)) ?? ""
        location = (try? c.decode(String.self, forKey: .location)) ?? ""
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        checklist = (try? c.decode([ChecklistItem].self, forKey: .checklist)) ?? []
        itinerary = (try? c.decode([ItineraryItem].self, forKey: .itinerary)) ?? []
        calendarSynced = (try? c.decode(Bool.self, forKey: .calendarSynced)) ?? false
        source = (try? c.decode(String.self, forKey: .source)) ?? "manual"
    }

    /// Next occurrence date (rolls annual occasions forward to the next upcoming one).
    var nextDate: Date? {
        guard dateEpoch > 0 else { return nil }
        let base = Date(timeIntervalSince1970: dateEpoch)
        guard recurringAnnual else { return base }
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        var comps = cal.dateComponents([.month, .day], from: base)
        comps.year = cal.component(.year, from: now)
        guard let thisYear = cal.date(from: comps) else { return base }
        if thisYear >= now { return thisYear }
        comps.year = (comps.year ?? 0) + 1
        return cal.date(from: comps) ?? base
    }

    static let types: [(id: String, label: String, symbol: String)] = [
        ("birthday", "Birthday", "gift.fill"),
        ("anniversary", "Anniversary", "heart.fill"),
        ("wedding", "Wedding", "figure.2.arms.open"),
        ("travel", "Travel", "airplane"),
        ("custom", "Other", "star.fill")
    ]
    static func symbol(_ t: String) -> String { types.first { $0.id == t }?.symbol ?? "star.fill" }
    static func label(_ t: String) -> String { types.first { $0.id == t }?.label ?? "Event" }
}

// MARK: - Body composition (InBody) & lab reports

struct BodyComp: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var date: String
    var weight: Double?          // kg
    var bodyFat: Double?         // %
    var leanMass: Double?        // kg
    var skeletalMuscle: Double?  // kg
    var bmi: Double?
    var visceralFat: Double?     // level (kept in-app; Health has no type for it)
}

struct LabItem: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var value: Double
    var unit: String
    var written: Bool = false    // whether it was saved to Apple Health
}

struct LabRecord: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var date: String
    var title: String
    var items: [LabItem]
}

/// A day's status — "protected" statuses pause expectations & the streak.
enum DayStatus {
    static let all: [(id: String, label: String, symbol: String)] = [
        ("normal", "Normal", "sun.max.fill"),
        ("rest", "Rest day", "figure.cooldown"),
        ("sick", "Sick", "thermometer.medium"),
        ("travel", "Travelling", "airplane")
    ]
    static func label(_ s: String) -> String { all.first { $0.id == s }?.label ?? "Normal" }
    static func symbol(_ s: String) -> String { all.first { $0.id == s }?.symbol ?? "sun.max.fill" }
    static func isProtected(_ s: String) -> Bool { s == "sick" || s == "travel" || s == "rest" }
}

/// Detailed sleep for a night, derived from HealthKit sleep-analysis samples.
struct SleepBreakdown: Codable, Equatable {
    var asleepMin: Double = 0
    var inBedMin: Double = 0
    var deepMin: Double = 0
    var remMin: Double = 0
    var coreMin: Double = 0
    var awakeMin: Double = 0
    var bedEpoch: Double = 0
    var wakeEpoch: Double = 0
    var efficiency: Double = 0     // 0–1 (asleep / in-bed)

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asleepMin = (try? c.decode(Double.self, forKey: .asleepMin)) ?? 0
        inBedMin = (try? c.decode(Double.self, forKey: .inBedMin)) ?? 0
        deepMin = (try? c.decode(Double.self, forKey: .deepMin)) ?? 0
        remMin = (try? c.decode(Double.self, forKey: .remMin)) ?? 0
        coreMin = (try? c.decode(Double.self, forKey: .coreMin)) ?? 0
        awakeMin = (try? c.decode(Double.self, forKey: .awakeMin)) ?? 0
        bedEpoch = (try? c.decode(Double.self, forKey: .bedEpoch)) ?? 0
        wakeEpoch = (try? c.decode(Double.self, forKey: .wakeEpoch)) ?? 0
        efficiency = (try? c.decode(Double.self, forKey: .efficiency)) ?? 0
    }
    var asleepHours: Double { asleepMin / 60 }
    var hasStages: Bool { deepMin > 0 || remMin > 0 || coreMin > 0 }
    var bedDate: Date? { bedEpoch > 0 ? Date(timeIntervalSince1970: bedEpoch) : nil }
    var wakeDate: Date? { wakeEpoch > 0 ? Date(timeIntervalSince1970: wakeEpoch) : nil }
}

/// A single contributor to the readiness score, for an explainable breakdown.
struct ReadinessFactor: Identifiable, Equatable {
    var id = UUID().uuidString
    var label: String
    var delta: Int          // signed points contribution
    var note: String
    init(_ label: String, _ delta: Int, _ note: String) { self.label = label; self.delta = delta; self.note = note }
}

/// Free-text health profile entry the user maintains — fed to the AI coach for context.
struct HealthNote: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var dateEpoch: Double = 0
    var title: String = ""
    var text: String = ""
    var category: String = "note"   // condition | medication | injury | goal | note

    init(title: String = "", text: String = "", category: String = "note") {
        self.title = title; self.text = text; self.category = category
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        dateEpoch = (try? c.decode(Double.self, forKey: .dateEpoch)) ?? 0
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        category = (try? c.decode(String.self, forKey: .category)) ?? "note"
    }

    static let categories: [(id: String, label: String, symbol: String)] = [
        ("condition", "Condition", "stethoscope"),
        ("medication", "Medication / supplement", "pills.fill"),
        ("injury", "Injury / physio", "bandage.fill"),
        ("goal", "Goal", "target"),
        ("note", "Note", "note.text")
    ]
    static func label(_ c: String) -> String { categories.first { $0.id == c }?.label ?? "Note" }
    static func symbol(_ c: String) -> String { categories.first { $0.id == c }?.symbol ?? "note.text" }
}

/// A complete, portable backup (everything + photos) for export to Files / iCloud Drive.
struct BackupBundle: Codable {
    var version = 2
    var data: AppData
    var photos: [String: String] = [:]   // filename → base64 JPEG
}

// MARK: - Catalog (known supplements & foods) + quick-logged items

enum CatalogKind: String, Codable, CaseIterable {
    case supplement, food
    var title: String { self == .supplement ? "Supplements" : "Foods" }
}

/// A micronutrient (vitamin / mineral / other) with amount + unit.
struct Micro: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var amount: Double
    var unit: String

    init(id: String = UUID().uuidString, name: String, amount: Double, unit: String) {
        self.id = id; self.name = name; self.amount = amount; self.unit = unit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
    }
}

struct CatalogItem: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var kind: CatalogKind
    var name: String
    var serving: String = ""          // e.g. "1 scoop (30g)"
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var micros: [Micro] = []          // vitamins, minerals, etc.

    init(id: String = UUID().uuidString, kind: CatalogKind, name: String, serving: String = "",
         calories: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0,
         fiber: Double = 0, micros: [Micro] = []) {
        self.id = id; self.kind = kind; self.name = name; self.serving = serving
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fat = fat
        self.fiber = fiber; self.micros = micros
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        kind = (try? c.decode(CatalogKind.self, forKey: .kind)) ?? .food
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        serving = (try? c.decode(String.self, forKey: .serving)) ?? ""
        calories = (try? c.decode(Double.self, forKey: .calories)) ?? 0
        protein = (try? c.decode(Double.self, forKey: .protein)) ?? 0
        carbs = (try? c.decode(Double.self, forKey: .carbs)) ?? 0
        fat = (try? c.decode(Double.self, forKey: .fat)) ?? 0
        fiber = (try? c.decode(Double.self, forKey: .fiber)) ?? 0
        micros = (try? c.decode([Micro].self, forKey: .micros)) ?? []
    }
}

/// A catalog item applied to a specific day's totals (full nutrition snapshot).
struct LoggedItem: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var itemID: String
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var micros: [Micro] = []
    var qty: Int = 1          // number of servings/doses (calories etc are PER serving)

    init(itemID: String, name: String, calories: Double, protein: Double,
         carbs: Double = 0, fat: Double = 0, fiber: Double = 0, micros: [Micro] = [], qty: Int = 1) {
        self.itemID = itemID; self.name = name; self.calories = calories; self.protein = protein
        self.carbs = carbs; self.fat = fat; self.fiber = fiber; self.micros = micros; self.qty = qty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        itemID = (try? c.decode(String.self, forKey: .itemID)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        calories = (try? c.decode(Double.self, forKey: .calories)) ?? 0
        protein = (try? c.decode(Double.self, forKey: .protein)) ?? 0
        carbs = (try? c.decode(Double.self, forKey: .carbs)) ?? 0
        fat = (try? c.decode(Double.self, forKey: .fat)) ?? 0
        fiber = (try? c.decode(Double.self, forKey: .fiber)) ?? 0
        micros = (try? c.decode([Micro].self, forKey: .micros)) ?? []
        qty = (try? c.decode(Int.self, forKey: .qty)) ?? 1
    }
}

// MARK: - Top-level persisted document

struct AppData: Codable {
    var entries: [String: Entry] = [:]
    var audits: [String: String] = [:]
    var catalog: [CatalogItem] = []
    var bodyComps: [BodyComp] = []
    var labs: [LabRecord] = []
    var habits: [HabitDef] = []
    var subjects: [Subject] = []
    var countdowns: [Countdown] = []
    var routine: [RoutineBlock] = []
    var sessions: [ScheduledSession] = []
    var occasions: [Occasion] = []
    var healthNotes: [HealthNote] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = (try? c.decode([String: Entry].self, forKey: .entries)) ?? [:]
        audits = (try? c.decode([String: String].self, forKey: .audits)) ?? [:]
        catalog = (try? c.decode([CatalogItem].self, forKey: .catalog)) ?? []
        bodyComps = (try? c.decode([BodyComp].self, forKey: .bodyComps)) ?? []
        labs = (try? c.decode([LabRecord].self, forKey: .labs)) ?? []
        habits = (try? c.decode([HabitDef].self, forKey: .habits)) ?? []
        subjects = (try? c.decode([Subject].self, forKey: .subjects)) ?? []
        countdowns = (try? c.decode([Countdown].self, forKey: .countdowns)) ?? []
        routine = (try? c.decode([RoutineBlock].self, forKey: .routine)) ?? []
        sessions = (try? c.decode([ScheduledSession].self, forKey: .sessions)) ?? []
        occasions = (try? c.decode([Occasion].self, forKey: .occasions)) ?? []
        healthNotes = (try? c.decode([HealthNote].self, forKey: .healthNotes)) ?? []
    }
}

extension HabitDef {
    /// Tailored starter habits for a pillar, seeded when an area is first turned on.
    static func starters(pillar: Pillar, workMode: String, faith: String) -> [HabitDef] {
        switch pillar {
        case .health:
            return [
                HabitDef(title: "Moved — walk, gym or run", pillar: .health, link: .manual),
                HabitDef(title: "Hit protein target", pillar: .health, link: .protein)
            ]
        case .spirituality:
            if faith == "islam" {
                return [HabitDef(title: "Prayed Fajr", pillar: .spirituality, link: .prayer, prayerName: "fajr")]
            }
            return [
                HabitDef(title: "Prayer / worship", pillar: .spirituality, link: .manual),
                HabitDef(title: "Gratitude", pillar: .spirituality, link: .manual)
            ]
        case .work:
            let hours = workMode == "work" ? "Hit focus hours" : "Hit study hours"
            let task = workMode == "work" ? "Cleared the top task" : "Revised one topic"
            return [
                HabitDef(title: hours, pillar: .work, link: .studyHours),
                HabitDef(title: task, pillar: .work, link: .manual)
            ]
        case .custom:
            return [HabitDef(title: "One thing just for me", pillar: .custom, link: .manual)]
        }
    }

    /// The original five non-negotiables, seeded on first run.
    static var defaults: [HabitDef] {
        [
            HabitDef(id: "fajr", title: "Prayed Fajr", pillar: .spirituality, link: .prayer, prayerName: "fajr", order: 0),
            HabitDef(id: "protein", title: "Hit protein target", pillar: .health, link: .protein, order: 1),
            HabitDef(id: "moved", title: "Moved — gym, walk or run", pillar: .health, link: .manual, order: 2),
            HabitDef(id: "phone", title: "Phone off by 11–11:30pm", pillar: .health, link: .manual, order: 3),
            HabitDef(id: "side", title: "Started the night on my side", pillar: .health, link: .manual, order: 4)
        ]
    }
}

// MARK: - Settings

struct AppSettings: Codable, Equatable {
    var provider = "anthropic"
    var model = "sonnet46"
    var customModel = ""                          // free-form model id (OpenRouter / Ollama "Custom")
    var ollamaHost = "http://localhost:11434"     // base URL of the user's Ollama server
    var healthkit = true
    var hkRead = HKReadFlags()
    var hkWrite = HKWriteFlags()
    var calendarSync = false
    var remindersSync = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = (try? c.decode(String.self, forKey: .provider)) ?? "anthropic"
        model = (try? c.decode(String.self, forKey: .model)) ?? "sonnet46"
        customModel = (try? c.decode(String.self, forKey: .customModel)) ?? ""
        ollamaHost = (try? c.decode(String.self, forKey: .ollamaHost)) ?? "http://localhost:11434"
        healthkit = (try? c.decode(Bool.self, forKey: .healthkit)) ?? true
        hkRead = (try? c.decode(HKReadFlags.self, forKey: .hkRead)) ?? HKReadFlags()
        hkWrite = (try? c.decode(HKWriteFlags.self, forKey: .hkWrite)) ?? HKWriteFlags()
        calendarSync = (try? c.decode(Bool.self, forKey: .calendarSync)) ?? false
        remindersSync = (try? c.decode(Bool.self, forKey: .remindersSync)) ?? false
    }
}

struct HKReadFlags: Codable, Equatable {
    var weight = true
    var steps = true
    var energy = true
    var workouts = true
    var sleep = false
}

struct HKWriteFlags: Codable, Equatable {
    var calories = true
    var protein = true
}

/// User-configurable daily targets (drive rings, labels, chart goal lines & scoring).
struct Targets: Codable, Equatable {
    var calories: Double = 2000
    var protein: Double = 120
    var steps: Double = 8000
    var studyHours: Double = 4
    var examName: String = ""
    var examDateEpoch: Double = 0
    var workMode: String = "study"          // "study" or "work"

    // The personal "prize" metric shown on Trends (defaults to visceral fat).
    var prizeName: String = "Visceral fat"
    var prizeUnit: String = ""
    var prizeStart: Double = 14
    var prizeTarget: Double = 10
    var prizeCurrent: Double = 14
    var prizeLowerIsBetter: Bool = true

    var examDate: Date? { examDateEpoch > 0 ? Date(timeIntervalSince1970: examDateEpoch) : nil }

    private enum LegacyKeys: String, CodingKey { case visceralStart, visceralTarget }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
        calories = (try? c.decode(Double.self, forKey: .calories)) ?? 2000
        protein = (try? c.decode(Double.self, forKey: .protein)) ?? 120
        steps = (try? c.decode(Double.self, forKey: .steps)) ?? 8000
        studyHours = (try? c.decode(Double.self, forKey: .studyHours)) ?? 4
        examName = (try? c.decode(String.self, forKey: .examName)) ?? ""
        examDateEpoch = (try? c.decode(Double.self, forKey: .examDateEpoch)) ?? 0
        workMode = (try? c.decode(String.self, forKey: .workMode)) ?? "study"
        prizeName = (try? c.decode(String.self, forKey: .prizeName)) ?? "Visceral fat"
        prizeUnit = (try? c.decode(String.self, forKey: .prizeUnit)) ?? ""
        prizeStart = (try? c.decode(Double.self, forKey: .prizeStart))
            ?? (legacy.flatMap { try? $0.decode(Double.self, forKey: .visceralStart) }) ?? 14
        prizeTarget = (try? c.decode(Double.self, forKey: .prizeTarget))
            ?? (legacy.flatMap { try? $0.decode(Double.self, forKey: .visceralTarget) }) ?? 10
        prizeCurrent = (try? c.decode(Double.self, forKey: .prizeCurrent)) ?? prizeStart
        prizeLowerIsBetter = (try? c.decode(Bool.self, forKey: .prizeLowerIsBetter)) ?? true
    }
}

/// Which sections appear on the Today screen, in what order (user-customizable).
struct ModulePrefs: Codable, Equatable {
    var coach = true
    var prayer = true
    var health = true
    var meals = true
    var hydration = true
    var quickLog = true
    var workStudy = true
    var training = true
    var photos = true
    var fasting = false
    var sleep = true
    var weather = true
    var order: [String] = ModulePrefs.defaultOrder

    /// Canonical order; "habits" and "score" are core (always shown, but movable).
    static let defaultOrder = ["coach", "weather", "prayer", "fasting", "sleep", "health", "meals", "hydration",
                               "quickLog", "habits", "score", "workStudy", "training", "photos"]
    static let coreKeys: Set<String> = ["habits", "score"]

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func f(_ k: CodingKeys) -> Bool { (try? c.decode(Bool.self, forKey: k)) ?? true }
        coach = f(.coach); prayer = f(.prayer); health = f(.health); meals = f(.meals)
        hydration = f(.hydration); quickLog = f(.quickLog); workStudy = f(.workStudy)
        training = f(.training); photos = f(.photos)
        fasting = (try? c.decode(Bool.self, forKey: .fasting)) ?? false
        sleep = (try? c.decode(Bool.self, forKey: .sleep)) ?? true
        weather = (try? c.decode(Bool.self, forKey: .weather)) ?? true
        let saved = (try? c.decode([String].self, forKey: .order)) ?? ModulePrefs.defaultOrder
        // Keep known keys in saved order, then append any new ones not yet present.
        var result = saved.filter { ModulePrefs.defaultOrder.contains($0) }
        for k in ModulePrefs.defaultOrder where !result.contains(k) { result.append(k) }
        order = result
    }

    var orderedKeys: [String] { order }

    func label(_ key: String) -> String {
        switch key {
        case "coach": return "AI coach"
        case "weather": return "Weather"
        case "prayer": return "Prayer times"
        case "fasting": return "Fasting"
        case "sleep": return "Sleep & readiness"
        case "health": return "Apple Health card"
        case "meals": return "Meals & calories"
        case "hydration": return "Hydration"
        case "quickLog": return "Quick log"
        case "habits": return "Non-negotiables"
        case "score": return "Daily score"
        case "workStudy": return "Work & study"
        case "training": return "Training & body"
        case "photos": return "Photos"
        default: return key
        }
    }

    func enabled(_ key: String) -> Bool {
        if ModulePrefs.coreKeys.contains(key) { return true }
        switch key {
        case "coach": return coach
        case "weather": return weather
        case "prayer": return prayer
        case "fasting": return fasting
        case "sleep": return sleep
        case "health": return health
        case "meals": return meals
        case "hydration": return hydration
        case "quickLog": return quickLog
        case "workStudy": return workStudy
        case "training": return training
        case "photos": return photos
        default: return true
        }
    }

    mutating func setEnabled(_ key: String, _ v: Bool) {
        switch key {
        case "coach": coach = v
        case "weather": weather = v
        case "prayer": prayer = v
        case "fasting": fasting = v
        case "sleep": sleep = v
        case "health": health = v
        case "meals": meals = v
        case "hydration": hydration = v
        case "quickLog": quickLog = v
        case "workStudy": workStudy = v
        case "training": training = v
        case "photos": photos = v
        default: break
        }
    }

    var isCore: (String) -> Bool { { ModulePrefs.coreKeys.contains($0) } }
}

/// User personalization: renamed pillars and per-module accent colors.
struct Personalization: Codable, Equatable {
    var pillarTitles: [String: String] = [:]   // Pillar.rawValue → custom name
    var moduleColors: [String: UInt] = [:]      // module key → hex color

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pillarTitles = (try? c.decode([String: String].self, forKey: .pillarTitles)) ?? [:]
        moduleColors = (try? c.decode([String: UInt].self, forKey: .moduleColors)) ?? [:]
    }
}

/// Mode-aware vocabulary for the Work/Study pillar.
struct WorkVocab {
    let pillar: String       // section header
    let session: String      // "Study session" / "Focus session"
    let hours: String        // "Study hours" / "Focus hours"
    let items: String        // "Subjects" / "Projects"
    let itemSingular: String // "subject" / "project"
    let countdown: String    // "Exam" / "Deadline"

    static func forMode(_ mode: String) -> WorkVocab {
        if mode == "work" {
            return WorkVocab(pillar: "Work", session: "Focus session", hours: "Focus hours",
                             items: "Projects", itemSingular: "project / task", countdown: "Deadline")
        }
        return WorkVocab(pillar: "Study", session: "Study session", hours: "Study hours",
                         items: "Subjects", itemSingular: "subject / topic", countdown: "Exam")
    }
}

// MARK: - Coach chat

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var role: String          // "user" | "assistant"
    var text: String
    var isUser: Bool { role == "user" }

    init(role: String, text: String) { self.role = role; self.text = text }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        role = (try? c.decode(String.self, forKey: .role)) ?? "assistant"
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
    }
}

// MARK: - Provider catalogue (mirrors the design)

struct AIModel: Identifiable, Equatable {
    let id: String
    let name: String
    let sub: String
}

struct AIProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let tag: String
    let foot: String
    let models: [AIModel]
    var needsKey: Bool = true          // requires an API key
    var isLocal: Bool = false          // talks to a server you run (Ollama) — data stays on your network
    var allowsCustomModel: Bool = false // free-form model id field

    /// Data leaves the device to a third-party cloud (drives the privacy footer & key prompt).
    var isCloud: Bool { id != "apple" && !isLocal }
}

enum Providers {
    static let all: [AIProvider] = [
        AIProvider(
            id: "apple", name: "Apple Intelligence", tag: "On-device · Private",
            foot: "Runs privately on your iPhone or Private Cloud Compute. Nothing leaves Apple\u{2019}s secure path.",
            models: [
                AIModel(id: "apple-od", name: "On-Device", sub: "Fast, fully private"),
                AIModel(id: "apple-pcc", name: "Private Cloud Compute", sub: "Larger model, still private")
            ], needsKey: false),
        AIProvider(
            id: "openai", name: "OpenAI", tag: "GPT family",
            foot: "Meals are sent to OpenAI for estimation. Standard API privacy applies.",
            models: [
                AIModel(id: "gpt5", name: "GPT-5", sub: "Most capable"),
                AIModel(id: "gpt5-mini", name: "GPT-5 mini", sub: "Faster, cheaper"),
                AIModel(id: "gpt41", name: "GPT-4.1", sub: "")
            ]),
        AIProvider(
            id: "anthropic", name: "Anthropic", tag: "Claude family",
            foot: "Meals are sent to Anthropic for estimation. Standard API privacy applies.",
            models: [
                AIModel(id: "opus48", name: "Claude Opus 4.8", sub: "Deepest reasoning"),
                AIModel(id: "sonnet46", name: "Claude Sonnet 4.6", sub: "Balanced — recommended"),
                AIModel(id: "haiku45", name: "Claude Haiku 4.5", sub: "Fastest")
            ]),
        AIProvider(
            id: "gemini", name: "Google Gemini", tag: "Gemini family",
            foot: "Meals are sent to Google for estimation. Standard API privacy applies.",
            models: [
                AIModel(id: "g31pro", name: "Gemini 3.1 Pro", sub: "Most capable"),
                AIModel(id: "g31flash", name: "Gemini 3.1 Flash", sub: "Fast"),
                AIModel(id: "g25pro", name: "Gemini 2.5 Pro", sub: "")
            ]),
        AIProvider(
            id: "openrouter", name: "OpenRouter", tag: "Any model · one key",
            foot: "Meals are routed through OpenRouter to the model you pick. Get a key at openrouter.ai. Vision works only on multimodal models.",
            models: [
                AIModel(id: "or-claude-sonnet", name: "Claude Sonnet 4.6", sub: "Balanced · vision"),
                AIModel(id: "or-gpt5", name: "GPT-5", sub: "vision"),
                AIModel(id: "or-gemini-flash", name: "Gemini 3.1 Flash", sub: "Fast · vision"),
                AIModel(id: "or-llama", name: "Llama 3.3 70B", sub: "Open · text only"),
                AIModel(id: "custom", name: "Custom model\u{2026}", sub: "Paste any OpenRouter model id")
            ], allowsCustomModel: true),
        AIProvider(
            id: "deepseek", name: "DeepSeek", tag: "DeepSeek family",
            foot: "Meals are sent to DeepSeek for estimation. Get a key at platform.deepseek.com. Text only — no photo scanning.",
            models: [
                AIModel(id: "deepseek-chat", name: "DeepSeek-V3", sub: "Fast, general"),
                AIModel(id: "deepseek-reasoner", name: "DeepSeek-R1", sub: "Deeper reasoning")
            ]),
        AIProvider(
            id: "ollama", name: "Ollama", tag: "Local · Private",
            foot: "Runs against your own Ollama server — nothing leaves your network. Set the server address below. Vision needs a multimodal model (e.g. llava).",
            models: [
                AIModel(id: "ollama-llama", name: "Llama 3.2", sub: "llama3.2"),
                AIModel(id: "ollama-qwen", name: "Qwen 2.5", sub: "qwen2.5"),
                AIModel(id: "ollama-llava", name: "LLaVA", sub: "llava · vision"),
                AIModel(id: "custom", name: "Custom model\u{2026}", sub: "Any pulled model name")
            ], needsKey: false, isLocal: true, allowsCustomModel: true),
        AIProvider(
            id: "ollamacloud", name: "Ollama Cloud", tag: "Hosted · API key",
            foot: "Runs large open models on Ollama\u{2019}s hosted cloud. Get a key at ollama.com. Meals are sent to Ollama for estimation.",
            models: [
                AIModel(id: "oc-gptoss", name: "gpt-oss 120B", sub: "gpt-oss:120b"),
                AIModel(id: "oc-deepseek", name: "DeepSeek V3.1", sub: "deepseek-v3.1:671b"),
                AIModel(id: "oc-qwen", name: "Qwen3 Coder", sub: "qwen3-coder:480b"),
                AIModel(id: "oc-glm", name: "GLM 4.6", sub: "glm-4.6"),
                AIModel(id: "custom", name: "Custom model\u{2026}", sub: "Any Ollama Cloud model id")
            ], allowsCustomModel: true)
    ]

    static func provider(_ id: String) -> AIProvider {
        all.first { $0.id == id } ?? all[2]
    }

    /// Maps an internal model id to the real API model identifier for each provider.
    static func apiModelID(provider: String, model: String, custom: String = "") -> String {
        if model == "custom" {
            let c = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return c.isEmpty ? "gpt-3.5-turbo" : c
        }
        switch model {
        case "opus48": return "claude-opus-4-8"
        case "sonnet46": return "claude-sonnet-4-6"
        case "haiku45": return "claude-haiku-4-5-20251001"
        case "gpt5": return "gpt-5"
        case "gpt5-mini": return "gpt-5-mini"
        case "gpt41": return "gpt-4.1"
        case "g31pro": return "gemini-2.5-pro"
        case "g31flash": return "gemini-2.5-flash"
        case "g25pro": return "gemini-2.5-pro"
        // OpenRouter — fully-qualified vendor/model slugs
        case "or-claude-sonnet": return "anthropic/claude-sonnet-4.5"
        case "or-gpt5": return "openai/gpt-5"
        case "or-gemini-flash": return "google/gemini-2.5-flash"
        case "or-llama": return "meta-llama/llama-3.3-70b-instruct"
        // DeepSeek (already real ids)
        case "deepseek-chat": return "deepseek-chat"
        case "deepseek-reasoner": return "deepseek-reasoner"
        // Ollama — local model names
        case "ollama-llama": return "llama3.2"
        case "ollama-qwen": return "qwen2.5"
        case "ollama-llava": return "llava"
        // Ollama Cloud — hosted model ids
        case "oc-gptoss": return "gpt-oss:120b"
        case "oc-deepseek": return "deepseek-v3.1:671b"
        case "oc-qwen": return "qwen3-coder:480b"
        case "oc-glm": return "glm-4.6"
        default: return model
        }
    }
}

// MARK: - Static content from the design

enum Content {
    /// key, label, placeholder (the user's real defaults)
    static let mealDefs: [(key: String, label: String, placeholder: String)] = [
        ("breakfast", "Breakfast", "2 egg bull\u{2019}s eye, ethapazham, black coffee"),
        ("snacks", "Snacks", "curd, apple, few nuts"),
        ("lunch", "Lunch", "rice, chicken curry, thoran"),
        ("dinner", "Dinner", "2 chapati, fish curry, veg"),
        ("drinks", "Drinks / supplements", "whey isolate, magnesium")
    ]

    /// key, label for the 5 non-negotiables
    static let nnDefs: [(key: String, label: String)] = [
        ("fajr", "Prayed Fajr"),
        ("protein", "Hit protein ~120g"),
        ("moved", "Moved — gym, walk or run"),
        ("phone", "Phone off by 11–11:30pm"),
        ("side", "Started the night on my side")
    ]

    static let tips: [String] = [
        "Coffee only after solid food — never on an empty stomach.",
        "Whey isolate in water, post-gym, is your easy protein win.",
        "Soluble fibre firms things up: isabgol, oats, a banana.",
        "No overhead or heavy-shrug work until the physio clears your neck.",
        "The trend matters far more than today\u{2019}s number on the scale.",
        "Minimise fried & greasy food — gut and deficit both thank you."
    ]

    static let baselineWeight = 84.3
    static let baselineDate = "2026-06-18"
    static let calorieTarget = 2000.0
    static let proteinTarget = 120.0
    static let stepsTarget = 8000.0
}
