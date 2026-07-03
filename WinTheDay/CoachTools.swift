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

        CoachTool(name: "getHealthIndex", description: "Get the user's health profile: latest body composition, recent labs, and health notes (conditions/meds/injuries/goals).",
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
