import SwiftUI
import Charts

/// **Biology** — the same imported data, pivoted from *reports* to *measurements*: every analyte the
/// user has ever had, grouped by category, each with its own history, reference band and (once
/// there is enough data) honest on-device correlations.
///
/// Guardrail, everywhere on this screen: reference ranges are *general adult reference data*. The
/// dot says "outside general range", never "abnormal"; there is no interpretation, no diagnosis and
/// no recommendation anywhere in this file.
struct BiologyView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    // Built once when the sheet opens: `allSeries` walks every report and `topCorrelations` is
    // O(analytes²), and the search field re-evaluates `body` on every keystroke.
    @State private var series: [BiologyCatalog.SeriesItem] = []
    @State private var top: [BiologyCatalog.Correlation] = []

    private var filtered: [BiologyCatalog.SeriesItem] {
        let q = BiologyCatalog.normalize(query)
        guard !q.isEmpty else { return series }
        return series.filter { item in
            if BiologyCatalog.normalize(item.displayName).contains(q) { return true }
            return item.def?.aliases.contains { BiologyCatalog.normalize($0).contains(q) } ?? false
        }
    }

    private var grouped: [(category: String, items: [BiologyCatalog.SeriesItem])] {
        let byCat = Dictionary(grouping: filtered) { $0.category }
        return BiologyCatalog.categoryOrder.compactMap { cat in
            guard let items = byCat[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        if series.isEmpty { empty } else { content }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Biology")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } }
            }
            .task {
                series = store.biologySeries
                top = BiologyCatalog.topCorrelations(series: series, metrics: store.biologyMetrics)
            }
        }
        .tint(Theme.accentDark)
    }

    private var content: some View {
        VStack(spacing: 0) {
            searchField
            ForEach(grouped, id: \.category) { group in
                SectionHeader(text: BiologyCatalog.categoryLabel(group.category))
                VStack(spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                        NavigationLink { BiologyDetailView(item: item) } label: { row(item) }
                            .buttonStyle(.plain)
                        if idx < group.items.count - 1 { Hairline() }
                    }
                }
                .glassList()
            }
            if grouped.isEmpty {
                Text("Nothing matches \u{201c}\(query)\u{201d}.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).glassList().padding(.top, 12)
            }
            correlationSummary
            disclaimer
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.tertiaryInk)
            TextField("Search measurements", text: $query)
                .font(.system(size: 15)).foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                        .foregroundStyle(Theme.tertiaryInk)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.6), lineWidth: 0.5)))
        .padding(.top, 12)
    }

    private func row(_ item: BiologyCatalog.SeriesItem) -> some View {
        let latest = item.latest
        let status = BiologyCatalog.status(value: latest?.value ?? 0, def: item.def, sexMale: store.targets.sexMale)
        return HStack(spacing: 10) {
            Circle().fill(BiologyStyle.color(status)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(latest?.date ?? "—") \u{00b7} \(item.points.count) reading\(item.points.count == 1 ? "" : "s")")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
            }
            Spacer(minLength: 8)
            Text(BiologyStyle.value(latest?.value, unit: item.unit))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
            trendArrow(item)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(white: 0.27).opacity(0.3))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func trendArrow(_ item: BiologyCatalog.SeriesItem) -> some View {
        let t = BiologyCatalog.trend(item.points)
        if t != .none {
            Image(systemName: BiologyStyle.symbol(t))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BiologyStyle.trendColor(t, item.direction))
        }
    }

    private var correlationSummary: some View {
        Group {
            if !top.isEmpty {
                SectionHeader(text: "Patterns across your data")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(top) { c in
                        Text(c.sentence).font(.system(size: 13.5)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(BiologyStyle.causationNote)
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk).padding(.top, 2)
                }
                .padding(16).glassList()
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No measurements yet").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Import a lab report or an InBody sheet from the Health tab. Every result is kept — the ones Biology recognises get a reference range and a trend, the rest are listed under their own name.")
                .font(.system(size: 13.5)).foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).glassList().padding(.top, 16)
    }

    private var disclaimer: some View {
        Text(BiologyStyle.rangeNote)
            .font(.system(size: 12)).foregroundStyle(Color(white: 0.27).opacity(0.45))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.top, 18)
    }
}

