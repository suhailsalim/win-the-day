import SwiftUI

struct TrendsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var health: HealthManager

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle(sub: "The real scoreboard", title: "Trends")

            if store.hasTrendData {
                weeklyReviewCard
                insightsCard
                prize
                statGrid
                readinessCard
                microsCard
                trainingCard
                rangePicker
                charts
                Text("The trend is the signal — daily scale noise isn\u{2019}t. Waist, photos and your jog are better proof than any single morning.")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.top, 14)
            } else {
                emptyState
            }
        }
        .task { await health.loadStepsHistory() }
    }

    @State private var range = 0   // 0 = 7d, 1 = 30d, 2 = all
    private var rangeDays: Int { range == 0 ? 7 : (range == 1 ? 30 : 9999) }
    private func win<T>(_ arr: [T]) -> [T] { Array(arr.suffix(rangeDays)) }

    private var rangePicker: some View {
        Picker("", selection: $range) {
            Text("7 days").tag(0); Text("30 days").tag(1); Text("All").tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.top, 14)
    }

    @ViewBuilder private var insightsCard: some View {
        let items = store.insights()
        if !items.isEmpty {
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What\u{2019}s working").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    ForEach(items) { i in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: i.icon).font(.system(size: 14)).foregroundStyle(Theme.accentDark)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(i.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                                Text(i.detail).font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.top, 14)
        }
    }

    private var weeklyReviewCard: some View {
        GlassCard(padding: 16, cornerRadius: 22, tint: .white.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles").font(.system(size: 13)).foregroundStyle(Theme.accentDark)
                        Text("This week").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Button { Task { await store.refreshWeeklyReview(force: true) } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.tertiaryInk)
                    }.buttonStyle(.plain)
                }
                if store.weeklyReviewLoading && store.weeklyReview.isEmpty {
                    Text("Reviewing your week…").font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                } else if store.weeklyReview.isEmpty {
                    Text("Tap ↻ to generate this week\u{2019}s AI review.")
                        .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                } else {
                    Text(store.weeklyReview).font(.system(size: 14.5)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                }
            }
        }
        .padding(.top, 14)
        .task { await store.refreshWeeklyReview() }
    }

    private var prize: some View {
        let t = store.targets
        let unit = t.prizeUnit.isEmpty ? "" : " \(t.prizeUnit)"
        let targetPrefix = t.prizeLowerIsBetter ? "≤" : "≥"
        return GlassCard(padding: 18, cornerRadius: 24, tint: .white.opacity(0.42)) {
            VStack(alignment: .leading, spacing: 8) {
                Text("THE PRIZE · \(t.prizeName.uppercased())")
                    .font(.system(size: 11.5, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(Theme.accentDark)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(fmt(t.prizeCurrent))\(unit)")
                        .font(Theme.serif(50)).foregroundStyle(Theme.ink)
                    Text("→").font(.system(size: 20)).foregroundStyle(Color(white: 0.27).opacity(0.4))
                    Text("\(targetPrefix)\(fmt(t.prizeTarget))\(unit)")
                        .font(Theme.serif(50)).foregroundStyle(Color(hex: 0x3DA876))
                }
                Text("Your one priority metric. Update it in Settings → The prize\(t.prizeName.lowercased().contains("visceral") ? ", or import an InBody report on the Health tab." : ".")")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 14)
    }

    private var statGrid: some View {
        let cards = store.statCards()
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(cards) { c in
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.label).font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(c.value).font(Theme.serif(26)).foregroundStyle(Theme.ink)
                        Text(c.delta).font(.system(size: 12.5)).foregroundStyle(c.deltaColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15).padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.5)))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
                )
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder private var charts: some View {
        ChartCard(title: "Weight trend", sub: String(format: "%.1f kg", store.latestWeight)) {
            LineChartView(values: win(store.weightSeries()), color: Theme.accent)
        }

        let bodyFat = store.bodyFatSeries()
        if bodyFat.count >= 2 {
            ChartCard(title: "Body fat", sub: String(format: "%.1f%%", bodyFat.last ?? 0)) {
                LineChartView(values: win(bodyFat), color: Color(hex: 0xD86B4A))
            }
        }

        let lean = store.leanMassSeries()
        if lean.count >= 2 {
            ChartCard(title: "Lean mass", sub: String(format: "%.1f kg", lean.last ?? 0)) {
                LineChartView(values: win(lean), color: Theme.sage)
            }
        }

        let scores = win(store.scoreSeries())
        if !scores.isEmpty {
            ChartCard(title: "Daily score", sub: "streak \(store.streak())d") {
                BarChartView(points: scores.enumerated().map {
                    BarPoint(x: $0.offset, y: Double($0.element),
                             color: $0.element >= 3 ? Theme.sage : Color(hex: 0xD9CFC2))
                }, maxValue: 5)
            }
        }

        let protein = win(store.proteinSeries())
        if !protein.isEmpty {
            ChartCard(title: "Protein", sub: "target \(Int(store.targets.protein))g") {
                LineChartView(values: protein, color: Theme.sage, target: store.targets.protein)
            }
        }

        let cals = win(store.calorieSeries())
        if !cals.isEmpty {
            ChartCard(title: "Calories", sub: "target \(Int(store.targets.calories))") {
                LineChartView(values: cals, color: Theme.accent, target: store.targets.calories)
            }
        }

        let steps = win(health.stepsHistory.isEmpty ? store.stepsSeries() : health.stepsHistory)
        if !steps.isEmpty {
            ChartCard(title: "Steps", sub: health.stepsHistory.isEmpty ? "target \(Int(store.targets.steps))" : "from Apple Health") {
                BarChartView(points: steps.enumerated().map { BarPoint(x: $0.offset, y: $0.element, color: Theme.sage) },
                             target: store.targets.steps)
            }
        }

        let jog = win(store.jogSeries())
        if !jog.isEmpty {
            ChartCard(title: "Longest jog", sub: "building to 20–30 min") {
                LineChartView(values: jog, color: Theme.accent)
            }
        }
    }

    @ViewBuilder private var readinessCard: some View {
        let series = store.readinessSeries()
        if series.count >= 2 {
            ChartCard(title: "Readiness", sub: "last \(series.count) days") {
                LineChartView(values: series, color: Color(hex: 0x6E7BFF), target: 70)
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder private var trainingCard: some View {
        let sessions = store.workoutSessionsThisWeek()
        if sessions > 0 {
            let vol = store.workoutVolumeSeries(days: 7)
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Training · this week").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(sessions) session\(sessions == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    }
                    if store.workoutVolumeThisWeek() > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(Int(store.workoutVolumeThisWeek()))").font(Theme.serif(28)).foregroundStyle(Theme.ink)
                            Text("kg total volume").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
                        }
                        BarChartView(points: vol.enumerated().map { BarPoint(x: $0.offset, y: $0.element, color: Theme.sage) })
                            .frame(height: 90)
                    }
                }
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder private var microsCard: some View {
        let items = store.microProgress()
        if !items.isEmpty {
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Micronutrients · today").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("vs daily value").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    }
                    ForEach(items) { m in
                        let pct = Int((m.amount / m.rda * 100).rounded())
                        let full = m.ratio >= 0.999
                        let barColor: Color = m.limit ? (m.amount > m.rda ? Color(hex: 0xD86B4A) : Theme.sage)
                                                       : (full ? Theme.sage : Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(m.name).font(.system(size: 13)).foregroundStyle(Theme.ink)
                                if m.limit { Text("limit").font(.system(size: 10)).foregroundStyle(Theme.tertiaryInk) }
                                Spacer()
                                Text("\(fmt(m.amount))/\(fmt(m.rda)) \(m.unit) · \(pct)%")
                                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(white: 0.5).opacity(0.15)).frame(height: 6)
                                    Capsule().fill(barColor)
                                        .frame(width: geo.size.width * min(1, m.amount / m.rda), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    Text("Estimates from your logged items & AI meal estimate. Reference values are general adult guidance.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk).padding(.top, 2)
                }
            }
            .padding(.top, 12)
        }
    }

    private func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Your charts grow here").font(Theme.serif(24)).foregroundStyle(Theme.ink)
            Text("Log a day or two on Today and your weight trend, score and streak take shape.")
                .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24).padding(.vertical, 70)
    }
}
