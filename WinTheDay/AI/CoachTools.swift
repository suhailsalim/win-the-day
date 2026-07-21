import Foundation

/// One callable the coach can invoke instead of having everything pre-stuffed into its prompt.
/// `parameters` is the JSON-Schema "properties" object (the caller wraps it as `{"type":"object",...}`
/// per-provider). `run` executes synchronously against `AppStore` — every tool here is a cheap,
/// already-loaded local read, so no async/await or `@MainActor` hop is needed beyond the call site
/// already being on the main actor (`AppStore` itself is `@MainActor`).
struct CoachTool {
    let name: String
    let description: String
    let parameters: [String: Any]   // e.g. ["date": ["type": "string", "description": "yyyy-MM-dd, default today"]]
    let required: [String]
    let run: @MainActor (AppStore, [String: Any]) -> String
}

/// The read-only tool set the coach can call. Kept intentionally small and specific — each tool
/// answers one question well rather than dumping the whole data model, so responses stay cheap.
enum CoachToolRegistry {
    static let all: [CoachTool] = [
        CoachTool(name: "getDay", description: "Get one day's log: meals, calories, protein, water, prayers, study/focus hours, status.",
                  parameters: ["date": ["type": "string", "description": "yyyy-MM-dd; omit for today"]], required: [],
                  run: { store, args in store.toolGetDay(dateArg(args)) }),

        CoachTool(name: "getRecentDays", description: "Get a compact summary of the last N logged days (score, calories, protein, prayers, study hours).",
                  parameters: ["n": ["type": "integer", "description": "how many recent days, default 5, max 14"]], required: [],
                  run: { store, args in store.toolGetRecentDays(intArg(args, "n", 5, max: 14)) }),

        CoachTool(name: "getWeekStats", description: "Get this week's stats: days logged, average score, perfect days, weight change, average protein, prayers.",
                  parameters: [:], required: [], run: { store, _ in store.toolGetWeekStats() }),

        CoachTool(name: "getReadiness", description: "Get a day's Sleep/Readiness/Active/Eating scores and the factors behind them.",
                  parameters: ["date": ["type": "string", "description": "yyyy-MM-dd; omit for today"]], required: [],
                  run: { store, args in store.toolGetReadiness(dateArg(args)) }),

        CoachTool(name: "getFoodLog", description: "Get a day's full food log: meal text, AI estimate, quick-logged items, totals, eating score.",
                  parameters: ["date": ["type": "string", "description": "yyyy-MM-dd; omit for today"]], required: [],
                  run: { store, args in store.toolGetFoodLog(dateArg(args)) }),

        CoachTool(name: "getPrayers", description: "Get a day's five prayers and whether each was on-time, late, qadha, or not yet due.",
                  parameters: ["date": ["type": "string", "description": "yyyy-MM-dd; omit for today"]], required: [],
                  run: { store, args in store.toolGetPrayers(dateArg(args)) }),

        CoachTool(name: "getHealthIndex", description: "Get the user's health profile: latest body composition, recent labs, health notes (conditions/meds/injuries/goals), plus the latest value, general-range status and trend direction for every lab analyte they have imported.",
                  parameters: [:], required: [], run: { store, _ in store.toolGetHealthIndex() }),

        CoachTool(name: "getTargets", description: "Get the user's configured targets: calories, protein, steps, study/focus hours, and priority metric.",
                  parameters: [:], required: [], run: { store, _ in store.toolGetTargets() })
    ]

    private static func dateArg(_ args: [String: Any]) -> String? {
        (args["date"] as? String)?.trimmingCharacters(in: .whitespaces)
    }
    private static func intArg(_ args: [String: Any], _ key: String, _ fallback: Int, max: Int) -> Int {
        let v: Int
        if let i = args[key] as? Int { v = i }
        else if let d = args[key] as? Double { v = Int(d) }
        else if let s = args[key] as? String, let i = Int(s) { v = i }
        else { v = fallback }
        return Swift.max(1, Swift.min(max, v))
    }
}

// MARK: - Write tools (staged proposals — nothing mutates on call)
//
// Every tool below is a *proposal*. It builds a `PendingCoachWrite`, hands it to
// `AppStore.stageCoachWrite` (which only appends to an in-memory staging buffer) and returns the
// "awaiting confirmation" contract string. The user's data moves only when they tap Confirm in
// chat, which calls `AppStore.commitCoachWrite`. A tool here that mutated on call would defeat the
// entire design — do not add one.

extension CoachToolRegistry {
    static let mealKeys = ["breakfast", "snacks", "lunch", "dinner", "drinks"]
    static let prayerNames = ["fajr", "dhuhr", "asr", "maghrib", "isha"]

    private static let proposalNote =
        "Proposes the change; the user must confirm in-app before it is saved. Never tell the user it is done."

