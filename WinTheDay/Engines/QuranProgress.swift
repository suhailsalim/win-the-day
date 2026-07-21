import Foundation

/// Qur'an reading progress — the khatmah plan and the position tables behind it.
///
/// Same shape as `ScoreEngine`/`RingEngine`/`Milestones`: pure, Foundation-only, deterministic. The
/// caller (`AppStore`) owns the entries and the persistence; this file only knows pages in → plan
/// state out.
///
/// **No Qur'anic text or translation is bundled** — only the standard 604-page Madani (King Fahd)
/// pagination as public factual reference data, so a page number can be shown as "Juz' 12 · Hud".
/// This tracks progress; it is not a mushaf.

// MARK: - Persisted plan

/// One khatmah ("finish the whole Qur'an in N days"). Deliberately does **not** store a running
/// page counter: the position is derived as `startPage + Σ Entry.quranPages since the start day`,
/// so editing a past day's pages adjusts the position by the delta instead of double-counting.
/// A counter would drift; a derived value cannot.
struct KhatmahPlan: Codable, Equatable, Sendable {
    var startEpoch: Double = 0              // start of the day the plan began (0 = never started)
    var targetDays: Int = 30                // how many days to finish in
    var startPage: Int = 0                  // pages already behind you when it began (0 = from page 1)
    var completedEpochs: [Double] = []      // archive: when each khatmah on this plan was finished

    init(startEpoch: Double = 0, targetDays: Int = 30, startPage: Int = 0, completedEpochs: [Double] = []) {
        self.startEpoch = startEpoch
        self.targetDays = targetDays
        self.startPage = startPage
        self.completedEpochs = completedEpochs
    }

    /// Tolerant decoding (AGENTS.md convention 1). `AppData` decodes the plan as one whole value,
    /// so a single throwing key here would silently delete the user's entire khatmah.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startEpoch = (try? c.decode(Double.self, forKey: .startEpoch)) ?? 0
        targetDays = (try? c.decode(Int.self, forKey: .targetDays)) ?? 30
        startPage = (try? c.decode(Int.self, forKey: .startPage)) ?? 0
        completedEpochs = (try? c.decode([Double].self, forKey: .completedEpochs)) ?? []
    }

    var startDate: Date? { startEpoch > 0 ? Date(timeIntervalSince1970: startEpoch) : nil }
    /// Clamped views of the stored values — hostile/legacy JSON must never divide by zero or
    /// produce a position outside the mushaf.
    var effectiveTargetDays: Int { max(1, targetDays) }
    var effectiveStartPage: Int { min(max(0, startPage), QuranProgress.totalPages) }
    var timesCompleted: Int { completedEpochs.count }
}

// MARK: - Tables + plan math

enum QuranProgress {
    /// Standard Madani mushaf.
    static let totalPages = 604
    static let juzCount = 30

    /// First page of each juz' in the 604-page Madani layout (index 0 = juz' 1).
    static let juzStartPages: [Int] = [
        1, 22, 42, 62, 82, 102, 121, 142, 162, 182,
        201, 222, 242, 262, 282, 302, 322, 342, 362, 382,
        402, 422, 442, 462, 482, 502, 522, 542, 562, 582
    ]

