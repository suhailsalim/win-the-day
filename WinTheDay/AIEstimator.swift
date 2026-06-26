import Foundation

enum AIError: LocalizedError {
    case noKey
    case unsupported
    case http(Int, String)
    case badResponse
    case appleNoVision
    case appleUnavailable

    var errorDescription: String? {
        switch self {
        case .noKey: return "No API key set for this provider. Add one in Settings → Intelligence."
        case .unsupported: return "This provider isn\u{2019}t available — pick another in Settings."
        case .http(let code, let msg): return "Provider error \(code): \(msg)"
        case .badResponse: return "The estimator returned something unexpected."
        case .appleNoVision: return "Apple Intelligence runs on-device and can\u{2019}t read photos yet. Pick a cloud provider (Settings → Intelligence) to scan labels & reports."
        case .appleUnavailable: return "Apple Intelligence isn\u{2019}t available on this device. Enable Apple Intelligence in iOS Settings, or pick a cloud provider."
        }
    }
}

/// Routes completion / vision requests to the selected provider's REST API.
struct AIEstimator {

    // MARK: - Public tasks

    func estimate(meals: Meals, knownFoods: [CatalogItem], settings: AppSettings) async throws -> AIResult {
        let text = try await complete(prompt: Self.estimatePrompt(for: meals, knownFoods: knownFoods),
                                      imageBase64: nil, settings: settings, jsonOnly: true)
        guard let result = Self.parseResult(text) else { throw AIError.badResponse }
        return result
    }

    /// Parse an InBody / body-composition report (photo and/or text).
    func parseBodyComp(text: String?, imageBase64: String?, settings: AppSettings) async throws -> BodyComp {
        let prompt = """
        You are reading an InBody / body-composition report. Extract the figures.
        \(text.map { "Notes: \($0)" } ?? "")
        Respond with ONLY this JSON, numbers only (omit a key if absent):
        {"weight":0,"bodyFat":0,"leanMass":0,"skeletalMuscle":0,"bmi":0,"visceralFat":0}
        weight & leanMass & skeletalMuscle in kg, bodyFat in %, visceralFat as the level number.
        """
        let out = try await complete(prompt: prompt, imageBase64: imageBase64, settings: settings, jsonOnly: true)
        guard let o = Self.parseObject(out) else { throw AIError.badResponse }
        func n(_ k: String) -> Double? { let v = num(o[k]); return v > 0 ? v : nil }
        return BodyComp(date: "", weight: n("weight"), bodyFat: n("bodyFat"), leanMass: n("leanMass"),
                        skeletalMuscle: n("skeletalMuscle"), bmi: n("bmi"), visceralFat: n("visceralFat"))
    }

    /// Parse a health-checkup / lab report into a list of measurements.
    func parseLabs(text: String?, imageBase64: String?, settings: AppSettings) async throws -> (title: String, items: [LabItem]) {
        let prompt = """
        You are reading a medical lab / health-checkup report. Extract every numeric test result.
        \(text.map { "Notes: \($0)" } ?? "")
        Respond with ONLY this JSON:
        {"title":"e.g. Lipid panel / Full checkup","items":[{"name":"Total Cholesterol","value":0,"unit":"mg/dL"}]}
        Use the report's units. Numbers only for value. Include every result you can read.
        """
        let out = try await complete(prompt: prompt, imageBase64: imageBase64, settings: settings, jsonOnly: true)
        guard let o = Self.parseObject(out) else { throw AIError.badResponse }
        let title = (o["title"] as? String) ?? "Lab report"
        let rawItems = (o["items"] as? [[String: Any]]) ?? []
        let items: [LabItem] = rawItems.compactMap { d in
            guard let name = d["name"] as? String else { return nil }
            return LabItem(name: name, value: num(d["value"]), unit: (d["unit"] as? String) ?? "")
        }
        return (title, items)
    }

    /// Parse a nutrition label (photo) and/or free text into a catalog item.
    func parseItem(kind: CatalogKind, text: String?, imageBase64: String?,
                   settings: AppSettings) async throws -> CatalogItem {
        let out = try await complete(prompt: Self.parsePrompt(kind: kind, text: text, hasImage: imageBase64 != nil),
                                     imageBase64: imageBase64, settings: settings, jsonOnly: true)
        guard let obj = Self.parseObject(out) else { throw AIError.badResponse }
        return CatalogItem(
            kind: kind,
            name: (obj["name"] as? String) ?? (text ?? "New item"),
            serving: (obj["serving"] as? String) ?? "",
            calories: num(obj["calories"]),
            protein: num(obj["protein"]),
            carbs: num(obj["carbs"]),
            fat: num(obj["fat"]),
            fiber: num(obj["fiber"]),
            micros: parseMicros(obj["micros"])
        )
    }

