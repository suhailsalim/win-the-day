import SwiftUI

/// An animated bottle that fills to `progress` (0…1) with a gentle moving wave.
struct WaterBottleView: View {
    var progress: Double
    var currentMl: Int
    var targetMl: Int

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        let bottle = BottleShape()
        return ZStack {
            // glass
            bottle.fill(Theme.surfaceOverlay)
            bottle.stroke(Theme.surfaceStroke, lineWidth: 1.5)

            // water — a STATIC wavy surface. The previous TimelineView(.animation) redrew this
            // at the display's full refresh rate (60–120 fps) forever, rebuilding the sine polyline
            // every frame while the hydration module sat on-screen — the dominant cause of the
            // app's high idle CPU / "High" energy. The fill height still animates on change via the
            // container's `.animation(value: clamped)`, so adding water is still lively.
            GeometryReader { geo in
                let h = geo.size.height
                let fillHeight = h * clamped
                ZStack(alignment: .bottom) {
                    Wave(phase: 0, amplitude: clamped > 0.02 ? 5 : 0)
                        .fill(LinearGradient(colors: [Theme.adaptive(light: 0x6FB7FF, darkGrey: 0x8CC8FF),
                                                      Theme.adaptive(light: 0x2E8AE0, darkGrey: 0x4E9FE8)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: max(0, fillHeight) + 12)
                        .offset(y: 6)
                }
                .frame(width: geo.size.width, height: h, alignment: .bottom)
            }
            .clipShape(bottle)

            VStack(spacing: 1) {
                Text("\(currentMl)")
                    .font(Theme.serif(26)).foregroundStyle(clamped > 0.55 ? Theme.onAccent : Theme.ink)
                Text("/ \(targetMl) ml")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(clamped > 0.6 ? Theme.onAccent.opacity(0.85) : Theme.secondaryInk)
            }
        }
        .frame(width: 92, height: 150)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: clamped)
    }
}

/// Symmetric bottle outline (cap → neck → shoulders → body).
private struct BottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height, cx = w / 2
        let neckHalf = w * 0.20          // half neck width
        let neckBottom = h * 0.20        // where shoulders begin
        let r = w * 0.24                 // body corner radius

        p.move(to: CGPoint(x: cx - neckHalf, y: 0))                 // cap top-left
        p.addLine(to: CGPoint(x: cx - neckHalf, y: neckBottom * 0.55)) // left neck
        p.addQuadCurve(to: CGPoint(x: 0, y: neckBottom + r),       // shoulder → left wall
                       control: CGPoint(x: 0, y: neckBottom * 0.8))
        p.addLine(to: CGPoint(x: 0, y: h - r))                     // left wall
        p.addQuadCurve(to: CGPoint(x: r, y: h), control: CGPoint(x: 0, y: h)) // bottom-left
        p.addLine(to: CGPoint(x: w - r, y: h))                     // bottom
        p.addQuadCurve(to: CGPoint(x: w, y: h - r), control: CGPoint(x: w, y: h)) // bottom-right
        p.addLine(to: CGPoint(x: w, y: neckBottom + r))            // right wall
        p.addQuadCurve(to: CGPoint(x: cx + neckHalf, y: neckBottom * 0.55), // shoulder → right neck
                       control: CGPoint(x: w, y: neckBottom * 0.8))
        p.addLine(to: CGPoint(x: cx + neckHalf, y: 0))             // right neck up to cap
        p.closeSubpath()
        return p
    }
}

/// Sine wave surface for the water.
private struct Wave: Shape {
    var phase: Double
    var amplitude: Double
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = amplitude
        p.move(to: CGPoint(x: 0, y: midY))
        let step = 2.0
        var x = 0.0
        while x <= rect.width {
            let y = midY + sin((x / rect.width) * .pi * 2 + phase) * amplitude
            p.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}
