import SwiftUI
import Charts

struct LinePoint: Identifiable {
    let id = UUID()
    let x: Int
    let y: Double
}

/// Filled line chart with an optional dashed target line — mirrors the design's lineChart.
struct LineChartView: View {
    let values: [Double]
    var color: Color = Theme.accent
    var target: Double? = nil

    private var points: [LinePoint] {
        values.enumerated().map { LinePoint(x: $0.offset, y: $0.element) }
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("i", p.x), y: .value("v", p.y))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), color.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("i", p.x), y: .value("v", p.y))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("i", last.x), y: .value("v", last.y))
                    .foregroundStyle(color)
                    .symbolSize(70)
            }
            if let target {
                RuleMark(y: .value("target", target))
                    .foregroundStyle(Color(white: 0.27).opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .frame(height: 110)
        .clipped()
    }

    private var yDomain: ClosedRange<Double> {
        var lo = values.min() ?? 0
        var hi = values.max() ?? 1
        if let target { lo = min(lo, target); hi = max(hi, target) }
        if lo == hi { lo -= 1; hi += 1 }
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }
}

struct BarPoint: Identifiable {
    let id = UUID()
    let x: Int
    let y: Double
    var color: Color
}

/// Bar chart with optional target — mirrors the design's barChart.
struct BarChartView: View {
    let points: [BarPoint]
    var target: Double? = nil
    var maxValue: Double = 0

    var body: some View {
        Chart {
            ForEach(points) { p in
                BarMark(x: .value("i", p.x), y: .value("v", p.y), width: .ratio(0.7))
                    .foregroundStyle(p.color)
                    .cornerRadius(3)
            }
            if let target {
                RuleMark(y: .value("target", target))
                    .foregroundStyle(Color(white: 0.27).opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...domainMax)
        .frame(height: 100)
        .clipped()
    }

    private var domainMax: Double {
        max(maxValue, target ?? 0, points.map(\.y).max() ?? 1, 1)
    }
}

/// A titled glass card wrapping a chart.
struct ChartCard<Content: View>: View {
    let title: String
    let sub: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(sub).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
                content()
            }
        }
        .padding(.top, 12)
    }
}
