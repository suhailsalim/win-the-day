import SwiftUI
import PhotosUI

struct TodayView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var health: HealthManager
    @EnvironmentObject var prayer: PrayerManager
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var studyTimer: StudyTimer
    @EnvironmentObject var fasting: FastingManager
    @EnvironmentObject var weather: WeatherManager
    @State private var showCatalog = false
    @State private var showHistory = false
    @State private var showQibla = false
    @State private var showHabits = false
    @State private var showStudy = false
    @State private var showChat = false
    @State private var showWorkout = false
    @State private var editWorkout: Workout?
    @State private var editingTimeKey: MealKey?
    @State private var photoItem: PhotosPickerItem?
    @State private var showRingEditor = false
    @State private var ringDetail: RingDef?
    @State private var showAllQuickLog = false
    @State private var exportedText: ExportedText?
    @State private var showFocus = false
    @State private var showFoodAdd = false
    @State private var foodAddMeal = "breakfast"
    @State private var showCheckIn = false
    @State private var showWindDown = false
    @EnvironmentObject var windDownRouter: WindDownRouter

    private struct MealKey: Identifiable { let id: String }
    private struct ExportedText: Identifiable { let id = UUID(); let text: String }

    var body: some View {
        VStack(spacing: 0) {
            dateHeader
            tipCard
            ForEach(store.modules.orderedKeys, id: \.self) { key in
                moduleView(key)
            }

            Text(store.draft.isMeaningful ? "Saved automatically" : "Start logging — it saves as you go")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.27).opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
        .sheet(isPresented: $showCatalog) { CatalogView() }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .sheet(isPresented: $showQibla) { QiblaView() }
        .sheet(isPresented: $showHabits) { HabitsEditorView() }
        .sheet(isPresented: $showStudy) { StudyManageView() }
        .sheet(isPresented: $showChat) { CoachChatListView() }
        .sheet(isPresented: $showWorkout) { WorkoutView() }
        .sheet(item: $editWorkout) { w in WorkoutView(editing: w) }
        .sheet(item: $editingTimeKey) { mk in mealTimeSheet(mk.id) }
        .sheet(isPresented: $showRingEditor) { RingEditorView() }
        .sheet(item: $ringDetail) { ring in
            RingDetailView(ring: ring, result: store.ringResult(ring, prayerTimes: prayer.today, nextFajr: prayer.nextFajr))
        }
        .sheet(item: $exportedText) { ShareSheet(items: [$0.text]) }
        .sheet(isPresented: $showFoodAdd) { FoodAddSheet(mealKey: foodAddMeal) }
        .sheet(isPresented: $showCheckIn) {
            // `initial` is read at presentation time, so History navigation backfills the viewed day.
            CheckInSheet(initial: store.draft.checkIn) { c in
                store.updateCheckIn(c)
                Task { await store.computeReadiness(for: store.date, health: health) }
            }
        }
        // Evening wind-down: opened from the header chip or by tapping the `winddown-` notification.
        .sheet(isPresented: $showWindDown) { WindDownView() }
        .onChange(of: windDownRouter.open) { _, open in
            if open { showWindDown = true; windDownRouter.open = false }
        }
        .task(id: store.sleepPlanTonight?.recommendedBedEpoch) { store.refreshWindDown(force: true) }
        // Milestones: one calm sheet per earned record (or one summary for a historical batch).
        .sheet(item: Binding(get: { store.justEarned },
                             set: { if $0 == nil { store.dismissMilestone() } })) { event in
            MilestoneCelebrationSheet(event: event)
        }
        .fullScreenCover(isPresented: $showFocus) { FocusScreenView() }
        // "Start a focus session" (Siri/Shortcuts) opens the app; the store raises this once it's
        // reconciled, so the cover opens whether the app cold-launched or was already running.
        .onChange(of: store.pendingFocusOpen) { _, open in
            if open { showFocus = true; store.pendingFocusOpen = false }
        }
        // …and once on appear, for the cold launch where the flag is already up by the time
        // this view starts observing it.
        .task { if store.pendingFocusOpen { showFocus = true; store.pendingFocusOpen = false } }
        .task { await store.refreshSuggestion() }
        .task { prayer.start() }
        .task { weather.start(); store.weatherContext = weather.plannerSummary }
        .task { hydration.start(); store.publishSnapshot() }
        .task(id: store.date) {
            await health.loadForDay(store.date)
            if store.isToday {
                await health.refresh()
                store.autofillWeight(health.weightToday)
                store.autofillActivity(steps: health.stepsToday, activeKcal: health.activeEnergyToday)
            }
            await store.computeReadiness(for: store.date, health: health)
            await health.loadWorkouts(for: store.date, maxHR: 208 - 0.7 * store.targets.ageYears)
            store.autofillJog(from: health.workoutsForDay)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    store.addPhoto(img)
                }
                photoItem = nil
            }
        }
    }

    // MARK: - Hydration

    private var hydrationSection: some View {
        let target = max(1, hydration.targetMl)
        let progress = Double(store.waterMl) / Double(target)
        return HStack(spacing: 16) {
            WaterBottleView(progress: progress, currentMl: store.waterMl, targetMl: hydration.targetMl)
            VStack(alignment: .leading, spacing: 10) {
                Text(progress >= 1 ? "Target hit — nice 💧" : "\(max(0, hydration.targetMl - store.waterMl)) ml to go")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    waterButton("+\(hydration.glassMl)") { store.addWater(hydration.glassMl) }
                    waterButton("+500") { store.addWater(500) }
                }
                HStack(spacing: 8) {
                    waterButton("Glass") { store.addWater(hydration.glassMl) }
                    if store.waterMl > 0 {
                        waterButton("−\(hydration.glassMl)") { store.addWater(-hydration.glassMl) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassList()
    }

    private func waterButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x1E8AE0))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color(hex: 0x6FB7FF).opacity(0.18))
                    .overlay(Capsule().strokeBorder(Color(hex: 0x2E8AE0).opacity(0.35), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Meal nudge (time-aware)

    @ViewBuilder private var mealNudgeBanner: some View {
        if store.isToday, let nudge = store.mealNudge {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill").font(.system(size: 12)).foregroundStyle(Theme.accentDark)
                Text("Around now — jot down \(nudge.label) while it\u{2019}s fresh.")
                    .font(.system(size: 13)).foregroundStyle(Theme.tipText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.tipBG)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.tipBorder, lineWidth: 0.5)))
            .padding(.bottom, 8)
        }
    }

    // MARK: - Photos

    private var photosSection: some View {
        let hasPhotos = !store.draft.photos.isEmpty
        return VStack(spacing: 10) {
            if hasPhotos {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.draft.photos, id: \.self) { name in
                            if let img = PhotoStore.load(name) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 100, height: 130).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        Button { store.removePhoto(name) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 18)).foregroundStyle(.white, .black.opacity(0.4))
                                                .padding(5)
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: 9) {
                    Image(systemName: "camera.fill").foregroundStyle(Theme.accentDark)
                    Text(hasPhotos ? "Add another photo" : "Add a progress photo for this day")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .glassList()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Module dispatch (renders sections in the user's chosen order)

    @ViewBuilder private func moduleView(_ key: String) -> some View {
        if store.modules.enabled(key) {
            switch key {
            case "rings": ringsModule
            case "coach": coachCard
            case "weather": weatherModule
            case "prayer": prayerCard
            case "fasting": fastingModule
            case "sleep": sleepModule
            case "health": healthCard
            case "meals": mealsModule
            case "hydration": hydrationModule
            case "quickLog": quickLog
            case "habits": habitsSection
            case "score": scoreCard
            case "workStudy": studySection
            case "training": trainingModule
            case "photos": photosModule
            default: EmptyView()
            }
        }
    }

    // MARK: - Rings (adjustable Whoop-style ring row)

    @ViewBuilder private var ringsModule: some View {
        HStack {
            SectionHeader(text: "Rings", color: store.moduleColor("rings"))
            Spacer()
            Button { showRingEditor = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
            }.padding(.top, 14)
        }
        HStack(spacing: 4) {
            ForEach(store.visibleRings) { ring in
                let result = store.ringResult(ring, prayerTimes: prayer.today, nextFajr: prayer.nextFajr)
                Button { ringDetail = ring } label: {
                    VStack(spacing: 6) {
                        RingGaugeView(fraction: result.fraction, value: result.displayValue, label: ring.displayTitle,
                                     color: ringColor(ring, result), available: result.available)
                        Text(result.caption).font(.system(size: 10)).foregroundStyle(Theme.tertiaryInk).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .glassList(cornerRadius: 20)
        .padding(.top, 14)
    }

    private func ringColor(_ def: RingDef, _ r: RingResult) -> Color {
        if def.colorHex != 0 { return Color(hex: def.colorHex) }
        switch r.band {
        case .low: return Color(hex: 0xD86B4A)
        case .mid: return Theme.accentDark
        case .high: return Theme.sage
        }
    }

    @ViewBuilder private var mealsModule: some View {
        HStack {
            SectionHeader(text: "What you ate", color: store.moduleColor("meals"))
            Spacer()
            if store.draft.isMeaningful {
                Button { exportedText = ExportedText(text: store.exportDayText(store.draft.date)) } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }
                .padding(.top, 22)
            }
        }
        foodLogCard
        foodTotalsBar
    }

    private var mealBuckets: [MealBucket] {
        // Meals that have entries, plus the time-of-day nudge meal, in canonical order.
        let withEntries = Set(store.draft.foodEntries.map { $0.mealKey })
        let nudge = store.mealNudge?.key
        return MealBucket.allCases.filter { withEntries.contains($0.rawValue) || $0.rawValue == nudge }
    }

    @ViewBuilder private var foodLogCard: some View {
        if store.draft.foodEntries.isEmpty && mealBuckets.isEmpty {
            Button { foodAddMeal = store.mealNudge?.key ?? "breakfast"; showFoodAdd = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentDark)
                    Text("Add what you ate — search a food, scan, or describe your meal.")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.secondaryInk).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity).glassList()
            }.buttonStyle(.plain).padding(.top, 4)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(mealBuckets.enumerated()), id: \.element.id) { idx, bucket in
                    let entries = store.foodEntries(bucket.rawValue)
                    HStack(spacing: 7) {
                        Image(systemName: bucket.icon).font(.system(size: 12)).foregroundStyle(Theme.accentDark)
                        Text(bucket.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                        if store.isToday && store.mealNudge?.key == bucket.rawValue {
                            Text("now").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Theme.accentDark))
                        }
                        Spacer()
                        if entries.isEmpty {
                            Text("\(Int(entries.reduce(0) { $0 + $1.totalKcal })) kcal").opacity(0)
                        } else {
                            Text("\(Int(entries.reduce(0) { $0 + $1.totalKcal })) kcal")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.tertiaryInk)
                        }
                        Button { foodAddMeal = bucket.rawValue; showFoodAdd = true } label: {
                            Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accentDark)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).padding(.top, idx == 0 ? 12 : 14).padding(.bottom, 4)
                    ForEach(entries) { e in
                        FoodEntryRow(entry: e)
                        if e.id != entries.last?.id { Hairline().padding(.leading, 14) }
                    }
                    if entries.isEmpty {
                        Text("Nothing yet — tap + to add.").font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 8)
                    }
                    if idx < mealBuckets.count - 1 { Hairline() }
                }
            }
            .padding(.bottom, 6)
            .glassList()
            .padding(.top, 4)

            Button { foodAddMeal = store.mealNudge?.key ?? "snacks"; showFoodAdd = true } label: {
                Label("Add food", systemImage: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentDark)
                    .frame(maxWidth: .infinity).padding(.vertical, 11).glassList()
            }.buttonStyle(.plain).padding(.top, 8)
        }
    }

    private var foodTotalsBar: some View {
        let t = store.foodTotals
        let eating = store.eatingScoreResult(for: store.draft)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int((Double(store.draft.calories) ?? t.kcal))) kcal")
                    .font(Theme.display(20)).foregroundStyle(Theme.ink)
                Text("\(Int((Double(store.draft.proteinG) ?? t.protein)))g protein · \(Int(t.carbs))C \(Int(t.fat))F")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
            if eating.available {
                VStack(spacing: 1) {
                    Text("\(eating.score)").font(Theme.display(20)).foregroundStyle(eatingColor(eating.score))
                    Text("eating").font(.system(size: 10)).foregroundStyle(Theme.tertiaryInk)
                }
            }
        }
        .padding(14).glassList().padding(.top, 10)
    }
    private func eatingColor(_ s: Int) -> Color { s >= 70 ? Theme.sage : (s >= 45 ? Theme.accentDark : Color(hex: 0xD86B4A)) }

    @ViewBuilder private var hydrationModule: some View {
        SectionHeader(text: "Hydration", color: store.moduleColor("hydration"))
        hydrationSection
    }

    // MARK: - Weather (compact tile) + AI tips rotator

    /// A fixed narrow width, not a `layoutPriority` hint (which only governs compression order,
    /// not a proportional split) — this is what actually gets a reliable ¼-ish tile every time.
    private static let weatherTileWidth: CGFloat = 92

    @ViewBuilder private var weatherModule: some View {
        if store.isToday, weather.now != nil {
            HStack(alignment: .top, spacing: 10) {
                weatherMiniTile
                tipsRotator.frame(maxWidth: .infinity)
            }
            .padding(.top, 14)
            .task { await store.refreshDayTips() }
        }
    }

    @ViewBuilder private var weatherMiniTile: some View {
        if let n = weather.now {
            let cond = WeatherManager.condition(n.code)
            let advice = weather.outdoorAdvice()
            GlassCard(padding: 10, cornerRadius: 20, tint: Color(hex: 0x2E8AE0).opacity(0.10)) {
                VStack(spacing: 3) {
                    Image(systemName: cond.symbol).font(.system(size: 22)).foregroundStyle(Color(hex: 0x2E8AE0))
                    Text("\(Int(n.tempC))\u{00b0}").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(advice.ok ? "Go out" : "Indoors")
                        .font(.system(size: 10, weight: .medium)).lineLimit(1)
                        .foregroundStyle(advice.ok ? Theme.sage : Color(hex: 0xD86B4A))
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: Self.weatherTileWidth)
        }
    }

    private var tipsRotator: some View {
        TipsRotatorView(tips: store.dayTips, loading: store.dayTipsLoading) {
            await store.refreshDayTips(force: true)
        }
    }

    // MARK: - Sleep & readiness

    @ViewBuilder private var sleepModule: some View {
        if let s = store.draft.sleep, store.draft.readiness > 0 {
            SectionHeader(text: "Sleep & readiness", color: store.moduleColor("sleep"))
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        RingGaugeView(fraction: Double(store.draft.sleepScore) / 100, value: "\(store.draft.sleepScore)",
                                     label: "sleep", color: bandColor(store.draft.sleepScore), size: 62)
                        RingGaugeView(fraction: Double(store.draft.readiness) / 100, value: "\(store.draft.readiness)",
                                     label: "ready", color: bandColor(store.draft.readiness), size: 62)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(readinessWord(store.draft.readiness)).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text(String(format: "%.1fh asleep", s.asleepHours))
                                .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                            if let bed = s.bedDate, let wake = s.wakeDate {
                                Text("\(clockStr(bed)) → \(clockStr(wake))" + (s.latencyMin > 0 ? " · \(Int(s.latencyMin))m to fall asleep" : ""))
                                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                            }
                        }
                        Spacer()
                    }
                    if s.hasStages { sleepStageBars(s) }
                    if !store.readinessFactors.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(store.readinessFactors.prefix(4)) { f in
                                HStack(spacing: 6) {
                                    if f.delta != 0 {
                                        Text(f.delta > 0 ? "+\(f.delta)" : "\(f.delta)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(f.delta > 0 ? Theme.sage : Color(hex: 0xD86B4A))
                                            .frame(width: 28, alignment: .leading)
                                    } else {
                                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Theme.tertiaryInk).frame(width: 28, alignment: .leading)
                                    }
                                    Text("\(f.label) — \(f.note)").font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    checkInRow
                    let trend = store.recentScores(days: 14).readiness
                    if trend.count >= 2 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Readiness · 14 days").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.tertiaryInk)
                            LineChartView(values: trend, color: Theme.accentDark, target: 70)
                                .frame(height: 70)
                        }
                        .padding(.top, 2)
                    }
                    if let plan = store.sleepPlanTonight { tonightPlanCard(plan) }
                }
            }
            .padding(.top, 14)
        }
    }

    /// Self-report entry point + the sensor-only transparency line, so an adjusted score is never a mystery.
    private var checkInRow: some View {
        let done = store.draft.checkIn != DayCheckIn()
        return VStack(alignment: .leading, spacing: 6) {
            if store.readinessSensorOnly > 0 {
                Text("Sensor-only readiness: \(store.readinessSensorOnly) · adjusted by your check-in")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
            }
            Button { showCheckIn = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                    Text(done ? "Check-in logged" : "How do you feel?")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(done ? .white : Theme.accentDark)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    Capsule().fill(done ? Theme.accentDark : Theme.accentDark.opacity(0.12))
                        .overlay(Capsule().strokeBorder(Theme.accentDark.opacity(done ? 0 : 0.3), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func bandColor(_ score: Int) -> Color {
        score >= 70 ? Theme.sage : (score >= 45 ? Theme.accentDark : Color(hex: 0xD86B4A))
    }

    @ViewBuilder private func tonightPlanCard(_ plan: SleepPlanner.Plan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Hairline().padding(.vertical, 2)
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 12)).foregroundStyle(Theme.accentDark)
                Text("Tonight's plan").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            Text(String(format: "Aim for %.1fh — bedtime around %@", plan.needHours, clockStr(Date(timeIntervalSince1970: plan.recommendedBedEpoch))))
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
            let cutoffStr = clockStr(Date(timeIntervalSince1970: plan.dinnerCutoffEpoch))
            if let dinnerEpoch = store.draft.mealTimes["dinner"], dinnerEpoch > 0 {
                let ok = dinnerEpoch <= plan.dinnerCutoffEpoch
                HStack(spacing: 5) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(ok ? Theme.sage : Color(hex: 0xD86B4A))
                    Text(ok ? "Dinner timing looks good for that bedtime." : "Dinner was after \(cutoffStr) — may push sleep later.")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
            } else {
                Text("Eat dinner by \(cutoffStr) for that bedtime.")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
            }
        }
    }

    private func sleepStageBars(_ s: SleepBreakdown) -> some View {
        let total = max(1, s.deepMin + s.remMin + s.coreMin + s.awakeMin)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    stageBar(geo.size.width, s.deepMin / total, Color(hex: 0x3B43C0))
                    stageBar(geo.size.width, s.remMin / total, Color(hex: 0x6E7BFF))
                    stageBar(geo.size.width, s.coreMin / total, Color(hex: 0x9DB0FF))
                    stageBar(geo.size.width, s.awakeMin / total, Color(hex: 0xE0C089))
                }
            }
            .frame(height: 8)
            HStack(spacing: 10) {
                stageLegend("Deep", Color(hex: 0x3B43C0), s.deepMin)
                stageLegend("REM", Color(hex: 0x6E7BFF), s.remMin)
                stageLegend("Core", Color(hex: 0x9DB0FF), s.coreMin)
            }
        }
    }
    private func stageBar(_ width: CGFloat, _ frac: Double, _ color: Color) -> some View {
        Capsule().fill(color).frame(width: max(0, width * frac), height: 8)
    }
    private func stageLegend(_ name: String, _ color: Color, _ mins: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(name) \(Int(mins))m").font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
        }
    }
    private func readinessWord(_ s: Int) -> String {
        s >= 80 ? "Primed" : (s >= 65 ? "Ready" : (s >= 45 ? "Moderate" : "Take it easy"))
    }
    private func clockStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }

    // MARK: - Fasting

    @ViewBuilder private var fastingModule: some View {
        SectionHeader(text: prayer.ramadanMode ? "Fasting · Ramadan" : "Fasting",
                      color: store.moduleColor("fasting"))
        if prayer.ramadanMode { ramadanCard }
        fastingTimerCard
    }

    private var ramadanCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date
            let inWindow = isFastingWindow(now)
            GlassCard(padding: 16, cornerRadius: 20, tint: Color(hex: 0x3B4A7C).opacity(0.12)) {
                HStack(spacing: 13) {
                    IconTile(symbol: "moon.stars.fill", colors: [Color(hex: 0x6470A6), Color(hex: 0x3B4A7C)], size: 36, corner: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(inWindow ? "Iftar in \(countdown(to: prayer.iftar, from: now))"
                                      : "Suhoor ends in \(countdown(to: prayer.suhoorEnd, from: now))")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        HStack(spacing: 10) {
                            Text("Suhoor \(timeStr(prayer.suhoorEnd))").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
                            Text("Iftar \(timeStr(prayer.iftar))").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    Spacer()
                }
            }
            .padding(.bottom, 4)
        }
    }

    // Only drive the per-second timeline while actually fasting; otherwise the periodic timer
    // ticked 86,400×/day re-laying out the whole card even when there was nothing counting.
    @ViewBuilder private var fastingTimerCard: some View {
        if fasting.isFasting {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in fastingCardBody(now: ctx.date) }
        } else {
            fastingCardBody(now: Date())
        }
    }

    private func fastingCardBody(now: Date) -> some View {
        let elapsed = fasting.elapsedHours(now: now)
        let progress = fasting.progress(now: now)
        return Group {
            GlassCard(padding: 16) {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fasting.isFasting ? "Fasting" : "Not fasting")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text("\(fasting.protocolName == "custom" ? "\(Int(fasting.targetHours))h" : fasting.protocolName) window · streak \(fasting.streak())d")
                                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                        }
                        Spacer()
                        Button {
                            if fasting.isFasting { fasting.endFast() } else { fasting.startFast() }
                        } label: {
                            Text(fasting.isFasting ? "End fast" : "Start fast")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(fasting.isFasting ? Theme.accentDark : .white)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(Capsule().fill(fasting.isFasting ? AnyShapeStyle(Color.white.opacity(0.6)) : AnyShapeStyle(Theme.accentDark)))
                                .overlay(Capsule().strokeBorder(Theme.accent.opacity(fasting.isFasting ? 0.4 : 0), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    if fasting.isFasting {
                        VStack(spacing: 5) {
                            HStack {
                                Text(String(format: "%.1fh", elapsed)).font(Theme.serif(24)).foregroundStyle(Theme.ink)
                                Text("of \(Int(fasting.targetHours))h").font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                                Spacer()
                                Text("\(Int(progress * 100))%").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(progress >= 1 ? Theme.sage : Theme.accentDark)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(white: 0.5).opacity(0.15)).frame(height: 8)
                                    Capsule().fill(progress >= 1 ? Theme.sage : Theme.accentDark)
                                        .frame(width: geo.size.width * progress, height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func isFastingWindow(_ now: Date) -> Bool {
        guard let fajr = prayer.suhoorEnd, let maghrib = prayer.iftar else { return false }
        return now >= fajr && now < maghrib
    }

    private func countdown(to date: Date?, from now: Date) -> String {
        guard let date else { return "—" }
        var secs = Int(date.timeIntervalSince(now))
        if secs < 0 { secs += 24 * 3600 }   // wrap to tomorrow for display
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func timeStr(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    @ViewBuilder private var trainingModule: some View {
        HStack {
            SectionHeader(text: "Training & body", color: store.moduleColor("training"))
            Spacer()
            Button { showWorkout = true } label: {
                Label("Log workout", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
            }
            .padding(.trailing, 8).padding(.top, 22)
        }
        fitnessCard
        workoutsList
        trainingCard
    }

    // MARK: - Apple Fitness (auto-detected workouts)

    @ViewBuilder private var fitnessCard: some View {
        let workouts = health.workoutsForDay
        if !workouts.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run").font(.system(size: 12)).foregroundStyle(Theme.accentDark)
                    Text("From Apple Fitness").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    Text("feeds Active").font(.system(size: 10.5)).foregroundStyle(Theme.tertiaryInk)
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
                ForEach(workouts) { w in
                    fitnessRow(w)
                    if w.id != workouts.last?.id { Hairline().padding(.leading, 14) }
                }
            }
            .padding(.bottom, 10).glassList().padding(.top, 10)
        }
    }

    private func fitnessRow(_ w: HealthWorkout) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: w.symbol).font(.system(size: 15)).foregroundStyle(Theme.accentDark).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(w.name).font(.system(size: 15)).foregroundStyle(Theme.ink)
                    Text(fitnessSub(w)).font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                }
                Spacer()
                if w.activeKcal > 0 {
                    Text("\(Int(w.activeKcal)) kcal").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                }
            }
            if w.hrZoneMinutes.contains(where: { $0 > 0 }) { hrZoneBar(w.hrZoneMinutes) }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func fitnessSub(_ w: HealthWorkout) -> String {
        var parts = ["\(Int(w.durationMin)) min"]
        if w.distanceKm > 0 { parts.append(String(format: "%.2f km", w.distanceKm)) }
        if w.avgHR > 0 { parts.append("♥ \(Int(w.avgHR)) avg · \(Int(w.maxHR)) max") }
        return parts.joined(separator: " · ")
    }

    private func hrZoneBar(_ zones: [Double]) -> some View {
        let colors = [Color(hex: 0x8FB0FF), Color(hex: 0x5F9E7A), Color(hex: 0xE0B341), Color(hex: 0xE0873A), Color(hex: 0xD8503A)]
        let total = max(1, zones.reduce(0, +))
        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { i, m in
                        if m > 0 { Capsule().fill(colors[min(i, 4)]).frame(width: max(2, geo.size.width * m / total)) }
                    }
                }
            }.frame(height: 6)
            Text("HR zones Z1–Z5").font(.system(size: 10)).foregroundStyle(Theme.tertiaryInk)
        }
    }

    @ViewBuilder private var workoutsList: some View {
        let workouts = store.draft.workouts
        if !workouts.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { idx, w in
                    Button { editWorkout = w } label: {
                        HStack(spacing: 11) {
                            IconTile(symbol: Workout.symbol(w.kind),
                                     colors: [Theme.accent, Color(hex: 0x3B4A7C)], size: 30, corner: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.title.isEmpty ? Workout.label(w.kind) : w.title)
                                    .font(.system(size: 15.5, weight: .medium)).foregroundStyle(Theme.ink)
                                Text(workoutSummary(w)).font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk)
                            }
                            Spacer()
                            if w.healthWritten {
                                Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(Color(hex: 0xFB1E4B).opacity(0.7))
                            }
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    if idx < workouts.count - 1 { Hairline() }
                }
            }
            .glassList()
            .padding(.top, 10)
        }
    }

    private func workoutSummary(_ w: Workout) -> String {
        var bits: [String] = []
        if !w.exercises.isEmpty { bits.append("\(w.exercises.count) exercise\(w.exercises.count == 1 ? "" : "s")") }
        if w.volume > 0 { bits.append("\(Int(w.volume)) kg vol") }
        if w.durationMin > 0 { bits.append("\(w.durationMin) min") }
        return bits.isEmpty ? Workout.label(w.kind) : bits.joined(separator: " · ")
    }

    @ViewBuilder private var photosModule: some View {
        SectionHeader(text: "Photos", color: store.moduleColor("photos"))
        photosSection
    }

    // MARK: - Date header (navigate to any past day)

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.todaySubtitle)
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.secondaryInk)
                    Text(store.dayLabel)
                        .font(.system(size: 34, weight: .bold)).tracking(0.3).foregroundStyle(Theme.ink)
                }
                Spacer()
                HStack(spacing: 4) {
                    navButton("chevron.left", enabled: true) { store.shiftDay(by: -1) }
                    navButton("calendar", enabled: true) { showHistory = true }
                    navButton("chevron.right", enabled: store.canGoForward) { store.shiftDay(by: 1) }
                }
            }
            statusChip
            windDownHeaderRow
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Wind-down (focus set last night + tonight's entry point)

    /// Last night's focus for today, and — once the evening starts — the way into the ritual.
    @ViewBuilder private var windDownHeaderRow: some View {
        let focus = store.draft.mainFocus
        if store.isToday && (!focus.isEmpty || store.isWindDownTime) {
            HStack(spacing: 6) {
                if !focus.isEmpty { focusChip(focus) }
                if store.isWindDownTime { windDownChip }
                Spacer(minLength: 0)
            }
        }
    }

    private func focusChip(_ focus: String) -> some View {
        let done = store.draft.mainFocusDone
        return Button { store.toggleMainFocusDone() } label: {
            HStack(spacing: 5) {
                Image(systemName: done ? "checkmark.circle.fill" : "target").font(.system(size: 10))
                Text(focus).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(done ? .white : Theme.accentDark)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(done ? Theme.sage : Theme.accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private var windDownChip: some View {
        Button { showWindDown = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 10))
                Text("Wind down").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Theme.accentDark))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var statusChip: some View {
        let effective = store.effectiveStatus(for: store.date)
        let shown = store.draft.status != "normal" ? store.draft.status : effective
        Menu {
            ForEach(DayStatus.all, id: \.id) { s in
                Button { store.setDayStatus(s.id) } label: { Label(s.label, systemImage: s.symbol) }
            }
        } label: {
            if shown != "normal" {
                HStack(spacing: 4) {
                    Image(systemName: DayStatus.symbol(shown)).font(.system(size: 10))
                    Text(DayStatus.label(shown) + (store.draft.status == "normal" && effective == "travel" ? " (auto)" : ""))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: 0x5B43E0)))
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "flag").font(.system(size: 10))
                    Text("Mark day").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.accentDark)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
            }
        }
    }

    private func navButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Theme.accentDark : Color(white: 0.27).opacity(0.25))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.5))
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Prayer times card

    @ViewBuilder private var prayerCard: some View {
        if prayer.enabled, let times = prayer.today {
            let next = prayer.nextPrayer
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "moon.stars.fill").font(.system(size: 13)).foregroundStyle(Theme.accentDark)
                        Text(prayer.placeName.isEmpty ? "Prayer times" : "Prayers · \(prayer.placeName)")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    if let next {
                        Text("Next: \(next.0.label) \(timeStr(next.1))")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accentDark)
                    }
                    Button { showQibla = true } label: {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                            .padding(.leading, 8)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 10)
                HStack(spacing: 6) {
                    ForEach(times.ordered.filter { $0.0.isPrayer }, id: \.0) { name, date in
                        let isNext = next?.0 == name
                        let prayed = store.isPrayed(name)
                        let band = store.prayerBand(name)
                        Button { store.togglePrayer(name, times: times, nextFajr: prayer.nextFajr) } label: {
                            VStack(spacing: 4) {
                                Text(name.label).font(.system(size: 11)).foregroundStyle(Theme.secondaryInk)
                                Text(prayed ? band.label : timeStr(date))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(prayed ? .white : (isNext ? Theme.accentDark : Theme.ink))
                                Image(systemName: prayed ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(prayed ? .white : Color(white: 0.27).opacity(0.3))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(prayed ? AnyShapeStyle(Theme.sage)
                                                 : AnyShapeStyle(isNext ? Theme.accent.opacity(0.16) : Color.clear))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Tap a prayer once you\u{2019}ve prayed it.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
            .padding(14)
            .glassList(cornerRadius: 20)
            .padding(.top, 12)
        }
    }

    private func timeStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }

    // MARK: - AI coach suggestion

    @ViewBuilder private var coachCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                IconTile(symbol: "sparkles", colors: [Theme.accent, Color(hex: 0x3B4A7C)], size: 32, corner: 10)
                if store.suggestionLoading && store.suggestion.isEmpty {
                    Text("Thinking about your day…")
                        .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                } else if store.suggestion.isEmpty {
                    Text("Your AI coach can see your logs — ask it anything.")
                        .font(.system(size: 14.5)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(store.suggestion)
                        .font(.system(size: 14.5)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { Task { await store.refreshSuggestion(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiaryInk)
                }
                .buttonStyle(.plain)
            }
            Button { showChat = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 12))
                    Text(store.chatMessages.isEmpty ? "Ask the coach" : "Continue chat")
                        .font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).opacity(0.5)
                }
                .foregroundStyle(Theme.accentDark)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.accent.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 0.5))
        )
        .padding(.top, 14)
    }

    // MARK: - Quick log (catalog items)

    @ViewBuilder private var quickLog: some View {
        HStack {
            SectionHeader(text: "Quick log", color: store.moduleColor("quickLog"))
            Spacer()
            Button { showCatalog = true } label: {
                Text("Library").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentDark)
            }
            .padding(.trailing, 8).padding(.top, 22)
        }

        let allSupps = store.items(of: .supplement)
        let allFoods = store.items(of: .food)
        if allSupps.isEmpty && allFoods.isEmpty {
            Button { showCatalog = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentDark)
                    Text("Add your regular supplements & foods — then tap to log them daily.")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.secondaryInk)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .glassList()
            }
            .buttonStyle(.plain)
        } else {
            let mealKey = store.mealNudge?.key
            let suggestedSupps = store.suggestedQuickAddItems(of: .supplement, mealKey: mealKey)
            let suggestedFoods = store.suggestedQuickAddItems(of: .food, mealKey: mealKey)
            let loggedElsewhere = (allSupps + allFoods).filter { store.loggedQty($0.id) > 0 }
                .filter { !suggestedSupps.contains($0) && !suggestedFoods.contains($0) }
            VStack(spacing: 10) {
                if !suggestedSupps.isEmpty { chipGroup(title: "Supplements", items: suggestedSupps) }
                if !suggestedFoods.isEmpty { chipGroup(title: "Foods · now", items: suggestedFoods) }
                if !loggedElsewhere.isEmpty { chipGroup(title: "Also logged today", items: loggedElsewhere) }
                if showAllQuickLog {
                    if !allSupps.isEmpty { chipGroup(title: "All supplements", items: allSupps) }
                    if !allFoods.isEmpty { chipGroup(title: "All foods", items: allFoods) }
                }
                Button { showAllQuickLog.toggle() } label: {
                    Text(showAllQuickLog ? "Show less" : "Show whole library")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.tertiaryInk)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        microsSummary
    }

    @ViewBuilder private var microsSummary: some View {
        if !store.draft.logged.isEmpty || store.draft.ai != nil {
            let n = store.dayNutrients()
            VStack(alignment: .leading, spacing: 8) {
                Text("CARBS · FAT · FIBER · MICROS (TODAY)").font(.system(size: 11, weight: .semibold)).tracking(0.3)
                    .foregroundStyle(Theme.tertiaryInk)
                HStack(spacing: 8) {
                    nutPill("Carbs", n.carbs, "g")
                    nutPill("Fat", n.fat, "g")
                    nutPill("Fiber", n.fiber, "g")
                }
                if !n.micros.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(n.micros) { m in
                            Text("\(m.name) \(fmtMicro(m.amount))\(m.unit)")
                                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color(hex: 0x5B43E0))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Capsule().fill(Color(hex: 0x6FA8FF).opacity(0.16)))
                        }
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassList().padding(.top, 10)
        }
    }

    private func nutPill(_ label: String, _ value: Double, _ unit: String) -> some View {
        VStack(spacing: 1) {
            Text("\(fmtMicro(value))\(unit)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.tertiaryInk)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
    }

    private func fmtMicro(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d) }

    private func chipGroup(title: String, items: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.3)
                .foregroundStyle(Theme.tertiaryInk).padding(.horizontal, 4)
            FlowLayout(spacing: 8) {
                ForEach(items) { item in
                    chip(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func chip(_ item: CatalogItem) -> some View {
        let qty = store.loggedQty(item.id)
        if qty > 0 {
            HStack(spacing: 8) {
                Button { store.removeServing(item) } label: {
                    Image(systemName: qty == 1 ? "trash" : "minus").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }.buttonStyle(.plain)
                Text(qty > 1 ? "\(item.name) ×\(qty)" : item.name)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Button { store.addServing(item) } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Capsule().fill(Theme.sage))
        } else {
            Button { store.addServing(item) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentDark)
                    Text(item.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(
                    Capsule().fill(Color.white.opacity(0.55))
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Apple Health card

    private var healthCard: some View {
        let on = store.settings.healthkit
        return HStack(spacing: 10) {
            statWidget(icon: "figure.walk", tint: Theme.sage,
                       title: store.isToday ? "Steps today" : "Steps",
                       value: on ? stepsString : "—")
            statWidget(icon: "scalemass.fill", tint: Theme.accentDark,
                       title: "Weight", value: weightString)
        }
        .padding(.top, 14)
    }

    private func statWidget(icon: String, tint: Color, title: String, value: String) -> some View {
        GlassCard(padding: 14, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                Text(value).font(Theme.display(24)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(title).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryInk)
            }
        }
    }

    private var stepsString: String {
        let n = Int(health.dateSteps)
        return NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }

    /// Prefer the weight logged for the day; otherwise the latest Health sample up to that day.
    private var weightString: String {
        if let w = Double(store.draft.weight), w > 0 { return String(format: "%.1f kg", w) }
        if store.settings.healthkit, health.dateWeight > 0 { return String(format: "%.1f kg", health.dateWeight) }
        return "—"
    }

    private func miniStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryInk)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
        )
    }

    // MARK: - Tip

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("◦").foregroundStyle(Theme.accentDark).font(.system(size: 14))
            Text(store.tipText)
                .font(.system(size: 13.5)).foregroundStyle(Theme.tipText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.tipBG)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.tipBorder, lineWidth: 0.5))
        )
        .padding(.top, 12)
    }

    // MARK: - Meals

    private var mealsCard: some View {
        VStack(spacing: 0) {
            ForEach(Content.mealDefs, id: \.key) { def in
                let highlight = store.isToday && store.mealNudge?.key == def.key
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(def.label).font(.system(size: 12, weight: highlight ? .semibold : .regular))
                            .foregroundStyle(highlight ? Theme.accentDark : Theme.secondaryInk)
                        if highlight {
                            Text("now").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Theme.accentDark))
                        }
                        Spacer()
                        mealTimeChip(def.key)
                    }
                    TextField(def.placeholder, text: mealBinding(def.key), axis: .vertical)
                        .font(.system(size: 16)).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(highlight ? Theme.accent.opacity(0.10) : .clear)
                Hairline()
            }
            Button {
                Task { await store.estimate() }
            } label: {
                Text(estimateLabel)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0x6470A6), Color(hex: 0x3B4A7C)],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .opacity(store.aiStatus == .loading ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .disabled(store.aiStatus == .loading)
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .glassList()
    }

    private func aiMealCalorieBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let meals = store.draft.ai?.meals, meals.indices.contains(index),
                      let v = meals[index].calories, v > 0 else { return "" }
                return String(Int(v.rounded()))
            },
            set: { store.updateAIMealCalories(at: index, calories: Double($0) ?? 0) })
    }

    private var estimateLabel: String {
        switch store.aiStatus {
        case .loading: return "Estimating your day…"
        default: return store.draft.ai != nil ? "Re-estimate my day" : "Estimate my day"
        }
    }

    // MARK: - AI result / error

    @ViewBuilder private var aiResult: some View {
        if let ai = store.draft.ai {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.aiModelLine)
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color(hex: 0x3B4A7C))
                    Spacer()
                    Text("±10–15%").font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk)
                }
                .padding(.bottom, 11)
                ForEach(Array(ai.meals.enumerated()), id: \.element.id) { idx, r in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.label).font(.system(size: 14)).foregroundStyle(Theme.ink)
                            if let note = r.note, !note.isEmpty {
                                Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            HStack(spacing: 2) {
                                TextField("0", text: aiMealCalorieBinding(idx))
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                                    .frame(width: 50)
                                Text("kcal").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                            }
                            Text("P\(Int((r.protein ?? 0).rounded())) · C\(Int((r.carbs ?? 0).rounded())) · F\(Int((r.fat ?? 0).rounded()))")
                                .font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk)
                        }
                    }
                    .padding(.vertical, 7)
                    Hairline()
                }
                Text("Tap a calorie value to correct it — the whole-day total recalculates.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
                HStack {
                    Text("Whole day").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(Int((ai.total.calories ?? 0).rounded())) kcal · \(Int((ai.total.protein ?? 0).rounded()))g protein")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x3B4A7C))
                }
                .padding(.top, 10)
                Text("Auto-filled your totals. Estimates are approximate.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.18), Theme.accent.opacity(0.06)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 0.5))
            )
            .padding(.top, 12)
        } else if store.aiStatus == .error {
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn\u{2019}t reach the estimator just now — no problem. Add calories & protein by hand below.")
                if !store.aiErrorMessage.isEmpty {
                    Text(store.aiErrorMessage)
                        .font(.system(size: 12)).foregroundStyle(Color(hex: 0xD86B4A))
                }
            }
                .font(.system(size: 13.5)).foregroundStyle(Color(white: 0.29))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(white: 0.27).opacity(0.12), lineWidth: 0.5))
                )
                .padding(.top, 12)
        }
    }

    // MARK: - Totals

    private var totals: some View {
        HStack(spacing: 10) {
            totalField(title: "Calories", target: "/ \(Int(store.targets.calories))", binding: caloriesBinding)
            totalField(title: "Protein g", target: "/ \(Int(store.targets.protein))", binding: proteinBinding)
        }
        .padding(.top, 14)
    }

    private func totalField(title: String, target: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                Text(target).font(.system(size: 12)).foregroundStyle(Color(white: 0.27).opacity(0.35))
            }
            TextField("—", text: binding)
                .keyboardType(.numberPad)
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
        )
    }

    // MARK: - Habits (configurable, grouped by pillar)

    @ViewBuilder private var habitsSection: some View {
        HStack {
            SectionHeader(text: "Your non-negotiables", color: store.moduleColor("habits"))
            Spacer()
            Button { showHabits = true } label: {
                Text("Edit").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentDark)
            }.padding(.trailing, 8).padding(.top, 22)
        }
        ForEach(store.usedPillars) { pillar in
            let items = store.habits(in: pillar)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: pillar.icon).font(.system(size: 11)).foregroundStyle(Color(hex: pillar.hex))
                    Text(store.pillarTitle(pillar).uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.3)
                        .foregroundStyle(Theme.tertiaryInk)
                }
                .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, def in
                        habitRow(def)
                        if idx < items.count - 1 { Hairline() }
                    }
                }
                .glassList()
            }
            .padding(.bottom, 10)
        }
    }

    private func habitRow(_ def: HabitDef) -> some View {
        let on = store.isSatisfied(def, store.draft)
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(def.title).font(.system(size: 16)).foregroundStyle(Theme.ink)
                if def.link.isAuto {
                    Text("Auto · \(def.link.label)").font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                }
            }
            Spacer()
            if def.link == .manual {
                ToggleRow(on: on) { store.toggleHabit(def) }
            } else {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(on ? Theme.sage : Color(white: 0.47).opacity(0.3))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    // MARK: - Score

    private var scoreCard: some View {
        let s = store.draftScore
        let total = store.habitTotal
        let msg = store.scoreMessage(s)
        let won = store.dayWon(store.draft)
        return HStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(s)").font(Theme.serif(40)).foregroundStyle(msg.color)
                Text("/\(total)").font(.system(size: 19)).foregroundStyle(Color(white: 0.27).opacity(0.4))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(msg.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(msg.sub).font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(won ? Theme.sage.opacity(0.1) : Color.white.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(won ? Theme.sage.opacity(0.3) : .white.opacity(0.7), lineWidth: 0.5))
        )
        .padding(.top, 14)
    }

    // MARK: - Study & work

    private var showStudySection: Bool {
        store.usedPillars.contains(.work) || !store.data.countdowns.isEmpty
            || !store.data.subjects.isEmpty || store.draft.studyHours > 0
    }

    @ViewBuilder private var studySection: some View {
        if showStudySection {
            let vocab = store.workVocab
            HStack {
                SectionHeader(text: vocab.pillar, color: store.moduleColor("workStudy"))
                Spacer()
                Button { showFocus = true } label: {
                    Label("Focus", systemImage: "scope").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }.padding(.trailing, 8).padding(.top, 22)
                Button { showStudy = true } label: {
                    Text("Manage").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }.padding(.trailing, 8).padding(.top, 22)
            }

            ForEach(store.data.countdowns) { cd in
                let days = store.days(until: cd.date)
                HStack(spacing: 12) {
                    IconTile(symbol: cd.kind == "work" ? "flag.checkered" : "graduationcap.fill",
                             colors: [Color(hex: 0x6FA8FF), Color(hex: 0x5B43E0)], size: 40, corner: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cd.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(examLine(days)).font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer()
                    Text("\(max(0, days))").font(Theme.serif(34)).foregroundStyle(Color(hex: 0x5B43E0))
                }
                .padding(16).glassList().padding(.bottom, 8)
            }

            studyTimerCard

            // hours today
            HStack(spacing: 12) {
                Image(systemName: "clock.fill").foregroundStyle(Color(hex: 0x5B43E0))
                Text(String(format: "%.1f / %.0f h · \(vocab.hours.lowercased())", store.draft.studyHours, store.targets.studyHours))
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Button("+30m") { store.addStudyHours(0.5) }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x5B43E0))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color(hex: 0x6FA8FF).opacity(0.18)))
            }
            .padding(16).glassList().padding(.top, 10)

            if !store.data.subjects.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(store.data.subjects.enumerated()), id: \.element.id) { idx, s in
                        Button { store.toggleSubject(s.id) } label: {
                            HStack {
                                Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(s.done ? Theme.sage : Color(white: 0.47).opacity(0.3))
                                Text(s.name).font(.system(size: 15))
                                    .foregroundStyle(s.done ? Theme.tertiaryInk : Theme.ink)
                                    .strikethrough(s.done)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }.buttonStyle(.plain)
                        if idx < store.data.subjects.count - 1 { Hairline() }
                    }
                }
                .glassList().padding(.top, 10)
            }
        }
    }

    private func examLine(_ days: Int) -> String {
        if days < 0 { return "Exam day has passed" }
        if days == 0 { return "Today — you've got this 💪" }
        return "\(days) day\(days == 1 ? "" : "s") to go"
    }

    @ViewBuilder private var studyTimerCard: some View {
        if studyTimer.running {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(studyTimer.subject.isEmpty ? "Studying" : studyTimer.subject)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(studyTimer.paused ? "Paused" : "In progress")
                            .font(.system(size: 12)).foregroundStyle(studyTimer.paused ? Theme.tertiaryInk : Theme.sage)
                    }
                    Spacer()
                    Text(timeFmt(studyTimer.elapsed)).font(Theme.serif(30)).monospacedDigit().foregroundStyle(Theme.ink)
                }
                HStack(spacing: 10) {
                    Button(studyTimer.paused ? "Resume" : "Pause") {
                        studyTimer.paused ? studyTimer.resume() : studyTimer.pause()
                    }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x5B43E0))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x6FA8FF).opacity(0.18)))
                    Button("Stop & log") {
                        let mins = studyTimer.stop()
                        store.logStudySession(subject: studyTimer.subject, minutes: mins)
                    }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x5B43E0)))
                }
            }
            .padding(16).glassList().padding(.top, 10)
        } else {
            Button { showStudy = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "play.circle.fill").foregroundStyle(Color(hex: 0x5B43E0))
                    Text("Start a \(store.workVocab.session.lowercased())").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity).glassList()
            }.buttonStyle(.plain).padding(.top, 10)
        }
    }

    private func timeFmt(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%02d:%02d:%02d", s/3600, (s%3600)/60, s%60)
    }

    // MARK: - Training & body

    private var trainingCard: some View {
        VStack(spacing: 0) {
            labeledField(label: "Session", hint: "— note any neck / shoulder discomfort",
                         placeholder: "e.g. Lower body + core. Neck fine.", binding: trainingBinding)
            Hairline()
            labeledField(label: "Longest jog (min) or intervals", hint: nil,
                         placeholder: "e.g. 2 min × 5", binding: runBinding)
            Hairline()
            HStack {
                Text("Weight (kg)").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                TextField("—", text: weightBinding)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .font(.system(size: 16)).foregroundStyle(Theme.ink).frame(width: 90)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            Hairline()
            HStack {
                Text("Sleep / mood / stress").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                TextField("one line", text: smsBinding)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15)).foregroundStyle(Theme.ink).frame(width: 160)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .glassList()
        .padding(.top, 10)
    }

    private func labeledField(label: String, hint: String?, placeholder: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                if let hint {
                    Text(hint).font(.system(size: 12)).foregroundStyle(Color(white: 0.27).opacity(0.35))
                }
            }
            TextField(placeholder, text: binding, axis: .vertical)
                .font(.system(size: 16)).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bindings into the autosaving draft

    @ViewBuilder private func mealTimeChip(_ key: String) -> some View {
        let hasContent = !mealBinding(key).wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        if hasContent {
            let epoch = store.draft.mealTimes[key]
            Button { editingTimeKey = MealKey(id: key) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "clock").font(.system(size: 10))
                    Text(epoch.map { mealTimeStr($0) } ?? "set time").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.accentDark)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    private func mealTimeStr(_ epoch: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: Date(timeIntervalSince1970: epoch))
    }

    @ViewBuilder private func mealTimeSheet(_ key: String) -> some View {
        let label = Content.mealDefs.first { $0.key == key }?.label ?? "Meal"
        let initial = store.draft.mealTimes[key].map { Date(timeIntervalSince1970: $0) } ?? Date()
        MealTimeSheet(label: label, initial: initial,
                      onSet: { store.setMealTime(key, $0); editingTimeKey = nil },
                      onClear: { store.setMealTime(key, nil); editingTimeKey = nil })
    }

    private func mealBinding(_ key: String) -> Binding<String> {
        Binding(
            get: {
                switch key {
                case "breakfast": return store.draft.meals.breakfast
                case "snacks": return store.draft.meals.snacks
                case "lunch": return store.draft.meals.lunch
                case "dinner": return store.draft.meals.dinner
                case "drinks": return store.draft.meals.drinks
                default: return ""
                }
            },
            set: { v in store.mutate { e in
                let wasEmpty: Bool
                switch key {
                case "breakfast": wasEmpty = e.meals.breakfast.isEmpty; e.meals.breakfast = v
                case "snacks": wasEmpty = e.meals.snacks.isEmpty; e.meals.snacks = v
                case "lunch": wasEmpty = e.meals.lunch.isEmpty; e.meals.lunch = v
                case "dinner": wasEmpty = e.meals.dinner.isEmpty; e.meals.dinner = v
                case "drinks": wasEmpty = e.meals.drinks.isEmpty; e.meals.drinks = v
                default: wasEmpty = false
                }
                // Auto-stamp the eaten time the first time a meal gets content today.
                if wasEmpty && !v.isEmpty && store.isToday && e.mealTimes[key] == nil {
                    e.mealTimes[key] = Date().timeIntervalSince1970
                }
            }}
        )
    }

    private var caloriesBinding: Binding<String> { field(\.calories) }
    private var proteinBinding: Binding<String> { field(\.proteinG) }
    private var trainingBinding: Binding<String> { field(\.training) }
    private var runBinding: Binding<String> { field(\.run) }
    private var weightBinding: Binding<String> { field(\.weight) }
    private var smsBinding: Binding<String> { field(\.sms) }

    private func field(_ kp: WritableKeyPath<Entry, String>) -> Binding<String> {
        Binding(
            get: { store.draft[keyPath: kp] },
            set: { v in store.mutate { $0[keyPath: kp] = v } }
        )
    }
}
