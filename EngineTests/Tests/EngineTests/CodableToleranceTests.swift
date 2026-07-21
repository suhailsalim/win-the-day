import XCTest
@testable import AppCore

/// Guards the project's #1 stated risk (AGENTS.md convention 1): every persisted struct has a
/// hand-written tolerant `init(from:)`, and a missing decode line silently wipes real user data.
///
/// Three complementary checks per struct:
///   • **round-trip** — a fully-populated instance survives encode → decode unchanged. Deleting any
///     one `(try? c.decode(…)) ?? default` line makes the corresponding field fall back to its
///     default and fails this test. That is the whole point, so every field is populated with a
///     value that is *not* its default.
///   • **empty object** — `{}` decodes to defaults instead of throwing (the tolerant contract:
///     old saved data written before a field existed must still load).
///   • **wrong types / unknown enum cases** — garbage in one key falls back instead of taking the
///     entire document down with it.
final class CodableToleranceTests: XCTestCase {

    // MARK: - Helpers

    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try JSONEncoder().encode(value)
        let back = try JSONDecoder().decode(T.self, from: data)
        XCTAssertEqual(back, value,
                       "\(T.self) lost data in a JSON round-trip — a stored property is missing its tolerant decode line or its CodingKeys entry.",
                       file: file, line: line)
    }

    private func decodeEmpty<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data("{}".utf8))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Fully-populated fixtures (every field non-default)

    private func filledEntry() -> Entry {
        var e = Entry(date: "2026-03-04")
        e.meals = Meals(breakfast: "eggs", snacks: "apple", lunch: "rice", dinner: "fish", drinks: "whey")
        e.nn = NonNegotiables(fajr: true, protein: true, moved: true, phone: true, side: true)
        e.training = "push day"
        e.run = "5k easy"
        e.weight = "83.1"
        e.steps = "9123"
        e.sms = "7/8/2"
        e.calories = "2210"
        e.proteinG = "134"
        e.ai = AIResult(meals: [AIMeal(label: "lunch", calories: 620, protein: 41, carbs: 70, fat: 18,
                                       fiber: 6, note: "estimated")],
                        total: AITotals(calories: 2210, protein: 134, carbs: 220, fat: 70, fiber: 31,
                                        micros: [Micro(name: "iron", amount: 14, unit: "mg")]))
        e.logged = [LoggedItem(itemID: "cat-1", name: "whey", calories: 120, protein: 25,
                               carbs: 2, fat: 1, fiber: 0.5,
                               micros: [Micro(name: "calcium", amount: 120, unit: "mg")], qty: 2)]
        e.foodEntries = [FoodEntry(mealKey: "dinner", name: "dosa", qty: 3, servingLabel: "1 dosa",
                                   kcal: 133, protein: 3, carbs: 24, fat: 3, fiber: 1.2, sodium: 210,
                                   micros: [Micro(name: "folate", amount: 30, unit: "µg")], source: .usda)]
        e.photos = ["a.jpg", "b.jpg"]
        e.prayers.setOn("fajr", true, at: 1_772_000_000, band: .promptOnTime)
        e.prayers.setOn("isha", true, at: 1_772_050_000, band: .lateValid)
        e.weightFromHealth = true
        e.waterMl = 2400
        // Non-empty on purpose: an empty habitState triggers the legacy non-negotiables migration
        // inside `Entry.init(from:)`, which would legitimately change the decoded value.
        e.habitState = ["moved": true, "phone": false]
        e.activeKcal = 612.5
        e.studyHours = 3.25
        e.studySessions = [StudySession(subject: "anatomy", minutes: 95)]
        e.workouts = [Workout(kind: "cardio", title: "intervals",
                              exercises: [Exercise(name: "row", sets: [StrengthSet(reps: 12, weightKg: 40)])],
                              durationMin: 38, note: "easy")]
        e.mealTimes = ["dinner": 1_772_049_000, "lunch": 1_772_020_000]
        var sleep = SleepBreakdown()
        sleep.asleepMin = 431; sleep.inBedMin = 470; sleep.deepMin = 71; sleep.remMin = 96
        sleep.coreMin = 264; sleep.awakeMin = 39; sleep.bedEpoch = 1_771_970_000
        sleep.wakeEpoch = 1_771_998_200; sleep.efficiency = 0.917; sleep.latencyMin = 14
        e.sleep = sleep
        e.readiness = 71
        e.sleepScore = 84
        e.activeScore = 63
        e.eatingScore = 78
        e.checkIn = filledCheckIn()
        e.status = "travel"
        e.mainFocus = "finish the physiology deck"
        e.mainFocusDone = true
        e.regimenTaken = ["reg-1": ["morning", "evening"], "reg-2": ["night"]]
        e.regimenTakenAt = ["reg-1#morning": 1_772_001_100, "reg-1#evening": 1_772_045_000]
        return e
    }

    private func filledRegimen() -> Regimen {
        Regimen(id: "reg-1", name: "Vitamin D", dose: "1000 IU",
                timesOfDay: ["morning", "evening"], daysOfWeek: [2, 4, 6], withFood: true,
                kind: .med, active: false, remind: false, startEpoch: 1_770_000_000)
    }

    private func filledCheckIn() -> DayCheckIn {
        var c = DayCheckIn()
        c.soreness = 2; c.stress = 3; c.mood = 1; c.alcohol = 2
        c.lateCaffeine = true; c.illness = true
        return c
    }

    private func filledOccasion() -> Occasion {
        var o = Occasion(title: "Amma's birthday", type: "birthday", dateEpoch: 1_780_000_000,
                         recurringAnnual: true, person: "Amma", location: "Kochi", source: "contacts")
        o.notes = "flowers + payasam"
        o.context = "she likes lilies"
        o.checklist = [ChecklistItem(text: "book cake", done: true)]
        o.itinerary = [ItineraryItem(dateEpoch: 1_780_003_600, title: "lunch", detail: "at home")]
        o.calendarSynced = true
        return o
    }

    private func filledAppData() -> AppData {
        var d = AppData()
        d.entries = ["2026-03-04": filledEntry()]
        d.audits = ["2026-03-04": "solid day"]
        var item = CatalogItem(kind: .supplement, name: "creatine", serving: "5 g", calories: 0,
                               protein: 0, carbs: 0, fat: 0, fiber: 0,
                               micros: [Micro(name: "sodium", amount: 3, unit: "mg")],
                               mealTags: ["drinks"], favorite: true)
        item.lastUsedEpoch = 1_772_000_000
        item.useCount = 12
        d.catalog = [item]
        d.bodyComps = [BodyComp(date: "2026-03-01", weight: 83.4, bodyFat: 21.2, leanMass: 65.7,
                                skeletalMuscle: 36.1, bmi: 26.4, visceralFat: 11)]
        d.labs = [LabRecord(date: "2026-02-14", title: "annual",
                            items: [LabItem(name: "HbA1c", value: 5.4, unit: "%", written: true)])]
        d.habits = [HabitDef(title: "Prayed Fajr", pillar: .spirituality, link: .prayer,
                             prayerName: "fajr", prayerNames: ["fajr", "isha"], threshold: 1,
                             active: false, order: 3)]
        d.subjects = [Subject(name: "physiology", done: true)]
        d.countdowns = [Countdown(name: "finals", dateEpoch: 1_790_000_000, kind: "work")]
        d.routine = [RoutineBlock(weekday: 3, title: "PT", kind: "mobility", hour: 18, minute: 30,
                                  durationMin: 50, withPT: true, remind: false)]
        var session = ScheduledSession(dateEpoch: 1_772_100_000, title: "long run", kind: "run",
                                       durationMin: 75, location: "marine drive", withPT: true,
                                       remindMin: 30, fromRoutine: true, fromAIPlan: true)
        session.calendarEventID = "evt-9"
        session.done = true
        d.sessions = [session]
        d.occasions = [filledOccasion()]
        var note = HealthNote(title: "neck", text: "no overhead work", category: "injury")
        note.dateEpoch = 1_771_000_000
        d.healthNotes = [note]
        d.rings = [RingDef(source: .custom, metric: .hydrationPct, title: "Water", goal: 3000,
                           colorHex: 0x33AACC, enabled: false, order: 7)]
        d.earnedMilestones = [EarnedMilestone(id: "days-100", earnedEpoch: 1_772_000_000)]
        d.regimens = [filledRegimen()]
        d.retiredRegimens = [RetiredRegimen(id: "reg-9", name: "Old iron tablet")]
        return d
    }

    // MARK: - Round-trips (delete a tolerant-decode line and one of these goes red)

    func testEntryRoundTripKeepsEveryField() throws {
        try roundTrip(filledEntry())
    }

    func testNestedEntryStructsRoundTrip() throws {
        let e = filledEntry()
        try roundTrip(e.prayers)
        try roundTrip(e.checkIn)
        try roundTrip(try XCTUnwrap(e.sleep))
        try roundTrip(try XCTUnwrap(e.foodEntries.first))
        try roundTrip(try XCTUnwrap(e.logged.first))
        try roundTrip(try XCTUnwrap(e.workouts.first))
        try roundTrip(try XCTUnwrap(e.workouts.first?.exercises.first))
        try roundTrip(try XCTUnwrap(e.workouts.first?.exercises.first?.sets.first))
        try roundTrip(PrayerRecord(markedEpoch: 1_772_000_000, band: .qadha))
        try roundTrip(Micro(name: "zinc", amount: 8, unit: "mg"))
    }

    func testPlanningAndOccasionStructsRoundTrip() throws {
        let d = filledAppData()
        try roundTrip(try XCTUnwrap(d.routine.first))
        try roundTrip(try XCTUnwrap(d.sessions.first))
        try roundTrip(try XCTUnwrap(d.occasions.first))
        try roundTrip(try XCTUnwrap(d.occasions.first?.checklist.first))
        try roundTrip(try XCTUnwrap(d.occasions.first?.itinerary.first))
        try roundTrip(try XCTUnwrap(d.healthNotes.first))
        try roundTrip(try XCTUnwrap(d.catalog.first))
        try roundTrip(try XCTUnwrap(d.rings.first))
    }

    func testSettingsTargetsAndPrefsRoundTrip() throws {
        var s = AppSettings()
        s.provider = "openai"; s.model = "gpt5"; s.customModel = "some/model"
        s.ollamaHost = "http://192.168.1.9:11434"; s.healthkit = false
        s.hkRead = HKReadFlags(weight: false, steps: false, energy: false, workouts: false, sleep: true)
        s.hkWrite = HKWriteFlags(calories: false, protein: false)
        s.calendarSync = true; s.remindersSync = true; s.visibleRingCount = 3
        s.appLockEnabled = true; s.appLockGraceMinutes = 15
        s.smartReminders = false; s.smartStreakRule = false; s.smartDinnerRule = false
        s.smartBedtimeRule = false; s.smartProteinRule = false; s.smartEveningHour = 22
        s.windDownEnabled = false; s.windDownHour = 21
        try roundTrip(s)

        var t = Targets()
        t.calories = 2400; t.protein = 150; t.steps = 11000; t.studyHours = 6
        t.examName = "finals"; t.examDateEpoch = 1_790_000_000; t.workMode = "work"
        t.ageYears = 34; t.heightCm = 178; t.sexMale = false; t.goal = "cut"
        t.prizeName = "Body fat"; t.prizeUnit = "%"; t.prizeStart = 24; t.prizeTarget = 16
        t.prizeCurrent = 21; t.prizeLowerIsBetter = false
        try roundTrip(t)

        var m = ModulePrefs()
        m.coach = false; m.prayer = false; m.health = false; m.meals = false
        m.hydration = false; m.quickLog = false; m.workStudy = false; m.training = false
        m.photos = false; m.fasting = true; m.sleep = false; m.weather = false
        m.regimen = false
        m.order = Array(ModulePrefs.defaultOrder.reversed())
        try roundTrip(m)

        var p = Personalization()
        p.pillarTitles = ["work": "Deep work"]
        p.moduleColors = ["meals": 0x112233]
        try roundTrip(p)
    }

    func testCoachThreadRoundTrips() throws {
        var thread = CoachThread()
        thread.title = "Meal ideas"
        thread.messages = [ChatMessage(role: "user", text: "what's for dinner"),
                           ChatMessage(role: "assistant", text: "fish curry")]
        thread.createdEpoch = 1_772_000_000
        thread.updatedEpoch = 1_772_003_600
        try roundTrip(thread)
        try roundTrip(try XCTUnwrap(thread.messages.first))
    }

    func testAppDataRoundTripKeepsEveryCollection() throws {
        let original = filledAppData()
        let back = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(back.entries, original.entries)
        XCTAssertEqual(back.audits, original.audits)
        XCTAssertEqual(back.catalog, original.catalog)
        XCTAssertEqual(back.bodyComps, original.bodyComps)
        XCTAssertEqual(back.labs, original.labs)
        XCTAssertEqual(back.habits, original.habits)
        XCTAssertEqual(back.subjects, original.subjects)
        XCTAssertEqual(back.countdowns, original.countdowns)
        XCTAssertEqual(back.routine, original.routine)
        XCTAssertEqual(back.sessions, original.sessions)
        XCTAssertEqual(back.occasions, original.occasions)
        XCTAssertEqual(back.healthNotes, original.healthNotes)
        XCTAssertEqual(back.rings, original.rings)
        XCTAssertEqual(back.earnedMilestones, original.earnedMilestones)
        XCTAssertEqual(back.regimens, original.regimens)
        XCTAssertEqual(back.retiredRegimens, original.retiredRegimens)
    }

    /// `AppData.regimens` decodes as one array, so a missing tolerant line on `Regimen` would wipe
    /// every scheduled medication/supplement the user has, not just one field.
    func testRegimenRoundTripAndDefaults() throws {
        try roundTrip(filledRegimen())
        try roundTrip(RetiredRegimen(id: "reg-9", name: "Old iron tablet"))

        let r = try decodeEmpty(Regimen.self)
        XCTAssertEqual(r.name, "")
        XCTAssertEqual(r.dose, "")
        XCTAssertEqual(r.timesOfDay, [RegimenSlot.morning.rawValue])
        XCTAssertEqual(r.daysOfWeek, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertFalse(r.withFood)
        XCTAssertEqual(r.kind, .supplement)
        XCTAssertTrue(r.active)
        XCTAssertTrue(r.remind)
        XCTAssertEqual(r.startEpoch, 0)
        XCTAssertFalse(r.id.isEmpty, "a missing id must get a fresh UUID, not an empty string")

        let retired = try decodeEmpty(RetiredRegimen.self)
        XCTAssertEqual(retired.id, "")
        XCTAssertEqual(retired.name, "")

        // Garbage in one key falls back rather than taking the regimen (and the list) down.
        let junk = try decode(Regimen.self, #"{"id":"reg-2","name":"Iron","kind":"vitamin","daysOfWeek":"every day","active":"yes"}"#)
        XCTAssertEqual(junk.id, "reg-2")
        XCTAssertEqual(junk.name, "Iron")
        XCTAssertEqual(junk.kind, .supplement)
        XCTAssertEqual(junk.daysOfWeek, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertTrue(junk.active)
    }

    /// Weekday storage is Sunday-based 1–7 (`DateComponents.weekday`) and must not depend on the
    /// user's `firstWeekday`, which only affects UI layout.
    func testRegimenSchedulingUsesSundayBasedWeekdays() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        // 2026-03-04 is a Wednesday (weekday 4); 2026-03-05 a Thursday (weekday 5).
        var comps = DateComponents(); comps.year = 2026; comps.month = 3; comps.day = 4
        let wednesday = try XCTUnwrap(cal.date(from: comps))
        comps.day = 5
        let thursday = try XCTUnwrap(cal.date(from: comps))
        XCTAssertEqual(cal.component(.weekday, from: wednesday), 4)

        let r = Regimen(name: "Vitamin D", timesOfDay: ["morning"], daysOfWeek: [4])
        XCTAssertTrue(r.scheduled(on: wednesday, calendar: cal))
        XCTAssertFalse(r.scheduled(on: thursday, calendar: cal))

        // A start date in the future means the day isn't scheduled yet.
        var later = r
        later.startEpoch = thursday.timeIntervalSince1970
        XCTAssertFalse(later.scheduled(on: wednesday, calendar: cal))

        // Inactive or slot-less regimens are never scheduled.
        var off = r; off.active = false
        XCTAssertFalse(off.scheduled(on: wednesday, calendar: cal))
        var noSlots = r; noSlots.timesOfDay = ["whenever"]
        XCTAssertFalse(noSlots.scheduled(on: wednesday, calendar: cal))
    }

    // MARK: - Types reachable from AppData as whole arrays
    //
    // `AppData.init(from:)` decodes each of these as an entire collection —
    // `(try? c.decode([HabitDef].self, forKey: .habits)) ?? []`. So a single element that fails to
    // decode doesn't degrade to a partial habit; it takes the **whole list** with it. That makes a
    // missing tolerant-decode line here a total-loss bug, not a one-field bug, which is why each of
    // these gets both a fully-populated round-trip and an empty-object check.

    func testMealsAndNonNegotiablesRoundTripAndDefault() throws {
        try roundTrip(Meals(breakfast: "idli", snacks: "dates", lunch: "biryani",
                            dinner: "grilled fish", drinks: "black coffee"))
        XCTAssertEqual(try decodeEmpty(Meals.self), Meals())

        try roundTrip(NonNegotiables(fajr: true, protein: true, moved: true, phone: true, side: true))
        XCTAssertEqual(try decodeEmpty(NonNegotiables.self), NonNegotiables())
    }

    func testHabitDefRoundTripAndDefaults() throws {
        try roundTrip(HabitDef(id: "h-1", title: "Walk 10k", pillar: .health, link: .steps,
                               prayerName: "isha", prayerNames: ["fajr", "maghrib"], threshold: 10_000,
                               active: false, order: 6))
        let h = try decodeEmpty(HabitDef.self)
        XCTAssertEqual(h.title, "")
        XCTAssertEqual(h.pillar, .custom)
        XCTAssertEqual(h.link, .manual)
        XCTAssertEqual(h.prayerName, "fajr")
        XCTAssertTrue(h.prayerNames.isEmpty)
        XCTAssertEqual(h.threshold, 0)
        XCTAssertTrue(h.active)
        XCTAssertEqual(h.order, 0)
        XCTAssertFalse(h.id.isEmpty, "a missing id must get a fresh UUID, not an empty string")
    }

    func testSubjectAndCountdownRoundTripAndDefaults() throws {
        try roundTrip(Subject(id: "s-1", name: "biochemistry", done: true))
        let s = try decodeEmpty(Subject.self)
        XCTAssertEqual(s.name, "")
        XCTAssertFalse(s.done)
        XCTAssertFalse(s.id.isEmpty)

        try roundTrip(Countdown(id: "c-1", name: "viva", dateEpoch: 1_795_000_000, kind: "work"))
        let c = try decodeEmpty(Countdown.self)
        XCTAssertEqual(c.name, "")
        XCTAssertEqual(c.dateEpoch, 0)
        XCTAssertEqual(c.kind, "study")
        XCTAssertFalse(c.id.isEmpty)
    }

    func testBodyCompRoundTripAndDefaults() throws {
        try roundTrip(BodyComp(id: "bc-1", date: "2026-04-02", weight: 81.9, bodyFat: 19.4,
                               leanMass: 66.0, skeletalMuscle: 37.2, bmi: 25.8, visceralFat: 9))
        let b = try decodeEmpty(BodyComp.self)
        XCTAssertEqual(b.date, "")
        XCTAssertNil(b.weight)
        XCTAssertNil(b.bodyFat)
        XCTAssertNil(b.leanMass)
        XCTAssertNil(b.skeletalMuscle)
        XCTAssertNil(b.bmi)
        XCTAssertNil(b.visceralFat)
        XCTAssertFalse(b.id.isEmpty)
    }

    func testLabItemAndLabRecordRoundTripAndDefaults() throws {
        let item = LabItem(id: "li-1", name: "Ferritin", value: 88.5, unit: "ng/mL", written: true)
        try roundTrip(item)
        try roundTrip(LabRecord(id: "lr-1", date: "2026-04-02", title: "Full panel", items: [item]))

        let i = try decodeEmpty(LabItem.self)
        XCTAssertEqual(i.name, "")
        XCTAssertEqual(i.value, 0)
        XCTAssertEqual(i.unit, "")
        XCTAssertFalse(i.written)
        XCTAssertFalse(i.id.isEmpty)

        let r = try decodeEmpty(LabRecord.self)
        XCTAssertEqual(r.date, "")
        XCTAssertEqual(r.title, "")
        XCTAssertTrue(r.items.isEmpty)
        XCTAssertFalse(r.id.isEmpty)
    }

    func testHealthKitFlagsRoundTripAndKeepTheirOptInDefaults() throws {
        try roundTrip(HKReadFlags(weight: false, steps: false, energy: false, workouts: false, sleep: true))
        try roundTrip(HKWriteFlags(calories: false, protein: false))
        // Defaults are deliberately asymmetric — everything on except sleep — so `{}` must not
        // collapse them all to `false`.
        XCTAssertEqual(try decodeEmpty(HKReadFlags.self), HKReadFlags())
        XCTAssertEqual(try decodeEmpty(HKWriteFlags.self), HKWriteFlags())
        let read = try decodeEmpty(HKReadFlags.self)
        XCTAssertTrue(read.weight && read.steps && read.energy && read.workouts)
        XCTAssertFalse(read.sleep)
        let write = try decodeEmpty(HKWriteFlags.self)
        XCTAssertTrue(write.calories && write.protein)
    }

    /// The actual regression this convention exists to prevent: JSON written by an older build (no
    /// `threshold`/`prayerNames`/`done`/`kind`/`written` keys) must still decode the **whole array**.
    /// With synthesized Codable a single missing key throws, `try?` yields nil, and the user loses
    /// every habit / subject / countdown / lab they ever recorded.
    func testLegacyAppDataArraysSurviveMissingNewerKeys() throws {
        let legacy = """
        {"habits":[{"id":"fajr","title":"Prayed Fajr","pillar":"spirituality","link":"prayer"},
                   {"id":"protein","title":"Hit protein target","pillar":"health","link":"protein"}],
         "subjects":[{"id":"s1","name":"anatomy"}],
         "countdowns":[{"id":"c1","name":"finals","dateEpoch":1790000000}],
         "bodyComps":[{"id":"b1","date":"2026-01-01","weight":84.2}],
         "labs":[{"id":"l1","date":"2026-01-02","title":"lipids",
                  "items":[{"id":"i1","name":"LDL","value":110,"unit":"mg/dL"}]}]}
        """
        let d = try decode(AppData.self, legacy)
        XCTAssertEqual(d.habits.count, 2, "one habit missing a newer key must not wipe the whole list")
        XCTAssertEqual(d.habits.first?.title, "Prayed Fajr")
        XCTAssertEqual(d.habits.first?.threshold, 0)
        XCTAssertTrue(try XCTUnwrap(d.habits.first).prayerNames.isEmpty)
        XCTAssertTrue(try XCTUnwrap(d.habits.first).active)
        XCTAssertEqual(d.subjects.count, 1)
        XCTAssertEqual(d.subjects.first?.name, "anatomy")
        XCTAssertEqual(d.subjects.first?.done, false)
        XCTAssertEqual(d.countdowns.count, 1)
        XCTAssertEqual(d.countdowns.first?.kind, "study")
        XCTAssertEqual(d.bodyComps.count, 1)
        XCTAssertEqual(d.bodyComps.first?.weight, 84.2)
        XCTAssertNil(d.bodyComps.first?.bodyFat)
        XCTAssertEqual(d.labs.first?.items.count, 1)
        XCTAssertEqual(d.labs.first?.items.first?.written, false)
    }

    /// Legacy `AppSettings` JSON predating `hkRead`/`hkWrite` sub-keys keeps the on-by-default flags.
    func testLegacySettingsKeepHealthKitDefaults() throws {
        let s = try decode(AppSettings.self, #"{"provider":"openai","hkRead":{"sleep":true}}"#)
        XCTAssertEqual(s.provider, "openai")
        XCTAssertTrue(s.hkRead.weight, "an absent sub-key must keep its default, not flip to false")
        XCTAssertTrue(s.hkRead.sleep)
        XCTAssertEqual(s.hkWrite, HKWriteFlags())
    }

    // MARK: - Empty-object tolerance (old data written before a field existed)

    func testEveryPersistedStructDecodesFromAnEmptyObject() throws {
        let entry = try decodeEmpty(Entry.self)
        XCTAssertEqual(entry.date, "")
        XCTAssertEqual(entry.status, "normal")
        XCTAssertTrue(entry.habitState.isEmpty)

        XCTAssertTrue(try decodeEmpty(AppData.self).entries.isEmpty)
        XCTAssertTrue(try decodeEmpty(AppData.self).earnedMilestones.isEmpty)
        XCTAssertEqual(try decodeEmpty(EarnedMilestone.self).earnedEpoch, 0)
        XCTAssertEqual(try decodeEmpty(AppSettings.self), AppSettings())
        XCTAssertEqual(try decodeEmpty(Targets.self), Targets())
        XCTAssertEqual(try decodeEmpty(ModulePrefs.self), ModulePrefs())
        XCTAssertEqual(try decodeEmpty(Personalization.self), Personalization())
        XCTAssertEqual(try decodeEmpty(DayCheckIn.self), DayCheckIn())
        XCTAssertEqual(try decodeEmpty(SleepBreakdown.self), SleepBreakdown())
        XCTAssertEqual(try decodeEmpty(PrayerLog.self), PrayerLog())
        XCTAssertEqual(try decodeEmpty(PrayerRecord.self), PrayerRecord())
        XCTAssertEqual(try decodeEmpty(RingDef.self).source, .custom)
        XCTAssertEqual(try decodeEmpty(Occasion.self).type, "custom")
        XCTAssertEqual(try decodeEmpty(ChecklistItem.self).text, "")
        XCTAssertEqual(try decodeEmpty(ItineraryItem.self).dateEpoch, 0)
        XCTAssertEqual(try decodeEmpty(HealthNote.self).category, "note")
        XCTAssertEqual(try decodeEmpty(FoodEntry.self).mealKey, "snacks")
        XCTAssertEqual(try decodeEmpty(FoodEntry.self).qty, 1)
        XCTAssertEqual(try decodeEmpty(LoggedItem.self).qty, 1)
        XCTAssertEqual(try decodeEmpty(CatalogItem.self).kind, .food)
        XCTAssertEqual(try decodeEmpty(Micro.self).unit, "")
        XCTAssertEqual(try decodeEmpty(Workout.self).kind, "strength")
        XCTAssertEqual(try decodeEmpty(Exercise.self).name, "")
        XCTAssertEqual(try decodeEmpty(StrengthSet.self).weightKg, 0)
        XCTAssertEqual(try decodeEmpty(RoutineBlock.self).durationMin, 45)
        XCTAssertEqual(try decodeEmpty(ScheduledSession.self).remindMin, 60)
        XCTAssertEqual(try decodeEmpty(ChatMessage.self).role, "assistant")
        XCTAssertEqual(try decodeEmpty(CoachThread.self).title, "New chat")
        XCTAssertEqual(try decodeEmpty(Meals.self), Meals())
        XCTAssertEqual(try decodeEmpty(NonNegotiables.self), NonNegotiables())
        XCTAssertEqual(try decodeEmpty(HKReadFlags.self), HKReadFlags())
        XCTAssertEqual(try decodeEmpty(HKWriteFlags.self), HKWriteFlags())
        XCTAssertEqual(try decodeEmpty(HabitDef.self).prayerName, "fajr")
        XCTAssertEqual(try decodeEmpty(Subject.self).name, "")
        XCTAssertEqual(try decodeEmpty(Countdown.self).kind, "study")
        XCTAssertEqual(try decodeEmpty(BodyComp.self).date, "")
        XCTAssertEqual(try decodeEmpty(LabItem.self).value, 0)
        XCTAssertTrue(try decodeEmpty(LabRecord.self).items.isEmpty)
    }

    /// A build that shipped before `foodEntries`/`rings`/`checkIn` existed wrote JSON without them —
    /// the day must still load with everything else intact.
    func testEntryFromLegacyJSONKeepsKnownFields() throws {
        let legacy = """
        {"date":"2025-11-02","training":"legs","weight":"85.0","calories":"1980",
         "nn":{"fajr":true,"protein":true,"moved":true,"phone":false,"side":false}}
        """
        let e = try decode(Entry.self, legacy)
        XCTAssertEqual(e.date, "2025-11-02")
        XCTAssertEqual(e.training, "legs")
        XCTAssertEqual(e.weight, "85.0")
        XCTAssertEqual(e.calories, "1980")
        XCTAssertTrue(e.foodEntries.isEmpty)
        XCTAssertEqual(e.status, "normal")
        // Legacy non-negotiables migrate into the manual-habit state rather than being dropped.
        XCTAssertEqual(e.habitState["moved"], true)
        XCTAssertNil(e.habitState["phone"])
    }

    /// The five top-level prayer bools predate `records` — a legacy `true` becomes an untimed mark.
    func testLegacyPrayerBoolsMigrateInsteadOfWiping() throws {
        let log = try decode(PrayerLog.self, #"{"fajr":true,"dhuhr":false,"maghrib":true}"#)
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log.band("fajr"), .unknown)
        XCTAssertEqual(log.band("maghrib"), .unknown)
        XCTAssertEqual(log.band("dhuhr"), .notLogged)
        XCTAssertNil(log.markedDate("fajr"))
    }

    // MARK: - Hostile input: unknown enum cases and wrong types

    func testUnknownEnumCasesFallBackInsteadOfThrowing() throws {
        let ring = try decode(RingDef.self,
                              #"{"id":"r1","source":"somethingNew","metric":"alsoNew","title":"X","goal":50,"colorHex":7,"enabled":false,"order":2}"#)
        XCTAssertEqual(ring.source, .custom)
        XCTAssertEqual(ring.metric, .unknown)
        // Everything alongside the unknown case must still survive.
        XCTAssertEqual(ring.id, "r1")
        XCTAssertEqual(ring.title, "X")
        XCTAssertEqual(ring.goal, 50)
        XCTAssertEqual(ring.colorHex, 7)
        XCTAssertFalse(ring.enabled)
        XCTAssertEqual(ring.order, 2)

        XCTAssertEqual(try decode(FoodEntry.self, #"{"name":"x","source":"quantumDb"}"#).source, .manual)
        XCTAssertEqual(try decode(CatalogItem.self, #"{"name":"x","kind":"potion"}"#).kind, .food)
        XCTAssertEqual(try decode(PrayerRecord.self, #"{"markedEpoch":12,"band":"whenever"}"#).band, .notLogged)
    }

    func testWronglyTypedValuesFallBackWithoutLosingTheRest() throws {
        let e = try decode(Entry.self,
                           #"{"date":"2026-01-09","waterMl":"lots","activeKcal":true,"readiness":"high","status":"sick"}"#)
        XCTAssertEqual(e.date, "2026-01-09")
        XCTAssertEqual(e.waterMl, 0)
        XCTAssertEqual(e.activeKcal, 0)
        XCTAssertEqual(e.readiness, 0)
        XCTAssertEqual(e.status, "sick")
    }

    /// One corrupt entry must not take the rest of the document with it — but note that `AppData`
    /// decodes `entries` as a whole dictionary, so this documents the actual blast radius.
    func testAppDataSurvivesGarbageInASingleSection() throws {
        let d = try decode(AppData.self, #"{"entries":"not-a-dictionary","audits":{"2026-01-09":"ok"}}"#)
        XCTAssertTrue(d.entries.isEmpty)
        XCTAssertEqual(d.audits["2026-01-09"], "ok")
    }

    // MARK: - Zero survival (a real 0 must not read as "never computed")

    func testZeroScoresSurviveARoundTrip() throws {
        var e = Entry(date: "2026-02-02")
        e.readiness = 0
        e.sleepScore = 0
        e.activeScore = 0     // Int? on purpose: nil = not computed, 0 = genuinely zero
        e.eatingScore = 0
        e.waterMl = 0
        let back = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back.readiness, 0)
        XCTAssertEqual(back.sleepScore, 0)
        XCTAssertEqual(back.activeScore, 0, "a computed 0 must not decode back as nil")
        XCTAssertEqual(back.eatingScore, 0)
        XCTAssertNotNil(back.activeScore)
        XCTAssertNotNil(back.eatingScore)
    }

    func testNotComputedScoresStayNil() throws {
        let e = Entry(date: "2026-02-03")
        XCTAssertNil(e.activeScore)
        let back = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(e))
        XCTAssertNil(back.activeScore, "an uncomputed score must stay nil, not become 0")
        XCTAssertNil(back.eatingScore)
        XCTAssertNil(back.sleep)
        XCTAssertNil(back.ai)
    }

    // MARK: - Clamps and derived defaults inside tolerant decoders

    func testVisibleRingCountIsClampedOnDecode() throws {
        XCTAssertEqual(try decode(AppSettings.self, #"{"visibleRingCount":99}"#).visibleRingCount, 4)
        XCTAssertEqual(try decode(AppSettings.self, #"{"visibleRingCount":0}"#).visibleRingCount, 3)
    }

    func testAppLockDefaultsAreSafeAndGraceIsValidated() throws {
        // A pre-app-lock settings blob must come back unlocked, never locked-by-accident.
        let old = try decode(AppSettings.self, #"{"provider":"openai"}"#)
        XCTAssertFalse(old.appLockEnabled)
        XCTAssertEqual(old.appLockGraceMinutes, 1)
        XCTAssertEqual(try decode(AppSettings.self, #"{"appLockGraceMinutes":5}"#).appLockGraceMinutes, 5)
        XCTAssertEqual(try decode(AppSettings.self, #"{"appLockGraceMinutes":0}"#).appLockGraceMinutes, 0)
        XCTAssertEqual(try decode(AppSettings.self, #"{"appLockGraceMinutes":999}"#).appLockGraceMinutes, 1)
        XCTAssertEqual(try decode(AppSettings.self, #"{"appLockGraceMinutes":-4}"#).appLockGraceMinutes, 1)
    }

    func testSmartEveningHourIsClampedOnDecode() throws {
        XCTAssertEqual(try decode(AppSettings.self, #"{"smartEveningHour":31}"#).smartEveningHour, 23)
        XCTAssertEqual(try decode(AppSettings.self, #"{"smartEveningHour":3}"#).smartEveningHour, 16)
        // Settings saved before the smart-reminder fields existed still opt in by default.
        XCTAssertTrue(try decode(AppSettings.self, #"{"provider":"openai"}"#).smartReminders)
    }

    func testWindDownHourIsClampedAndDefaultsToAuto() throws {
        // Settings written before the wind-down existed: on, and on "auto" (bedtime - 45 min).
        let old = try decode(AppSettings.self, #"{"provider":"openai"}"#)
        XCTAssertTrue(old.windDownEnabled)
        XCTAssertEqual(old.windDownHour, -1)
        XCTAssertEqual(try decode(AppSettings.self, #"{"windDownHour":21}"#).windDownHour, 21)
        XCTAssertEqual(try decode(AppSettings.self, #"{"windDownHour":99}"#).windDownHour, 23)
        XCTAssertEqual(try decode(AppSettings.self, #"{"windDownHour":-9}"#).windDownHour, -1)
    }

    /// A tomorrow-entry whose only content is the focus set the night before must count as worth
    /// saving, or `AppStore.commit()` drops it before the chip is ever shown.
    func testEntryWithOnlyAMainFocusIsMeaningful() throws {
        var e = Entry(date: "2026-03-05")
        XCTAssertFalse(e.isMeaningful)
        e.mainFocus = "one hard thing"
        XCTAssertTrue(e.isMeaningful)
        e.mainFocus = "   "
        XCTAssertFalse(e.isMeaningful)
    }

    func testModulePrefsOrderDropsUnknownKeysAndAppendsNewOnes() throws {
        let m = try decode(ModulePrefs.self, #"{"order":["photos","ghostModule","rings"]}"#)
        XCTAssertFalse(m.order.contains("ghostModule"))
        XCTAssertEqual(Array(m.order.prefix(2)), ["photos", "rings"])
        XCTAssertEqual(Set(m.order), Set(ModulePrefs.defaultOrder), "every known module must survive")
        XCTAssertEqual(m.order.count, ModulePrefs.defaultOrder.count)
    }

    func testTargetsMigrateLegacyVisceralKeysAndDefaultPrizeCurrent() throws {
        let t = try decode(Targets.self, #"{"visceralStart":18,"visceralTarget":9}"#)
        XCTAssertEqual(t.prizeStart, 18)
        XCTAssertEqual(t.prizeTarget, 9)
        XCTAssertEqual(t.prizeCurrent, 18, "prizeCurrent falls back to prizeStart, not to the hard default")
    }
}