    static let writeTools: [CoachTool] = [
        CoachTool(name: "logFood",
                  description: "Propose adding one food item to a meal in the user's food log. \(proposalNote)",
                  parameters: [
                    "name": ["type": "string", "description": "food name, e.g. \"boiled egg\""],
                    "mealKey": ["type": "string", "enum": mealKeys, "description": "which meal it belongs to"],
                    "kcal": ["type": "number", "description": "calories in ONE serving"],
                    "protein": ["type": "number", "description": "protein grams in ONE serving; 0 if unknown"],
                    "qty": ["type": "number", "description": "number of servings, default 1"],
                    "date": ["type": "string", "description": "yyyy-MM-dd; omit for today"]
                  ],
                  required: ["name", "mealKey", "kcal"],
                  run: { store, args in proposeLogFood(store, args) }),

        CoachTool(name: "removeFood",
                  description: "Propose removing an item that is already in the user's food log, matched by name. \(proposalNote)",
                  parameters: [
                    "name": ["type": "string", "description": "name (or part of it) of the logged item to remove"],
                    "mealKey": ["type": "string", "enum": mealKeys, "description": "narrow the match to one meal; optional"],
                    "date": ["type": "string", "description": "yyyy-MM-dd; omit for today"]
                  ],
                  required: ["name"],
                  run: { store, args in proposeRemoveFood(store, args) }),

        CoachTool(name: "setMealText",
                  description: "Propose replacing a meal's free-text description (e.g. lunch = \"rice & dal\"). Pass an empty string to clear it. \(proposalNote)",
                  parameters: [
                    "mealKey": ["type": "string", "enum": mealKeys, "description": "which meal"],
                    "text": ["type": "string", "description": "the new text; \"\" clears the meal"],
                    "date": ["type": "string", "description": "yyyy-MM-dd; omit for today"]
                  ],
                  required: ["mealKey", "text"],
                  run: { store, args in proposeSetMealText(store, args) }),

        CoachTool(name: "setMealTime",
                  description: "Propose setting (or clearing) the time a meal was eaten. \(proposalNote)",
                  parameters: [
                    "mealKey": ["type": "string", "enum": mealKeys, "description": "which meal"],
                    "time": ["type": "string", "description": "24-hour HH:mm, e.g. \"13:30\""],
                    "clear": ["type": "boolean", "description": "true to remove the recorded time instead"],
                    "date": ["type": "string", "description": "yyyy-MM-dd; omit for today"]
                  ],
                  required: ["mealKey"],
                  run: { store, args in proposeSetMealTime(store, args) }),

        CoachTool(name: "togglePrayer",
                  description: "Propose marking one of the five prayers as prayed, or un-marking it. \(proposalNote)",
                  parameters: [
                    "prayer": ["type": "string", "enum": prayerNames, "description": "which prayer"],
                    "on": ["type": "boolean", "description": "true to mark as prayed, false to un-mark; default true"],
                    "date": ["type": "string", "description": "yyyy-MM-dd; omit for today"]
                  ],
                  required: ["prayer"],
                  run: { store, args in proposeTogglePrayer(store, args) })
    ]

    /// The tool list to send a provider. Write tools are omitted entirely when the user has turned
    /// them off — the model cannot call what it cannot see.
    static func tools(writesEnabled: Bool) -> [CoachTool] {
        writesEnabled ? all + writeTools : all
    }

    // MARK: Proposal builders

    @MainActor private static func proposeLogFood(_ store: AppStore, _ args: [String: Any]) -> String {
        let name = AppStore.coachStr(args, "name")
        guard !name.isEmpty else { return "Missing food name \u{2014} nothing proposed." }
        guard let meal = mealArg(args) else { return "Unknown meal \u{2014} use breakfast, snacks, lunch, dinner or drinks." }
        let qty = clamp(AppStore.coachNum(args, "qty", 1), 0.01, 50)
        let kcal = clamp(AppStore.coachNum(args, "kcal", 0), 0, 5000)
        let protein = clamp(AppStore.coachNum(args, "protein", 0), 0, 500)
        let day = store.coachWriteDate(dateArg(args))
        let qtyLabel = qty == 1 ? "" : "\(trim(qty))\u{00d7} "
        var macro = "~\(Int((kcal * qty).rounded())) kcal"
        if protein > 0 { macro += ", \(Int((protein * qty).rounded()))g protein" }
        return store.stageCoachWrite(
            kind: "logFood", date: day,
            summary: "Log \(qtyLabel)\(name) to \(label(meal))\(dayNote(day, store)) (\(macro))",
            payload: ["name": name, "mealKey": meal, "qty": qty, "kcal": kcal, "protein": protein])
    }

