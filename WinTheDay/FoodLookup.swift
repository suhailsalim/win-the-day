import Foundation

/// A resolved food candidate from any tier of the lookup chain, ready to become a `FoodEntry`.
struct FoodMatch: Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var servingLabel: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sodium: Double = 0
    var micros: [Micro] = []
    var source: FoodSource

    func toEntry(mealKey: String, qty: Double = 1) -> FoodEntry {
        FoodEntry(mealKey: mealKey, name: name, qty: qty, servingLabel: servingLabel,
                  kcal: kcal, protein: protein, carbs: carbs, fat: fat, fiber: fiber,
                  sodium: sodium, micros: micros, source: source)
    }
}

/// The four-tier lookup chain: user library → bundled DB → Open Food Facts → (LLM, owned by AppStore).
/// The first two tiers are offline & synchronous, so search-as-you-type and re-logging a known food
/// NEVER hit the network or the LLM — that's the "no AI if it's already known" guarantee.
enum FoodLookup {
    /// Tier 1 + 2: the user's own library, then the bundled curated DB. Offline.
    static func local(_ query: String, catalog: [CatalogItem]) -> [FoodMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        var out: [FoodMatch] = []

        // Tier 1 — user library (highest trust). Match name substring.
        for item in catalog where item.name.lowercased().contains(q) || q.contains(item.name.lowercased()) {
            out.append(FoodMatch(name: item.name, servingLabel: item.serving,
                                 kcal: item.calories, protein: item.protein, carbs: item.carbs,
                                 fat: item.fat, fiber: item.fiber, micros: item.micros, source: .user))
        }
        // Tier 2 — bundled DB.
        for it in FoodDatabase.search(q) {
            // Skip if the library already covered this name closely.
            if out.contains(where: { $0.name.lowercased() == it.name.lowercased() }) { continue }
            out.append(FoodMatch(name: it.name, servingLabel: it.serving, kcal: it.kcal,
                                 protein: it.protein, carbs: it.carbs, fat: it.fat, fiber: it.fiber,
                                 sodium: it.sodium, source: .curated))
        }
        return Array(out.prefix(10))
    }

    /// Tier 3: Open Food Facts text search (network). Only called on explicit "search online",
    /// never as-you-type, so there's no request storm. Values are per-serving when OFF provides a
    /// serving size, else per-100g.
    static func off(_ query: String) async -> [FoodMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2,
              let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&search_simple=1&action=process&json=1&page_size=6&fields=product_name,brands,nutriments,serving_size")
        else { return [] }
        var req = URLRequest(url: url)
        req.setValue("WinTheDay/1.0 (personal health app)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = obj["products"] as? [[String: Any]] else { return [] }

        var out: [FoodMatch] = []
        for p in products {
            var name = (p["product_name"] as? String) ?? ""
            if name.isEmpty { name = (p["brands"] as? String) ?? "" }
            guard !name.isEmpty else { continue }
            let nutr = p["nutriments"] as? [String: Any] ?? [:]
            func num(_ k: String) -> Double {
                if let v = nutr[k] as? Double { return v }
                if let v = nutr[k] as? Int { return Double(v) }
                if let v = nutr[k] as? String { return Double(v) ?? 0 }
                return 0
            }
            let perServing = num("energy-kcal_serving") > 0
            func pick(_ base: String) -> Double { perServing && num("\(base)_serving") > 0 ? num("\(base)_serving") : num("\(base)_100g") }
            let kcal = pick("energy-kcal")
            guard kcal > 0 else { continue }
            var sodium = pick("sodium")
            if sodium > 0 && sodium < 2 { sodium *= 1000 }   // OFF stores grams; show mg
            out.append(FoodMatch(name: String(name.prefix(48)),
                                 servingLabel: (p["serving_size"] as? String) ?? (perServing ? "1 serving" : "100 g"),
                                 kcal: kcal.rounded(), protein: pick("proteins").rounded(),
                                 carbs: pick("carbohydrates").rounded(), fat: pick("fat").rounded(),
                                 fiber: pick("fiber").rounded(), sodium: sodium.rounded(), source: .off))
        }
        return out
    }
}
