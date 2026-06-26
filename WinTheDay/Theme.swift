import SwiftUI

enum Theme {
    // Palette from the design
    static let accent = Color(hex: 0xE6A765)
    static let accentDark = Color(hex: 0xC8843E)
    static let sage = Color(hex: 0x3DA876)
    static let ink = Color(hex: 0x1C1C1E)
    static let secondaryInk = Color(white: 0.27).opacity(0.6)   // rgba(60,60,67,0.6)
    static let tertiaryInk = Color(white: 0.27).opacity(0.5)

    // Warm tip card
    static let tipBG = Color(hex: 0xE6A765).opacity(0.14)
    static let tipBorder = Color(hex: 0xE6A765).opacity(0.30)
    static let tipText = Color(hex: 0x7A5836)

    // Newsreader serif for headline numbers, with graceful fallback to system serif.
    static func serif(_ size: CGFloat) -> Font {
        if UIFont.fontNames(forFamilyName: "Newsreader").isEmpty {
            return .system(size: size, design: .serif)
        }
        return .custom("Newsreader", size: size)
    }
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

// MARK: - Warm background with refraction blobs

struct WarmBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xFCF6EE), Color(hex: 0xF6E9DA), Color(hex: 0xF1E2D2)],
                startPoint: .top, endPoint: .bottom
            )
            blob(color: Color(hex: 0xE6A765).opacity(0.50), size: 280)
                .offset(x: -140, y: -200)
            blob(color: Color(hex: 0x78B496).opacity(0.34), size: 300)
                .offset(x: 150, y: 60)
            blob(color: Color(hex: 0xD29678).opacity(0.26), size: 240)
                .offset(x: -90, y: 320)
        }
        .ignoresSafeArea()
    }

    private func blob(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: 30)
    }
}

// MARK: - Glass card

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 22
    var tint: Color = .white.opacity(0.5)
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
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: Color(hex: 0x966E46).opacity(0.10), radius: 12, x: 0, y: 6)
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
                            .fill(Color.white.opacity(0.5))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color(hex: 0x966E46).opacity(0.10), radius: 12, x: 0, y: 6)
    }
}