    @MainActor private static func proposeRemoveFood(_ store: AppStore, _ args: [String: Any]) -> String {
        let needle = AppStore.coachStr(args, "name").lowercased()
        guard !needle.isEmpty else { return "Missing food name \u{2014} nothing proposed." }
        let day = store.coachWriteDate(dateArg(args))
        let meal = mealArg(args)
        let candidates = store.coachFoodEntries(on: day)
            .filter { meal == nil || $0.mealKey == meal }
            .filter { $0.name.lowercased().contains(needle) }
        guard let hit = candidates.first else {
            return "No logged item matching \u{201c}\(needle)\u{201d} on \(day) \u{2014} nothing proposed."
        }
        let qtyLabel = hit.qty == 1 ? "" : "\(trim(hit.qty))\u{00d7} "
        return store.stageCoachWrite(
            kind: "removeFood", date: day,
            summary: "Remove \(qtyLabel)\(hit.name) from \(label(hit.mealKey))\(dayNote(day, store)) (\u{2212}\(Int(hit.totalKcal.rounded())) kcal)",
            payload: ["foodID": hit.id])
    }

    @MainActor private static func proposeSetMealText(_ store: AppStore, _ args: [String: Any]) -> String {
        guard let meal = mealArg(args) else { return "Unknown meal \u{2014} use breakfast, snacks, lunch, dinner or drinks." }
        let text = AppStore.coachStr(args, "text")
        let day = store.coachWriteDate(dateArg(args))
        let summary = text.isEmpty
            ? "Clear \(label(meal))\(dayNote(day, store))"
            : "Set \(label(meal))\(dayNote(day, store)) to \u{201c}\(String(text.prefix(120)))\u{201d}"
        return store.stageCoachWrite(kind: "setMealText", date: day, summary: summary,
                                     payload: ["mealKey": meal, "text": String(text.prefix(400))])
    }

    @MainActor private static func proposeSetMealTime(_ store: AppStore, _ args: [String: Any]) -> String {
        guard let meal = mealArg(args) else { return "Unknown meal \u{2014} use breakfast, snacks, lunch, dinner or drinks." }
        let day = store.coachWriteDate(dateArg(args))
        let clear = (args["clear"] as? Bool) ?? false
        if clear {
            return store.stageCoachWrite(kind: "setMealTime", date: day,
                                         summary: "Clear the time on \(label(meal))\(dayNote(day, store))",
                                         payload: ["mealKey": meal, "clear": true])
        }
        let raw = AppStore.coachStr(args, "time")
        guard let minutes = AppStore.coachMinutesOfDay(raw) else {
            return "Couldn\u{2019}t read \u{201c}\(raw)\u{201d} as a time \u{2014} nothing proposed. Use 24-hour HH:mm."
        }
        let hhmm = String(format: "%02d:%02d", minutes / 60, minutes % 60)
        return store.stageCoachWrite(kind: "setMealTime", date: day,
                                     summary: "Set \(label(meal))\(dayNote(day, store)) time to \(hhmm)",
                                     payload: ["mealKey": meal, "time": hhmm])
    }

    @MainActor private static func proposeTogglePrayer(_ store: AppStore, _ args: [String: Any]) -> String {
        let name = AppStore.coachStr(args, "prayer").lowercased()
        guard prayerNames.contains(name) else { return "Unknown prayer \u{2014} use fajr, dhuhr, asr, maghrib or isha." }
        let on = (args["on"] as? Bool) ?? true
        let day = store.coachWriteDate(dateArg(args))
        guard store.coachPrayerIsOn(name, on: day) != on else {
            return "\(name.capitalized) is already \(on ? "marked" : "unmarked") on \(day) \u{2014} nothing proposed."
        }
        return store.stageCoachWrite(
            kind: "togglePrayer", date: day,
            summary: "\(on ? "Mark" : "Un-mark") \(name.capitalized)\(dayNote(day, store))\(on ? " as prayed" : "")",
            payload: ["prayer": name, "on": on])
    }

    // MARK: Small helpers

    private static func mealArg(_ args: [String: Any]) -> String? {
        let k = AppStore.coachStr(args, "mealKey").lowercased()
        if mealKeys.contains(k) { return k }
        if k == "snack" { return "snacks" }
        if k == "drink" || k == "beverages" { return "drinks" }
        return nil
    }
    private static func label(_ mealKey: String) -> String {
        mealKey == "drinks" ? "drinks" : mealKey
    }
    /// Names the day only when it isn't the day the app is currently showing — keeps the card short.
    @MainActor private static func dayNote(_ day: String, _ store: AppStore) -> String {
        day == store.date ? "" : " on \(day)"
    }
    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { Swift.max(lo, Swift.min(hi, v)) }
    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2g", v)
    }
}