    private func parseMicros(_ v: Any?) -> [Micro] {
        guard let arr = v as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let name = d["name"] as? String, !name.isEmpty else { return nil }
            let amount = num(d["amount"])
            guard amount > 0 else { return nil }
            return Micro(name: name, amount: amount, unit: (d["unit"] as? String) ?? "")
        }
    }

    /// Round-trips a trivial prompt to verify the provider, model, key/host all work.
    /// Returns a short echo of what the model replied; throws an `AIError` on failure.
    func testConnection(settings: AppSettings) async throws -> String {
        let reply = try await complete(
            prompt: "Reply with exactly the two words: connection ok",
            imageBase64: nil, settings: settings, jsonOnly: false)
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.badResponse }
        return String(trimmed.prefix(80))
    }

    /// Generate a prep plan for an occasion (gift/celebration ideas, a checklist, and for
    /// travel a day-by-day itinerary). `pasted` can carry a booking confirmation to parse.
    func planOccasion(title: String, type: String, person: String, location: String,
                      dateText: String, pasted: String?, settings: AppSettings)
                      async throws -> (checklist: [String], ideas: [String], itinerary: [ItineraryItem]) {
        let isTravel = type == "travel"
        var lines = [
            "You are a thoughtful personal planner. Help the user prepare for this occasion.",
            "Occasion: \(title) (type: \(type))" + (person.isEmpty ? "" : ", for \(person)")
                + (location.isEmpty ? "" : ", at \(location)") + (dateText.isEmpty ? "" : ", on \(dateText)")
        ]
        if let pasted, !pasted.isEmpty { lines.append("Booking / details provided:\n\(pasted)") }
        if isTravel {
            lines.append("Build a practical day-by-day itinerary AND a packing/prep checklist. Keep items short and actionable.")
        } else {
            lines.append("Suggest a few gift/celebration ideas AND a short prep checklist (booking, ordering, messages). Keep items short and actionable.")
        }
        lines.append("""
        Respond with ONLY this JSON, no prose or markdown:
        {"ideas":["..."],"checklist":["..."],"itinerary":[{"date":"yyyy-MM-dd or empty","title":"short","detail":"short"}]}
        Use at most 6 ideas, 8 checklist items, 8 itinerary items. Leave itinerary empty for non-travel.
        """)
        let out = try await complete(prompt: lines.joined(separator: "\n\n"), imageBase64: nil, settings: settings, jsonOnly: true)
        guard let obj = Self.parseObject(out) else { throw AIError.badResponse }
        let ideas = (obj["ideas"] as? [String]) ?? []
        let checklist = (obj["checklist"] as? [String]) ?? []
        let rawItinerary = (obj["itinerary"] as? [[String: Any]]) ?? []
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
        let itinerary: [ItineraryItem] = rawItinerary.compactMap { d in
            guard let t = d["title"] as? String, !t.isEmpty else { return nil }
            let epoch = (d["date"] as? String).flatMap { df.date(from: $0) }?.timeIntervalSince1970 ?? 0
            return ItineraryItem(dateEpoch: epoch, title: t, detail: (d["detail"] as? String) ?? "")
        }
        return (checklist, ideas, itinerary)
    }

    /// Generate a balanced week plan as schedulable blocks. `context` carries the user's
    /// routine, targets, health profile, readiness trend and upcoming calendar commitments.
    func generateWeekPlan(context: String, settings: AppSettings) async throws -> [PlanBlock] {
        let prompt = """
        You are an expert performance coach + scheduler. Build the user a realistic 7-day plan starting today (day 0 = today … day 6).

        \(context)

        Plan these block kinds as relevant: workout, pt, run, walk, strength, focus, work, stretch, cooldown, winddown, meal. Rules:
        - Work AROUND the listed calendar commitments and prayer times — never overlap them.
        - Balance load: lighter or rest the day after a hard session or a low-readiness day; don't stack two hard days.
        - Every training day: a short morning day-starter stretch and a post-workout cooldown.
        - Every day: an evening wind-down ~45 min before a sensible bedtime, plus walk reminders and consistent meal times.
        - Keep it achievable, not overwhelming.

        Respond with ONLY this JSON, no prose or markdown:
        {"blocks":[{"day":0,"start":"07:00","durationMin":15,"kind":"stretch","title":"Morning mobility","note":"short","remind":true}]}
        Use 24h "HH:mm". Aim for 4–8 blocks per day. Titles short.
        """
        let out = try await complete(prompt: prompt, imageBase64: nil, settings: settings, jsonOnly: true)
        guard let obj = Self.parseObject(out) else { throw AIError.badResponse }
        let raw = (obj["blocks"] as? [[String: Any]]) ?? []
        return raw.compactMap { d in
            guard let kind = d["kind"] as? String else { return nil }
            let start = (d["start"] as? String) ?? "07:00"
            let comps = start.split(separator: ":")
            let hour = comps.first.flatMap { Int($0) } ?? 7
            let minute = comps.count > 1 ? (Int(comps[1]) ?? 0) : 0
            var b = PlanBlock()
            b.day = max(0, min(6, Int(num(d["day"]))))
            b.hour = max(0, min(23, hour)); b.minute = max(0, min(59, minute))
            b.durationMin = max(5, Int(num(d["durationMin"])))
            b.kind = kind
            b.title = (d["title"] as? String) ?? ""
            b.note = (d["note"] as? String) ?? ""
            b.remind = (d["remind"] as? Bool) ?? true
            return b
        }
    }

    /// Multi-turn coach chat. The system preamble + prior turns are folded into one prompt
    /// so every provider (incl. Apple/Ollama) works without per-provider message-array handling.
    func chat(system: String, history: [ChatMessage], settings: AppSettings) async throws -> String {
        var lines = [system, ""]
        for m in history {
            lines.append("\(m.isUser ? "User" : "Coach"): \(m.text)")
        }
        lines.append("Coach:")
        let prompt = lines.joined(separator: "\n")
        let text = try await complete(prompt: prompt, imageBase64: nil, settings: settings, jsonOnly: false)
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("Coach:") { out = String(out.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        return out
    }

    /// A short, time-aware nudge for the home screen.
    func suggest(prompt: String, settings: AppSettings) async throws -> String {
        let text = try await complete(prompt: prompt, imageBase64: nil, settings: settings, jsonOnly: false)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
    }

    private func num(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }

    // MARK: - Prompts

    static func estimatePrompt(for m: Meals, knownFoods: [CatalogItem]) -> String {
        func v(_ s: String) -> String { s.isEmpty ? "(none)" : s }
        var library = ""
        if !knownFoods.isEmpty {
            let lines = knownFoods.prefix(40).map { f in
                "- \(f.name)\(f.serving.isEmpty ? "" : " (\(f.serving))"): \(Int(f.calories)) kcal, P\(Int(f.protein)) C\(Int(f.carbs)) F\(Int(f.fat))"
            }.joined(separator: "\n")
            library = """

            KNOWN FOODS LIBRARY — these are the user\u{2019}s own dishes with verified values from how THEY cook/portion. If a meal matches one of these (even loosely, e.g. \u{201C}home omlette\u{201D} → \u{201C}Home omelette\u{201D}), USE these exact values instead of guessing:
            \(lines)
            """
        }
        return """
        You are a nutrition estimator for everyday Kerala / South Indian home cooking. Estimate calories and macros for this day's meals. These are Indian foods — give ±10–15% ballpark estimates and flag big-swing items in the note. Be concise.
        \(library)

        Breakfast: \(v(m.breakfast))
        Snacks: \(v(m.snacks))
        Lunch: \(v(m.lunch))
        Dinner: \(v(m.dinner))
        Drinks/supplements: \(v(m.drinks))

        Also estimate the day's key vitamins & minerals (sodium, calcium, iron, potassium, vitamin C, etc.) in total.micros with real units.

        Respond with ONLY a JSON object, no prose, no markdown fences, exactly:
        {"meals":[{"label":"Breakfast","calories":0,"protein":0,"carbs":0,"fat":0,"fiber":0,"note":"short"}],"total":{"calories":0,"protein":0,"carbs":0,"fat":0,"fiber":0,"micros":[{"name":"Sodium","amount":0,"unit":"mg"}]}}
        Only include meals with content. Whole numbers. When you used a known-food value, say so in its note.
        """
    }

    static func parsePrompt(kind: CatalogKind, text: String?, hasImage: Bool) -> String {
        let kindWord = kind == .supplement ? "supplement" : "food"
        var lines = [
            "You are a nutrition extractor. Identify a single \(kindWord) and its per-serving nutrition."
        ]
        if hasImage { lines.append("A photo of a nutrition / supplement facts label is attached — read it.") }
        if let text, !text.isEmpty { lines.append("User description: \(text)") }
        lines.append("""
        Use the label's stated serving size. If the label gives per-100g and a serving size, convert to per serving. For Indian / home foods with no label, give a sensible per-serving estimate. Include any vitamins & minerals you can read or reasonably estimate (e.g. fiber, sugar, sodium, calcium, iron, potassium, vitamin D, B12, etc.) in the micros array with their real units.

        Respond with ONLY this JSON, no prose, no markdown:
        {"name":"short name","serving":"e.g. 1 scoop (30g)","calories":0,"protein":0,"carbs":0,"fat":0,"fiber":0,"micros":[{"name":"Sodium","amount":0,"unit":"mg"},{"name":"Vitamin D","amount":0,"unit":"mcg"}]}
        Numbers only for amounts. Omit micros you can't determine.
        """)
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Tolerant JSON parsing

    static func parseResult(_ text: String) -> AIResult? {
        guard let data = sliceJSON(text)?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIResult.self, from: data)
    }

    static func parseObject(_ text: String) -> [String: Any]? {
        guard let data = sliceJSON(text)?.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func sliceJSON(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: #"```(?:json)?([\s\S]*?)```"#, options: .regularExpression) {
            t = String(t[r])
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}"), a < b {
            return String(t[a...b])
        }
        return t
    }

    // MARK: - Provider routing

    private func complete(prompt: String, imageBase64: String?, settings: AppSettings, jsonOnly: Bool) async throws -> String {
        let apiModel = Providers.apiModelID(provider: settings.provider, model: settings.model, custom: settings.customModel)
        switch settings.provider {
        case "anthropic": return try await anthropic(prompt: prompt, image: imageBase64, model: apiModel)
        case "openai":    return try await openAICompatible(base: "https://api.openai.com/v1", keyName: "openai",
                                                            prompt: prompt, image: imageBase64, model: apiModel)
        case "gemini":    return try await gemini(prompt: prompt, image: imageBase64, model: apiModel, jsonOnly: jsonOnly)
        case "apple":     return try await AppleIntelligence.complete(prompt: prompt, hasImage: imageBase64 != nil)
        case "deepseek":  return try await openAICompatible(base: "https://api.deepseek.com/v1", keyName: "deepseek",
                                                            prompt: prompt, image: nil, model: apiModel)  // text only
        case "ollamacloud": return try await openAICompatible(base: "https://ollama.com/v1", keyName: "ollamacloud",
                                                              prompt: prompt, image: imageBase64, model: apiModel)
        case "openrouter":
            return try await openAICompatible(base: "https://openrouter.ai/api/v1", keyName: "openrouter",
                                              prompt: prompt, image: imageBase64, model: apiModel,
                                              extraHeaders: ["HTTP-Referer": "https://wintheday.app",
                                                             "X-Title": "Win the Day"])
        case "ollama":
            let host = settings.ollamaHost.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !host.isEmpty else { throw AIError.noKey }
            return try await openAICompatible(base: host + "/v1", keyName: nil,
                                              prompt: prompt, image: imageBase64, model: apiModel)
        default:          throw AIError.unsupported
        }
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(http.statusCode, String(body.prefix(300)))
        }
        return data
    }

    // MARK: - Anthropic

    private func anthropic(prompt: String, image: String?, model: String) async throws -> String {
        let key = Keychain.get("anthropic")
        guard !key.isEmpty else { throw AIError.noKey }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        if let image {
            content.insert(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": image]], at: 0)
        }
        let body: [String: Any] = [
            "model": model, "max_tokens": 1024,
            "messages": [["role": "user", "content": content]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["content"] as? [[String: Any]],
              let text = arr.first?["text"] as? String else { throw AIError.badResponse }
        return text
    }

    // MARK: - OpenAI-compatible (OpenAI, OpenRouter, DeepSeek, Ollama)

    /// Calls any `/chat/completions` endpoint that follows the OpenAI schema.
    /// `keyName` is the Keychain id for the bearer token, or `nil` for keyless servers (Ollama).
    private func openAICompatible(base: String, keyName: String?, prompt: String, image: String?,
                                  model: String, extraHeaders: [String: String] = [:]) async throws -> String {
        guard let url = URL(string: base + "/chat/completions") else { throw AIError.unsupported }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let keyName {
            let key = Keychain.get(keyName)
            guard !key.isEmpty else { throw AIError.noKey }
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        for (h, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: h) }

        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        if let image {
            content.append(["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(image)"]])
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": content]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let text = msg["content"] as? String else { throw AIError.badResponse }
        return text
    }

    // MARK: - Gemini

    private func gemini(prompt: String, image: String?, model: String, jsonOnly: Bool) async throws -> String {
        let key = Keychain.get("gemini")
        guard !key.isEmpty else { throw AIError.noKey }
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var parts: [[String: Any]] = [["text": prompt]]
        if let image {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": image]])
        }
        var body: [String: Any] = ["contents": [["parts": parts]]]
        if jsonOnly { body["generationConfig"] = ["responseMimeType": "application/json"] }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts2 = content["parts"] as? [[String: Any]],
              let text = parts2.first?["text"] as? String else { throw AIError.badResponse }
        return text
    }
}
