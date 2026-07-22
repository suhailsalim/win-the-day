import SwiftUI

/// iOS-style switch matching the design (sage when on).
struct IOSToggle: View {
    @Binding var isOn: Bool
    var onColor: Color = Theme.sage

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? onColor : Theme.tertiaryInk.opacity(0.18))
                    .frame(width: 51, height: 31)
                Circle()
                    .fill(.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.2), radius: 2.5, x: 0, y: 2)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Read-only switch (drives an action) — used for HealthKit metric rows.
struct ToggleRow: View {
    let on: Bool
    let action: () -> Void
    var onColor: Color = Theme.sage

    var body: some View {
        Button(action: action) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? onColor : Theme.tertiaryInk.opacity(0.18))
                    .frame(width: 51, height: 31)
                Circle()
                    .fill(.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.2), radius: 2.5, x: 0, y: 2)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let text: String
    var color: Color? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(text.uppercased())
                .font(.system(size: 13, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(Theme.secondaryInk)
        }
        .padding(.horizontal, 8)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScreenTitle: View {
    let sub: String?
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let sub {
                Text(sub)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
            }
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A divider that stops short of card edges.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.quaternaryInk.opacity(0.25))
            .frame(height: 0.5)
    }
}

/// Sheet for picking a day to edit (no future dates).
struct DatePickerSheet: View {
    let selected: String      // yyyy-MM-dd
    let onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                VStack {
                    DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Theme.accentDark)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surfaceOverlay))
                        .padding()
                    Spacer()
                }
            }
            .navigationTitle("Go to day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Go") { onPick(date); dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear { date = AppStore.parse(selected) }
        .tint(Theme.accentDark)
    }
}

/// A simple wrapping layout (left-to-right, wraps to new rows) for chips/tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0; rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Generic concentric ring gauge — the shared visual for the Today ring row, ring detail sheets,
/// and the sleep/readiness module. `fraction` is 0...1; `available` renders a dim "—" placeholder
/// instead of a misleading empty/zero ring when there's no data yet.
/// `lineWidth` nil = proportional to size (the thick Apple-rings look); pass a value to override.
struct RingGaugeView: View {
    var fraction: Double
    var value: String
    var label: String
    var color: Color
    var available: Bool = true
    var size: CGFloat = 66
    var lineWidth: CGFloat? = nil

    private var stroke: CGFloat { lineWidth ?? max(8, size * 0.14) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(available ? 0.16 : 0.10), lineWidth: stroke)
            if available {
                // The arc sweeps from a dimmer tail into the full colour — reads as depth on glass
                // without needing a second hue.
                Circle().trim(from: 0, to: max(0.015, min(1, fraction)))
                    .stroke(
                        AngularGradient(gradient: Gradient(colors: [color.opacity(0.55), color]),
                                        center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
            VStack(spacing: 0) {
                Text(available ? value : "—")
                    .font(Theme.serif(size * 0.30)).foregroundStyle(available ? Theme.ink : Theme.tertiaryInk)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.system(size: max(8.5, size * 0.115))).foregroundStyle(Theme.tertiaryInk).lineLimit(1)
            }
            .padding(.horizontal, stroke + 3)
        }
        .frame(width: size, height: size)
    }
}

/// Section header + trailing action(s) on one clean baseline — replaces the ad-hoc
/// `SectionHeader … Spacer … Button().padding(.top, 22)` pattern that drifted per call site.
struct SectionHeaderRow<Trailing: View>: View {
    let text: String
    var color: Color? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            SectionHeader(text: text, color: color)
            trailing().padding(.trailing, 8)
        }
    }
}

/// Small rounded tile holding an SF Symbol, with a gradient fill.
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 30
    var corner: CGFloat = 8
    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
            )
    }
}
