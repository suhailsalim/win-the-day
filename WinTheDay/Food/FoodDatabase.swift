import Foundation

/// One row of the bundled starter food DB (`FoodDB.json`). Per-serving nutrition.
struct FoodDBItem: Codable, Identifiable, Equatable {
    var name: String
    var aliases: [String] = []
    var serving: String = ""
    var grams: Double = 0
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sodium: Double = 0
    var kind: String = "food"     // food | drink | supplement
    var tags: [String] = []       // meal tags
    var id: String { name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        aliases = (try? c.decode([String].self, forKey: .aliases)) ?? []
        serving = (try? c.decode(String.self, forKey: .serving)) ?? ""
        grams = (try? c.decode(Double.self, forKey: .grams)) ?? 0
        kcal = (try? c.decode(Double.self, forKey: .kcal)) ?? 0
        protein = (try? c.decode(Double.self, forKey: .protein)) ?? 0
        carbs = (try? c.decode(Double.self, forKey: .carbs)) ?? 0
        fat = (try? c.decode(Double.self, forKey: .fat)) ?? 0
        fiber = (try? c.decode(Double.self, forKey: .fiber)) ?? 0
        sodium = (try? c.decode(Double.self, forKey: .sodium)) ?? 0
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "food"
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
    }

    func toFoodEntry(mealKey: String) -> FoodEntry {
        FoodEntry(mealKey: mealKey, name: name, qty: 1, servingLabel: serving,
                  kcal: kcal, protein: protein, carbs: carbs, fat: fat, fiber: fiber,
                  sodium: sodium, source: .curated)
    }
}

/// Loads the bundled, read-only starter food database once and offers offline substring search.
/// Small enough (~a few dozen foods) to keep in memory as JSON; a full USDA import would swap this
/// for an on-disk SQLite/FTS index behind the same `search` API.
enum FoodDatabase {
    private static let items: [FoodDBItem] = {
        guard let url = Bundle.main.url(forResource: "FoodDB", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let db = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return db.foods
    }()
    private struct Payload: Codable { var foods: [FoodDBItem] = [] }

    static var count: Int { items.count }

    /// Best matches for a query — exact name/alias first, then substring, ranked by how early the
    /// match starts. Returns [] when nothing plausible matches (so callers fall through the chain).
    static func search(_ query: String, limit: Int = 8) -> [FoodDBItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        var scored: [(FoodDBItem, Int)] = []
        for it in items {
            let hay = ([it.name] + it.aliases).map { $0.lowercased() }
            if hay.contains(q) {
                scored.append((it, 0))                                   // exact name/alias
            } else if hay.contains(where: { $0.hasPrefix(q) }) {
                scored.append((it, 1))                                   // prefix match
            } else if hay.contains(where: { $0.contains(q) }) {
                scored.append((it, 2))                                   // substring match
            } else if hay.contains(where: { $0.count >= 3 && q.contains($0) }) {
                scored.append((it, 3))                                   // query ⊇ entry ("2 dosas" ⊇ "dosa")
            }
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map { $0.0 }
    }
}
