import Foundation
import HealthKit

/// Reads steps + body mass and writes dietary energy + protein.
/// Falls back to deterministic placeholder values when HealthKit is unavailable
/// (e.g. on Simulator) so the UI still has something to show.
@MainActor
final class HealthManager: ObservableObject {
    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    @Published var stepsToday: Double = 0
    @Published var latestWeight: Double = 0
    @Published var activeEnergyToday: Double = 0     // kcal
    @Published var restingHR: Double = 0             // bpm (incl. Bevel/Watch)
    @Published var hrv: Double = 0                    // ms SDNN (incl. Bevel)
    @Published var sleepHours: Double = 0            // last night
    @Published var sleepDetail: SleepBreakdown?      // last night's detailed sleep
    @Published var workoutsThisWeek: Int = 0
    @Published var authorized = false
    @Published var usingPlaceholders = false

    private let stepType = HKQuantityType(.stepCount)
    private let weightType = HKQuantityType(.bodyMass)
    private let energyType = HKQuantityType(.dietaryEnergyConsumed)
    private let proteinType = HKQuantityType(.dietaryProtein)
    private let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private let restingHRType = HKQuantityType(.restingHeartRate)
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let sleepType = HKCategoryType(.sleepAnalysis)
    // Body composition (InBody)
    private let bodyFatType = HKQuantityType(.bodyFatPercentage)
    private let leanMassType = HKQuantityType(.leanBodyMass)
    private let bmiType = HKQuantityType(.bodyMassIndex)

    @Published var weightToday: Double = 0   // smart-scale weight logged today, if any
    @Published var dateSteps: Double = 0     // steps for the day shown on Today
    @Published var dateWeight: Double = 0    // latest body mass up to that day
    @Published var stepsHistory: [Double] = []   // daily steps (oldest→newest) for Trends

    func requestAuthorization() async {
        guard available else {
            loadPlaceholders()
            return
        }
        let read: Set<HKObjectType> = [
            stepType, weightType, activeEnergyType, restingHRType, hrvType, sleepType,
            energyType, proteinType, bodyFatType, leanMassType, bmiType, HKObjectType.workoutType()
        ]
        var write: Set<HKSampleType> = [
            energyType, proteinType, weightType, bodyFatType, leanMassType, bmiType,
            HKObjectType.workoutType()
        ]
        for t in Self.labWritableTypes.values { write.insert(t) }
        do {
            try await store.requestAuthorization(toShare: write, read: read)
            authorized = true
            await refresh()
        } catch {
            loadPlaceholders()
        }
    }

    func refresh() async {
        guard available else { loadPlaceholders(); return }
        async let steps = fetchStepsToday()
        async let weight = fetchLatest(weightType, unit: .gramUnit(with: .kilo))
        async let active = fetchSumToday(activeEnergyType, unit: .kilocalorie())
        async let rhr = fetchLatest(restingHRType, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrvVal = fetchLatest(hrvType, unit: .secondUnit(with: .milli))
        async let sleep = fetchSleepHours()
        async let workouts = fetchWorkoutsThisWeek()

        let r = await (steps, weight, active, rhr, hrvVal, sleep, workouts)
        stepsToday = r.0 ?? 0
        latestWeight = r.1 ?? 0
        activeEnergyToday = r.2 ?? 0
        restingHR = r.3 ?? 0
        hrv = r.4 ?? 0
        sleepHours = r.5 ?? 0
        workoutsThisWeek = r.6
        sleepDetail = await fetchSleepDetail()
        if let s = sleepDetail, s.asleepHours > 0 { sleepHours = s.asleepHours }
        weightToday = await fetchWeightTodayValue() ?? 0
        usingPlaceholders = false
        if stepsToday == 0 && latestWeight == 0 && activeEnergyToday == 0 { loadPlaceholders() }
    }

    private func loadPlaceholders() {
        // Deterministic stand-ins so the simulator (empty HealthKit) isn't blank.
        usingPlaceholders = true
        let doy = Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: Date()) ?? 1
        stepsToday = Double(4200 + ((doy * 617) % 5400))
        latestWeight = 84.3
        activeEnergyToday = 412
        restingHR = 58
        hrv = 42
        sleepHours = 7.2
        workoutsThisWeek = 4
    }

    private func fetchStepsToday() async -> Double? {
        await fetchSumToday(stepType, unit: .count())
    }

    private func fetchSumToday(_ type: HKQuantityType, unit: HKUnit) async -> Double? {
        let start = Calendar.current.startOfDay(for: Date())
        return await fetchSum(type, unit: unit, start: start, end: Date())
    }

