import SwiftUI

enum Theme {
    // MARK: - Palette — neutral white "liquid glass" + graphite + a single cool indigo accent.
    static let accent = Color(hex: 0x6470A6)          // soft indigo (light tints / secondary)
    static let accentDark = Color(hex: 0x3B4A7C)      // deep indigo (primary accent: buttons, links)
    static let sage = Color(hex: 0x2FA36B)            // positive / success green
    static let ink = Color(hex: 0x16181F)             // graphite text
    static let secondaryInk = Color(hex: 0x5A6172)    // cool slate
    static let tertiaryInk = Color(hex: 0x9096A6)     // cool light slate

    // Tip card — neutral glass, not warm.
    static let tipBG = Color(hex: 0x3B4A7C).opacity(0.07)
    static let tipBorder = Color(hex: 0x3B4A7C).opacity(0.16)
    static let tipText = Color(hex: 0x2E3340)

    // MARK: - Type — iOS system native (SF). `display` is the big-numeral face (rings, scores,
    // timers); SF Rounded is a native system face that reads cleanly on glass. Everything else uses
    // plain `.system(...)`. The old Newsreader serif (the "editorial/Claude" look) is retired — the
    // Fonts/Newsreader.ttf resource is now unused and can be dropped from the target.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    /// Back-compat alias for existing call sites — now returns the native system numeral face.
    static func serif(_ size: CGFloat) -> Font { display(size) }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - App background — cool near-white with subtle translucent depth (no cream).

struct WarmBackground: View {   // name kept for call-site stability; renders the neutral glass base
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xF8FAFD), Color(hex: 0xEFF2F8), Color(hex: 0xE8ECF4)],
                startPoint: .top, endPoint: .bottom
            )
            // Soft cool blobs give the glass something to refract, at low opacity so it stays clean.
            blob(color: Color(hex: 0x8FA0D8).opacity(0.22), size: 300)
                .offset(x: -140, y: -210)
            blob(color: Color(hex: 0x8FC8C6).opacity(0.16), size: 300)
                .offset(x: 150, y: 70)
            blob(color: Color(hex: 0xB4ADE0).opacity(0.14), size: 240)
                .offset(x: -90, y: 330)
        }
        .ignoresSafeArea()
    }

    private func blob(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: 40)
    }
}

// MARK: - Glass surfaces

private let glassStroke = Color.white.opacity(0.6)
private let glassOverlay = Color.white.opacity(0.42)
private let glassShadow = Color(hex: 0x2A3350).opacity(0.10)

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 22
    var tint: Color = .white.opacity(0.42)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(glassStroke, lineWidth: 0.5)
            )
            .shadow(color: glassShadow, radius: 14, x: 0, y: 8)
    }
}

extension View {
    /// Card that holds a vertical list of rows with hairline dividers (no inner padding).
    func glassList(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(glassOverlay)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(glassStroke, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: glassShadow, radius: 14, x: 0, y: 8)
    }
}