    /// First page of each surah (number, transliterated name, start page). Non-decreasing — the
    /// short surahs share pages, so a lookup takes the *last* surah that starts on or before a page.
    static let surahStartPages: [(number: Int, name: String, page: Int)] = [
        (1, "Al-Fatihah", 1), (2, "Al-Baqarah", 2), (3, "Al-'Imran", 50), (4, "An-Nisa", 77),
        (5, "Al-Ma'idah", 106), (6, "Al-An'am", 128), (7, "Al-A'raf", 151), (8, "Al-Anfal", 177),
        (9, "At-Tawbah", 187), (10, "Yunus", 208), (11, "Hud", 221), (12, "Yusuf", 235),
        (13, "Ar-Ra'd", 249), (14, "Ibrahim", 255), (15, "Al-Hijr", 262), (16, "An-Nahl", 267),
        (17, "Al-Isra", 282), (18, "Al-Kahf", 293), (19, "Maryam", 305), (20, "Ta-Ha", 312),
        (21, "Al-Anbiya", 322), (22, "Al-Hajj", 332), (23, "Al-Mu'minun", 342), (24, "An-Nur", 350),
        (25, "Al-Furqan", 359), (26, "Ash-Shu'ara", 367), (27, "An-Naml", 377), (28, "Al-Qasas", 385),
        (29, "Al-'Ankabut", 396), (30, "Ar-Rum", 404), (31, "Luqman", 411), (32, "As-Sajdah", 415),
        (33, "Al-Ahzab", 418), (34, "Saba", 428), (35, "Fatir", 434), (36, "Ya-Sin", 440),
        (37, "As-Saffat", 446), (38, "Sad", 453), (39, "Az-Zumar", 458), (40, "Ghafir", 467),
        (41, "Fussilat", 477), (42, "Ash-Shura", 483), (43, "Az-Zukhruf", 489), (44, "Ad-Dukhan", 496),
        (45, "Al-Jathiyah", 499), (46, "Al-Ahqaf", 502), (47, "Muhammad", 507), (48, "Al-Fath", 511),
        (49, "Al-Hujurat", 515), (50, "Qaf", 518), (51, "Adh-Dhariyat", 520), (52, "At-Tur", 523),
        (53, "An-Najm", 526), (54, "Al-Qamar", 528), (55, "Ar-Rahman", 531), (56, "Al-Waqi'ah", 534),
        (57, "Al-Hadid", 537), (58, "Al-Mujadila", 542), (59, "Al-Hashr", 545), (60, "Al-Mumtahanah", 549),
        (61, "As-Saff", 551), (62, "Al-Jumu'ah", 553), (63, "Al-Munafiqun", 554), (64, "At-Taghabun", 556),
        (65, "At-Talaq", 558), (66, "At-Tahrim", 560), (67, "Al-Mulk", 562), (68, "Al-Qalam", 564),
        (69, "Al-Haqqah", 566), (70, "Al-Ma'arij", 568), (71, "Nuh", 570), (72, "Al-Jinn", 572),
        (73, "Al-Muzzammil", 574), (74, "Al-Muddaththir", 575), (75, "Al-Qiyamah", 577), (76, "Al-Insan", 578),
        (77, "Al-Mursalat", 580), (78, "An-Naba", 582), (79, "An-Nazi'at", 583), (80, "'Abasa", 585),
        (81, "At-Takwir", 586), (82, "Al-Infitar", 587), (83, "Al-Mutaffifin", 587), (84, "Al-Inshiqaq", 589),
        (85, "Al-Buruj", 590), (86, "At-Tariq", 591), (87, "Al-A'la", 591), (88, "Al-Ghashiyah", 592),
        (89, "Al-Fajr", 593), (90, "Al-Balad", 594), (91, "Ash-Shams", 595), (92, "Al-Layl", 595),
        (93, "Ad-Duha", 596), (94, "Ash-Sharh", 596), (95, "At-Tin", 597), (96, "Al-'Alaq", 597),
        (97, "Al-Qadr", 598), (98, "Al-Bayyinah", 598), (99, "Az-Zalzalah", 599), (100, "Al-'Adiyat", 599),
        (101, "Al-Qari'ah", 600), (102, "At-Takathur", 600), (103, "Al-'Asr", 601), (104, "Al-Humazah", 601),
        (105, "Al-Fil", 601), (106, "Quraysh", 602), (107, "Al-Ma'un", 602), (108, "Al-Kawthar", 602),
        (109, "Al-Kafirun", 603), (110, "An-Nasr", 603), (111, "Al-Masad", 603), (112, "Al-Ikhlas", 604),
        (113, "Al-Falaq", 604), (114, "An-Nas", 604)
    ]

    /// Which juz' a page falls in (1...30). Pages before the mushaf starts read as juz' 1.
    static func juz(forPage page: Int) -> Int {
        let p = min(max(1, page), totalPages)
        var result = 1
        for (i, start) in juzStartPages.enumerated() where start <= p { result = i + 1 }
        return result
    }

    /// The surah a page belongs to — the last one starting on or before it.
    static func surah(forPage page: Int) -> (number: Int, name: String, page: Int)? {
        let p = min(max(1, page), totalPages)
        var result: (number: Int, name: String, page: Int)?
        for s in surahStartPages where s.page <= p { result = s }
        return result
    }