    private func fetchSum(_ type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// Load steps + body mass for an arbitrary day (drives the Today card when viewing past dates).
    func loadForDay(_ dateString: String) async {
        guard available else { dateSteps = stepsToday; dateWeight = latestWeight; return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: AppStore.parse(dateString))
        let end = min(Date(), cal.date(byAdding: .day, value: 1, to: start) ?? Date())
        async let steps = fetchSum(stepType, unit: .count(), start: start, end: end)
        async let weight = fetchWeight(before: cal.date(byAdding: .day, value: 1, to: start) ?? end)
        dateSteps = await steps ?? 0
        dateWeight = await weight ?? 0
    }

    /// Daily step totals for the last `days` days (oldest → newest) for the Trends chart.
    func loadStepsHistory(days: Int = 14) async {
        guard available else { return }
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date())) else { return }
        let result: [Double] = await withCheckedContinuation { cont in
            let interval = DateComponents(day: 1)
            let q = HKStatisticsCollectionQuery(quantityType: stepType,
                                                quantitySamplePredicate: nil,
                                                options: .cumulativeSum,
                                                anchorDate: cal.startOfDay(for: start),
                                                intervalComponents: interval)
            q.initialResultsHandler = { _, collection, _ in
                var out: [Double] = []
                collection?.enumerateStatistics(from: start, to: end) { stat, _ in
                    out.append(stat.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
        // Trim leading zero-only days so the chart starts at real data.
        var trimmed = result
        while let first = trimmed.first, first == 0, trimmed.count > 1 { trimmed.removeFirst() }
        stepsHistory = trimmed
    }

    private func fetchWeight(before end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: weightType, predicate: predicate, limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo)))
            }
            store.execute(q)
        }
    }

    private func fetchLatest(_ type: HKQuantityType, unit: HKUnit) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// Hours "asleep" in the most recent night.
    private func fetchSleepHours() async -> Double? {
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                ]
                let seconds = (samples as? [HKCategorySample] ?? [])
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: seconds > 0 ? seconds / 3600.0 : nil)
            }
            store.execute(q)
        }
    }

    /// Detailed sleep for the night you woke on `day` (window ≈ 6pm prev → noon).
    func fetchSleepDetail(nightEnding day: Date = Date()) async -> SleepBreakdown? {
        guard available else { return nil }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let start = cal.date(byAdding: .hour, value: -6, to: dayStart) ?? dayStart   // ~6pm prev day
        let end = min(Date(), cal.date(byAdding: .hour, value: 12, to: dayStart) ?? day)  // ~noon
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let cats = (samples as? [HKCategorySample]) ?? []
                guard !cats.isEmpty else { cont.resume(returning: nil); return }
                var b = SleepBreakdown()
                func mins(_ s: HKCategorySample) -> Double { s.endDate.timeIntervalSince(s.startDate) / 60 }
                var firstAsleep: Date?
                var lastAsleep: Date?
                for s in cats {
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        b.deepMin += mins(s); b.asleepMin += mins(s)
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        b.remMin += mins(s); b.asleepMin += mins(s)
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        b.coreMin += mins(s); b.asleepMin += mins(s)
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        b.coreMin += mins(s); b.asleepMin += mins(s)
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        b.awakeMin += mins(s)
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        b.inBedMin += mins(s)
                    default: break
                    }
                    let asleep = s.value != HKCategoryValueSleepAnalysis.awake.rawValue
                        && s.value != HKCategoryValueSleepAnalysis.inBed.rawValue
                    if asleep {
                        if firstAsleep == nil { firstAsleep = s.startDate }
                        lastAsleep = s.endDate
                    }
                }
                if b.inBedMin < b.asleepMin { b.inBedMin = b.asleepMin + b.awakeMin }
                b.bedEpoch = firstAsleep?.timeIntervalSince1970 ?? 0
                b.wakeEpoch = lastAsleep?.timeIntervalSince1970 ?? 0
                b.efficiency = b.inBedMin > 0 ? min(1, b.asleepMin / b.inBedMin) : 0
                cont.resume(returning: b.asleepMin > 0 ? b : nil)
            }
            store.execute(q)
        }
    }

    /// Latest HRV / resting HR as of a given day (falls back to most recent).
    func fetchHRV(asOf day: Date = Date()) async -> Double? {
        await fetchLatest(before: day, hrvType, unit: .secondUnit(with: .milli))
    }
    func fetchRestingHR(asOf day: Date = Date()) async -> Double? {
        await fetchLatest(before: day, restingHRType, unit: HKUnit.count().unitDivided(by: .minute()))
    }
    private func fetchLatest(before end: Date, _ type: HKQuantityType, unit: HKUnit) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// Rolling average of a quantity over the last `days` (for HRV/RHR baselines).
    func fetchAverage(_ type: HKQuantityType, unit: HKUnit, days: Int) async -> Double? {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                      options: .discreteAverage) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }
    func hrvBaseline() async -> Double? { await fetchAverage(hrvType, unit: .secondUnit(with: .milli), days: 30) }
    func rhrBaseline() async -> Double? { await fetchAverage(restingHRType, unit: HKUnit.count().unitDivided(by: .minute()), days: 30) }

    private func fetchWorkoutsThisWeek() async -> Int {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples?.count ?? 0)
            }
            store.execute(q)
        }
    }

    /// Most recent body-mass sample dated today (smart-scale auto-fill).
    private func fetchWeightTodayValue() async -> Double? {
        guard available else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: weightType, predicate: predicate, limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo)))
            }
            store.execute(q)
        }
    }

    // MARK: - Writing imported data

    /// Body-composition fields HealthKit accepts (visceral fat has no HK type → kept in-app only).
    func writeBodyComp(_ comp: BodyComp, settings: AppSettings) {
        guard available, settings.healthkit else { return }
        var samples: [HKQuantitySample] = []
        let now = Date()
        if let w = comp.weight, w > 0 {
            samples.append(HKQuantitySample(type: weightType, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: w), start: now, end: now))
        }
        if let bf = comp.bodyFat, bf > 0 {
            samples.append(HKQuantitySample(type: bodyFatType, quantity: HKQuantity(unit: .percent(), doubleValue: bf / 100), start: now, end: now))
        }
        if let lm = comp.leanMass, lm > 0 {
            samples.append(HKQuantitySample(type: leanMassType, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: lm), start: now, end: now))
        }
        if let bmi = comp.bmi, bmi > 0 {
            samples.append(HKQuantitySample(type: bmiType, quantity: HKQuantity(unit: .count(), doubleValue: bmi), start: now, end: now))
        }
        if !samples.isEmpty { store.save(samples) { _, _ in } }
    }

    /// Write a logged workout to Apple Health via HKWorkoutBuilder (HKWorkout init is deprecated on iOS 17+).
    func writeWorkout(_ w: Workout, settings: AppSettings) {
        guard available, settings.healthkit else { return }
        let mins = max(w.durationMin, w.totalSets * 2, 10)   // sensible floor if duration omitted
        let end = Date()
        let start = end.addingTimeInterval(-Double(mins) * 60)
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(for: w.kind)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        builder.beginCollection(withStart: start) { ok, _ in
            guard ok else { return }
            builder.endCollection(withEnd: end) { _, _ in
                builder.finishWorkout { _, _ in }
            }
        }
    }

    private static func activityType(for kind: String) -> HKWorkoutActivityType {
        switch kind {
        case "cardio": return .running
        case "mobility": return .flexibility
        case "other": return .mixedCardio
        default: return .traditionalStrengthTraining
        }
    }

    /// Map of lab name keywords → (HK type, unit). Only these are writable to Health.
    static let labWritableTypes: [String: HKQuantityType] = [
        "glucose": HKQuantityType(.bloodGlucose),
        "oxygen": HKQuantityType(.oxygenSaturation),
        "respiratory": HKQuantityType(.respiratoryRate),
        "temperature": HKQuantityType(.bodyTemperature),
        "resting heart": HKQuantityType(.restingHeartRate)
    ]

    /// Write any supported lab values; returns the names that were saved.
    func writeLabs(_ items: [LabItem], settings: AppSettings) -> [String] {
        guard available, settings.healthkit else { return [] }
        var written: [String] = []
        var samples: [HKQuantitySample] = []
        let now = Date()
        for item in items {
            let lower = item.name.lowercased()
            guard let (_, type) = Self.labWritableTypes.first(where: { lower.contains($0.key) }) else { continue }
            guard let unit = Self.labUnit(for: type, reported: item.unit) else { continue }
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: item.value), start: now, end: now))
            written.append(item.name)
        }
        if !samples.isEmpty { store.save(samples) { _, _ in } }
        return written
    }

    private static func labUnit(for type: HKQuantityType, reported: String) -> HKUnit? {
        switch type {
        case HKQuantityType(.bloodGlucose):
            return HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case HKQuantityType(.oxygenSaturation):
            return .percent()
        case HKQuantityType(.respiratoryRate), HKQuantityType(.restingHeartRate):
            return HKUnit.count().unitDivided(by: .minute())
        case HKQuantityType(.bodyTemperature):
            return reported.lowercased().contains("f") ? .degreeFahrenheit() : .degreeCelsius()
        default: return nil
        }
    }

    /// Write the day's logged calories & protein back to Health.
    func write(calories: Double?, protein: Double?, settings: AppSettings) {
        guard available, settings.healthkit else { return }
        var samples: [HKQuantitySample] = []
        if settings.hkWrite.calories, let c = calories, c > 0 {
            samples.append(HKQuantitySample(type: energyType,
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: c),
                                            start: Date(), end: Date()))
        }
        if settings.hkWrite.protein, let p = protein, p > 0 {
            samples.append(HKQuantitySample(type: proteinType,
                                            quantity: HKQuantity(unit: .gram(), doubleValue: p),
                                            start: Date(), end: Date()))
        }
        guard !samples.isEmpty else { return }
        store.save(samples) { _, _ in }
    }
}