// MARK: - Detail

struct BiologyDetailView: View {
    let item: BiologyCatalog.SeriesItem
    @EnvironmentObject var store: AppStore
    @State private var openRecord: LabRecord?
    @State private var found: [BiologyCatalog.Correlation] = []

    private var range: ClosedRange<Double>? { item.def?.referenceRange(sexMale: store.targets.sexMale) }

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(spacing: 0) {
                    header
                    chartCard
                    SectionHeader(text: "Every reading")
                    readings
                    correlations
                    Text(BiologyStyle.rangeNote)
                        .font(.system(size: 12)).foregroundStyle(Color(white: 0.27).opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.top, 18)
                }
                .padding(.horizontal, 16).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openRecord) { r in LabRecordSheet(record: r) }
        .task { found = BiologyCatalog.correlations(for: item, among: store.biologySeries,
                                                    metrics: store.biologyMetrics) }
    }

    private var header: some View {
        GlassCard(padding: 16, cornerRadius: 24, tint: .white.opacity(0.46)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(BiologyStyle.value(item.latest?.value, unit: nil))
                        .font(Theme.display(34)).foregroundStyle(Theme.ink)
                    Text(item.unit).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    let t = BiologyCatalog.trend(item.points)
                    if t != .none {
                        Image(systemName: BiologyStyle.symbol(t)).font(.system(size: 15, weight: .bold))
                            .foregroundStyle(BiologyStyle.trendColor(t, item.direction))
                    }
                }
                HStack(spacing: 6) {
                    let status = BiologyCatalog.status(value: item.latest?.value ?? 0, def: item.def,
                                                       sexMale: store.targets.sexMale)
                    Circle().fill(BiologyStyle.color(status)).frame(width: 8, height: 8)
                    Text(BiologyStyle.statusText(status)).font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                    if let d = item.latest?.date {
                        Text("\u{00b7} \(d)").font(.system(size: 13)).foregroundStyle(Theme.tertiaryInk)
                    }
                }
                if let r = range {
                    Text("General reference range \(BiologyStyle.trim(r.lowerBound))\u{2013}\(BiologyStyle.trim(r.upperBound)) \(item.unit)")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
                if item.def == nil {
                    Text("Kept under the name your report used. No reference range \u{2014} this one isn\u{2019}t in the catalog.")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 14)
    }

    private var chartCard: some View {
        let pts = item.chartPoints
        return GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                if pts.count >= 2 {
                    BiologySeriesChart(points: pts, band: range, color: Theme.accentDark)
                    HStack {
                        Text(pts.first?.date ?? "").font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                        Spacer()
                        Text(pts.last?.date ?? "").font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                    }
                } else if let only = pts.first {
                    HStack(spacing: 10) {
                        Circle().fill(Theme.accentDark).frame(width: 10, height: 10)
                        Text("\(BiologyStyle.trim(only.value)) \(item.unit) \u{00b7} \(only.date)")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                    }
                    Text("One reading \u{2014} trends appear after your next report.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk)
                } else {
                    Text("No reading here can be charted yet \u{2014} every value so far came in a unit Biology doesn\u{2019}t recognise, and mixing scales would draw a false trend.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if item.hasUnknownUnits {
                    Text("Readings marked \u{201c}unit not recognised\u{201d} below are left off the line on purpose.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                }
            }
        }
        .padding(.top, 12)
    }

    private var readings: some View {
        VStack(spacing: 0) {
            ForEach(Array(item.points.reversed().enumerated()), id: \.element.id) { idx, p in
                Button {
                    openRecord = store.data.labs.first { $0.id == p.sourceID }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.date).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ink)
                            Text(p.sourceTitle).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(BiologyStyle.trim(p.value)) \(p.unitRecognized ? item.unit : p.reportedUnit)")
                                .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.ink)
                            if !p.unitRecognized {
                                Text("unit not recognised").font(.system(size: 11))
                                    .foregroundStyle(Color(hex: 0xD86B4A))
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < item.points.count - 1 { Hairline() }
            }
        }
        .glassList()
    }

    private var correlations: some View {
        Group {
            if !found.isEmpty {
                SectionHeader(text: "Patterns")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(found) { c in
                        Text(c.sentence).font(.system(size: 13.5)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(BiologyStyle.causationNote)
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk).padding(.top, 2)
                }
                .padding(16).glassList()
            }
        }
    }
}

// MARK: - The report a reading came from

struct LabRecordSheet: View {
    let record: LabRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Imported \(record.date)\(record.collectedDate.isEmpty ? "" : " \u{00b7} collected \(record.collectedDate)")")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                        ForEach(record.items) { item in
                            HStack {
                                Text(item.name).font(.system(size: 14)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(BiologyStyle.trim(item.value)) \(item.unit)")
                                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).glassList()
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(record.title.isEmpty ? "Lab report" : record.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }
        .tint(Theme.accentDark)
    }
}

// MARK: - Chart

/// The analyte's history, spaced by real elapsed days (not by index), with the general reference
/// range drawn as a shaded band behind it.
struct BiologySeriesChart: View {
    let points: [BiologyCatalog.Point]
    var band: ClosedRange<Double>?
    var color: Color = Theme.accentDark

    private struct Plotted: Identifiable {
        let id: String
        let day: Int
        let value: Double
    }

    private var plotted: [Plotted] {
        points.compactMap { p in
            BiologyCatalog.dayNumber(p.date).map { Plotted(id: p.id, day: $0, value: p.value) }
        }
    }

    var body: some View {
        Chart {
            if let band {
                RectangleMark(yStart: .value("low", band.lowerBound), yEnd: .value("high", band.upperBound))
                    .foregroundStyle(Theme.sage.opacity(0.13))
            }
            ForEach(plotted) { p in
                AreaMark(x: .value("day", p.day), y: .value("v", p.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("day", p.day), y: .value("v", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("day", p.day), y: .value("v", p.value))
                    .foregroundStyle(color)
                    .symbolSize(34)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartYScale(domain: yDomain)
        .frame(height: 150)
    }

    private var yDomain: ClosedRange<Double> {
        let values = plotted.map(\.value)
        var lo = values.min() ?? 0
        var hi = values.max() ?? 1
        if let band { lo = min(lo, band.lowerBound); hi = max(hi, band.upperBound) }
        if lo == hi { lo -= 1; hi += 1 }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }
}

// MARK: - Shared styling & wording

/// Every user-facing string about ranges lives here so the wording stays a *reference* statement,
/// never a clinical one.
enum BiologyStyle {
    static let rangeNote = "General adult reference ranges \u{2014} your lab\u{2019}s own range may differ. Win the Day shows where a value sits, and nothing more. It doesn\u{2019}t interpret results or give medical advice: talk to your doctor."
    static let causationNote = "Correlation, not causation \u{2014} discuss with your doctor."

    static func color(_ s: BiologyCatalog.RangeStatus) -> Color {
        switch s {
        case .inRange: return Theme.sage
        case .below, .above: return Color(hex: 0xD86B4A)
        case .unknown: return Theme.tertiaryInk.opacity(0.5)
        }
    }

    static func statusText(_ s: BiologyCatalog.RangeStatus) -> String {
        switch s {
        case .inRange: return "Within general range"
        case .below:   return "Below general range"
        case .above:   return "Above general range"
        case .unknown: return "No general range for this one"
        }
    }

    static func symbol(_ t: BiologyCatalog.Trend) -> String {
        switch t {
        case .up:   return "arrow.up.right"
        case .down: return "arrow.down.right"
        default:    return "arrow.right"
        }
    }

    /// Neutral unless the analyte declares which way is better — an unknown analyte never gets a
    /// green or red arrow.
    static func trendColor(_ t: BiologyCatalog.Trend, _ d: BiologyCatalog.Direction) -> Color {
        switch BiologyCatalog.trendIsGood(t, d) {
        case .some(true):  return Theme.sage
        case .some(false): return Color(hex: 0xD86B4A)
        case .none:        return Theme.tertiaryInk
        }
    }

    static func trim(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 100_000 { return String(Int(d)) }
        return String(format: abs(d) < 10 ? "%.2f" : "%.1f", d)
    }

    static func value(_ d: Double?, unit: String?) -> String {
        guard let d else { return "\u{2014}" }
        let u = (unit?.isEmpty == false) ? " " + unit! : ""
        return trim(d) + u
    }
}