    /// "Juz' 12 · Hud · p. 231" — a position label only, never any text of the page itself.
    static func positionLabel(page: Int) -> String {
        guard page > 0 else { return "Not started yet" }
        let p = min(page, totalPages)
        let name = surah(forPage: p)?.name ?? ""
        return "Juz' \(juz(forPage: p))\(name.isEmpty ? "" : " · \(name)") · p. \(p)"
    }

    /// Pages per juz' on average (604/30 ≈ 20.1) — used only to show a juz' equivalent next to a
    /// page count. There is one data model (pages); juz' is a presentation of it.
    static let pagesPerJuz = Double(totalPages) / Double(juzCount)
    static func juzEquivalent(pages: Int) -> Double { Double(max(0, pages)) / pagesPerJuz }
    /// Pages in one juz', rounded up — what a "+1 juz'" button logs.
    static var pagesInOneJuz: Int { Int(pagesPerJuz.rounded()) }

    /// The plan's flat pace: what it asks for per day if no day is ever missed. O(1), which is why
    /// habit satisfaction uses it rather than the redistributed daily target.
    static func flatDailyPages(_ plan: KhatmahPlan) -> Int {
        let toRead = max(0, totalPages - plan.effectiveStartPage)
        guard toRead > 0 else { return 0 }
        return ceilDiv(toRead, plan.effectiveTargetDays)
    }

    // MARK: - Status

    /// Everything the card needs for one day of a plan. Never persisted, recomputed on demand.
    struct Status: Equatable, Sendable {
        var currentPage: Int        // 0...604, derived; 0 = nothing read yet
        var pagesRead: Int          // total logged since the plan started
        var pagesRemaining: Int     // to 604
        var pagesToday: Int
        var dailyTarget: Int        // pages asked of *today*, fixed at the start of the day
        var remainingToday: Int     // max(0, dailyTarget - pagesToday)
        var dayNumber: Int          // 1-based day of the plan
        var daysRemaining: Int      // including today; 0 once the target date has passed
        var fraction: Double        // 0...1 through the mushaf
        var paceDelta: Int          // pages ahead (+) / behind (−) the flat pace by end of today
        var flatDailyPages: Int
        var isComplete: Bool
    }

    /// Plan state for one day.
    ///
    /// - `pagesBeforeToday`: pages logged on days from the plan start up to (not including) this day.
    /// - `pagesToday`: pages logged on this day.
    /// - `dayIndex`: whole days since the plan started (0 on the start day).
    ///
    /// `dailyTarget` is computed from the position **at the start of the day** and re-derived every
    /// day, so missed days redistribute forward into the days that are left and reading extra today
    /// lowers tomorrow's ask. Past the target date everything remaining lands on today rather than
    /// dividing by zero — the plan heals itself, it never scolds about the past.
    static func status(plan: KhatmahPlan, pagesBeforeToday: Int, pagesToday: Int, dayIndex: Int) -> Status {
        let start = plan.effectiveStartPage
        let target = plan.effectiveTargetDays
        let idx = max(0, dayIndex)
        let before = max(0, pagesBeforeToday)
        let today = max(0, pagesToday)

        let atDayStart = min(totalPages, start + before)
        let currentPage = min(totalPages, atDayStart + today)
        let remainingAtDayStart = totalPages - atDayStart
        let daysLeftIncludingToday = max(1, target - idx)
        let dailyTarget = remainingAtDayStart > 0 ? ceilDiv(remainingAtDayStart, daysLeftIncludingToday) : 0

        let flat = flatDailyPages(plan)
        let toRead = max(0, totalPages - start)
        // Surplus counts: reading past the daily ask shows up as "ahead", it is never clipped.
        let expectedByTonight = min(toRead, flat * (idx + 1))
        let paceDelta = (before + today) - expectedByTonight

        return Status(currentPage: currentPage,
                      pagesRead: before + today,
                      pagesRemaining: max(0, totalPages - currentPage),
                      pagesToday: today,
                      dailyTarget: dailyTarget,
                      remainingToday: max(0, dailyTarget - today),
                      dayNumber: idx + 1,
                      daysRemaining: max(0, target - idx),
                      fraction: min(1, max(0, Double(currentPage) / Double(totalPages))),
                      paceDelta: paceDelta,
                      flatDailyPages: flat,
                      isComplete: currentPage >= totalPages)
    }

    private static func ceilDiv(_ a: Int, _ b: Int) -> Int {
        guard b > 0 else { return a }
        return (a + b - 1) / b
    }
}
