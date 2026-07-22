import Foundation
import HealthKit

/// One workout auto-detected from Apple Health / Fitness for a day. Transient (not persisted).
struct HealthWorkout: Identifiable, Equatable {
    let id: UUID
    var kind: String            // internal kind used by Active/training
    var name: String            // display, e.g. "Running"
    var symbol: String          // SF Symbol
    var start: Date
    var durationMin: Double
    var activeKcal: Double
    var distanceKm: Double
    var avgHR: Double
    var maxHR: Double
    /// Minutes spent in HR zones Z1…Z5 (by % of max HR). Empty if no HR data.
    var hrZoneMinutes: [Double] = []
    var isRunWalk: Bool { kind == "run" || kind == "walk" }
}

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
    private let respiratoryRateType = HKQuantityType(.respiratoryRate)
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
            stepType, weightType, activeEnergyType, restingHRType, hrvType, respiratoryRateType, sleepType,
            energyType, proteinType, bodyFatType, leanMassType, bmiType, HKObjectType.workoutType(),
            HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)
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
            await backfill()   // warm HRV/RHR/respiratory baselines from existing history so Readiness/Active calibrate on day one
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
    /// 90 days so the 30-day and "All" ranges show real history instead of being capped short.
    func loadStepsHistory(days: Int = 90) async {
        guard available else { return }
        // A collection query silently returns zero-sums when step reading was never authorized —
        // there is no error to catch. Asking first turns "empty chart forever" into the standard
        // permission sheet on the first visit (a no-op once the user has answered it).
        if !authorized { await requestAuthorization() }
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
        // All zeros = Health has nothing for us (denied read or a device with no step data).
        // Publish empty so Trends falls back to the steps logged in the app instead of rendering
        // a flat, empty-looking chart.
        stepsHistory = trimmed.allSatisfy { $0 == 0 } ? [] : trimmed
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
                var firstInBed: Date?
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
                        if firstInBed == nil { firstInBed = s.startDate }
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
                if let firstInBed, let firstAsleep, firstAsleep > firstInBed {
                    b.latencyMin = firstAsleep.timeIntervalSince(firstInBed) / 60
                }
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
    func respRateBaseline() async -> Double? { await fetchAverage(respiratoryRateType, unit: HKUnit.count().unitDivided(by: .minute()), days: 30) }

    func fetchRespiratoryRate(asOf day: Date = Date()) async -> Double? {
        await fetchLatest(before: day, respiratoryRateType, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    /// Median HRV (SDNN) over the same night window used for sleep detail — Apple's HRV samples are
    /// sparse spot-checks, so a single "latest" reading is noisy; the overnight median is more stable.
    func fetchHRVOvernightMedian(nightEnding day: Date = Date()) async -> Double? {
        await fetchMedian(hrvType, unit: .secondUnit(with: .milli), nightEnding: day)
    }

    /// Median respiratory rate over the same night window.
    func fetchRespiratoryRateOvernightMedian(nightEnding day: Date = Date()) async -> Double? {
        await fetchMedian(respiratoryRateType, unit: HKUnit.count().unitDivided(by: .minute()), nightEnding: day)
    }

    /// Daily discrete-average history for a quantity, oldest→newest, days without samples dropped.
    private func fetchDailyAverageHistory(_ type: HKQuantityType, unit: HKUnit, days: Int) async -> [Double] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date())) else { return [] }
        return await withCheckedContinuation { cont in
            let interval = DateComponents(day: 1)
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: nil,
                                                options: .discreteAverage, anchorDate: cal.startOfDay(for: start),
                                                intervalComponents: interval)
            q.initialResultsHandler = { _, collection, _ in
                var out: [Double] = []
                collection?.enumerateStatistics(from: start, to: end) { stat, _ in
                    if let v = stat.averageQuantity()?.doubleValue(for: unit) { out.append(v) }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    private func meanSD(_ values: [Double], ln: Bool = false) -> (mean: Double, sd: Double)? {
        let xs = ln ? values.filter { $0 > 0 }.map { log($0) } : values
        guard xs.count >= 2 else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
        return (mean, sqrt(variance))
    }

    /// 30-day baseline (mean, sd) of ln(HRV) — HRV is right-skewed, so scores compare against the
    /// log-normal distribution rather than raw ms.
    func hrvBaselineStats(days: Int = 30) async -> (mean: Double, sd: Double)? {
        meanSD(await fetchDailyAverageHistory(hrvType, unit: .secondUnit(with: .milli), days: days), ln: true)
    }
    func rhrBaselineStats(days: Int = 30) async -> (mean: Double, sd: Double)? {
        meanSD(await fetchDailyAverageHistory(restingHRType, unit: HKUnit.count().unitDivided(by: .minute()), days: days))
    }
    func respBaselineStats(days: Int = 30) async -> (mean: Double, sd: Double)? {
        meanSD(await fetchDailyAverageHistory(respiratoryRateType, unit: HKUnit.count().unitDivided(by: .minute()), days: days))
    }
    /// Number of nights with an HRV reading in the last `days` — gates score availability (need ≥7).
    func hrvSampleNights(days: Int = 30) async -> Int {
        (await fetchDailyAverageHistory(hrvType, unit: .secondUnit(with: .milli), days: days)).count
    }

    /// Backfills the last 30 days of sleep/HRV/RHR/respiratory/active-energy so baselines are usable
    /// on first launch instead of waiting a week — a no-op beyond warming HealthKit's cache since
    /// ScoreEngine recomputes baselines from live queries each time.
    func backfill() async {
        guard available else { return }
        _ = await hrvBaselineStats()
        _ = await rhrBaselineStats()
        _ = await respBaselineStats()
    }

    private func fetchMedian(_ type: HKQuantityType, unit: HKUnit, nightEnding day: Date) async -> Double? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let start = cal.date(byAdding: .hour, value: -6, to: dayStart) ?? dayStart
        let end = min(Date(), cal.date(byAdding: .hour, value: 12, to: dayStart) ?? day)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let values: [Double] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let vals = (samples as? [HKQuantitySample] ?? []).map { $0.quantity.doubleValue(for: unit) }
                cont.resume(returning: vals)
            }
            store.execute(q)
        }
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    // MARK: - Apple Fitness workouts (auto-detected)

    @Published var workoutsForDay: [HealthWorkout] = []

    /// Reads every workout Apple Health recorded for a day — type, duration, active calories,
    /// distance, average/max HR and a HR-zone breakdown — for the fitness card and the Active score.
    func loadWorkouts(for dateString: String, maxHR: Double) async {
        guard available else { workoutsForDay = []; return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: AppStore.parse(dateString))
        let end = min(Date(), cal.date(byAdding: .day, value: 1, to: start) ?? Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        var out: [HealthWorkout] = []
        for w in workouts {
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            var distKm = 0.0
            for dt in [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)] {
                if let d = w.statistics(for: dt)?.sumQuantity()?.doubleValue(for: .meter()), d > 0 { distKm = d / 1000; break }
            }
            let hr = await fetchHRStats(start: w.startDate, end: w.endDate, maxHR: maxHR)
            let meta = Self.workoutMeta(w.workoutActivityType)
            out.append(HealthWorkout(id: w.uuid, kind: meta.kind, name: meta.name, symbol: meta.symbol,
                                     start: w.startDate, durationMin: w.duration / 60, activeKcal: kcal,
                                     distanceKm: distKm, avgHR: hr.avg, maxHR: hr.max, hrZoneMinutes: hr.zones))
        }
        workoutsForDay = out
    }

    /// Average/max HR + zone minutes over a workout window (empty zones when no HR samples).
    private func fetchHRStats(start: Date, end: Date, maxHR: Double) async -> (avg: Double, max: Double, zones: [Double]) {
        let hrType = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [Double] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: (s as? [HKQuantitySample])?.map { $0.quantity.doubleValue(for: unit) } ?? [])
            }
            store.execute(q)
        }
        guard !samples.isEmpty else { return (0, 0, []) }
        let avg = samples.reduce(0, +) / Double(samples.count)
        let peak = samples.max() ?? 0
        let mhr = maxHR > 0 ? maxHR : 190
        let durationMin = end.timeIntervalSince(start) / 60
        var buckets = [Double](repeating: 0, count: 5)   // Z1<60% … Z5≥90%
        for hr in samples {
            let pct = hr / mhr
            let z = pct < 0.6 ? 0 : (pct < 0.7 ? 1 : (pct < 0.8 ? 2 : (pct < 0.9 ? 3 : 4)))
            buckets[z] += 1
        }
        let total = Double(samples.count)
        return (avg, peak, buckets.map { $0 / total * durationMin })
    }

    /// Map a HealthKit activity type to our (kind, display name, SF Symbol).
    private static func workoutMeta(_ t: HKWorkoutActivityType) -> (kind: String, name: String, symbol: String) {
        switch t {
        case .running: return ("run", "Running", "figure.run")
        case .walking, .hiking: return ("walk", "Walk", "figure.walk")
        case .cycling: return ("cardio", "Cycling", "figure.outdoor.cycle")
        case .traditionalStrengthTraining, .functionalStrengthTraining: return ("strength", "Strength", "dumbbell.fill")
        case .highIntensityIntervalTraining: return ("cardio", "HIIT", "figure.highintensity.intervaltraining")
        case .swimming: return ("cardio", "Swimming", "figure.pool.swim")
        case .yoga: return ("mobility", "Yoga", "figure.yoga")
        case .flexibility, .cooldown: return ("mobility", "Mobility", "figure.flexibility")
        case .coreTraining: return ("strength", "Core", "figure.core.training")
        default: return ("other", "Workout", "figure.mixed.cardio")
        }
    }

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
