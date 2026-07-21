import SwiftUI

// MARK: - Theme selection
//
// `ThemeMode`/`DarkStyle` themselves live in Core/Models.swift, because that file is compiled into
// the Foundation-only EngineTests package and cannot see SwiftUI. Only the SwiftUI bridge is here.

extension ThemeMode {
    /// `nil` hands control back to iOS, which is what `.system` means.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum Theme {
    // MARK: - Live style state
    //
    // These mirror `AppSettings` into UserDefaults, for the same reason `AppLock` does: a dynamic
    // `UIColor` provider can be resolved before `AppStore` has decoded its JSON (and on any thread),
    // so the palette needs a source of truth that is cheap, thread-safe, and available at cold
    // launch. `ThemeController` keeps these in step; `AppSettings` remains the real source of truth.

    static let darkStyleKey = "theme_dark_style_v1"
    static let reduceTransparencyKey = "theme_reduce_transparency_v1"

    /// True when the user picked the true-black dark flavour.
    static var darkIsBlack: Bool {
        UserDefaults.standard.string(forKey: darkStyleKey) == DarkStyle.black.rawValue
    }

    /// True when iOS Accessibility → Reduce Transparency is on, so glass becomes opaque.
    /// Mirrored rather than read from `UIAccessibility` directly because this is read from the
    /// colour-resolution path, which is not guaranteed to be on the main actor.
    static var glassOff: Bool {
        UserDefaults.standard.bool(forKey: reduceTransparencyKey)
    }

    /// A colour that resolves per trait collection, and — when dark — per the user's dark flavour.
    /// The closure runs at draw time, so flipping the flavour changes every token at once.
    static func adaptive(light: UInt, darkGrey: UInt, darkBlack: UInt? = nil) -> Color {
        Color(UIColor { traits in
            guard traits.userInterfaceStyle == .dark else { return UIColor(hex: light) }
            return UIColor(hex: darkIsBlack ? (darkBlack ?? darkGrey) : darkGrey)
        })
    }

    // MARK: - Palette
    //
    // Light stays the established neutral white "liquid glass" + graphite + cool indigo. Dark keeps
    // the same hues but lifts the accents (a 0x3B4A7C indigo is unreadable on charcoal) and drops
    // the inks to near-white. True-black differs from grey only where a surface would otherwise
    // glow: text can stay identical.

    static var accent: Color      { adaptive(light: 0x6470A6, darkGrey: 0x9AA6DC) }
    static var accentDark: Color  { adaptive(light: 0x3B4A7C, darkGrey: 0xAEB9EE) }
    static var sage: Color        { adaptive(light: 0x2FA36B, darkGrey: 0x4FC98D) }
    static var ink: Color         { adaptive(light: 0x16181F, darkGrey: 0xF2F4F8) }
    static var secondaryInk: Color { adaptive(light: 0x5A6172, darkGrey: 0xAEB5C4) }
    static var tertiaryInk: Color  { adaptive(light: 0x9096A6, darkGrey: 0x7E8698) }
    /// The faintest readable text — replaces the old hardcoded `Color(white: 0.27).opacity(0.35…0.4)`.
    static var quaternaryInk: Color { adaptive(light: 0xB3B8C4, darkGrey: 0x646C7E) }

    /// Warning / over-target. Kept as one token so it can be lifted for dark in one place.
    static var coral: Color       { adaptive(light: 0xD86B4A, darkGrey: 0xF08A66) }

    /// Foreground for content sitting **on top of** a filled `accent`/`accentDark`/`sage`/`coral`
    /// surface — a button label, a selected segment, an icon-tile glyph.
    ///
    /// This is not decoration, it is the fix for a real trap. Those fills inverted for dark: in
    /// light `accentDark` is a deep indigo and white-on-it reads fine, but in dark it resolves to a
    /// pale lavender and white-on-it measures about 1.9:1 — effectively unreadable. So the
    /// foreground has to invert with the fill, not stay white. Never use this on the page
    /// background; that is what `ink` is for.
    static var onAccent: Color    { adaptive(light: 0xFFFFFF, darkGrey: 0x14161C, darkBlack: 0x000000) }

    // Tip card — neutral glass, not warm.
    static var tipBG: Color     { adaptive(light: 0x3B4A7C, darkGrey: 0x9AA6DC).opacity(glassOff ? 0.16 : 0.07) }
    static var tipBorder: Color { adaptive(light: 0x3B4A7C, darkGrey: 0x9AA6DC).opacity(0.16) }
    static var tipText: Color   { adaptive(light: 0x2E3340, darkGrey: 0xE4E8F2) }

    // MARK: - Surfaces
    //
    // `surface` is what a card falls back to when glass is off (Reduce Transparency). It is also the
    // solid tint layered under the material, so the two paths look like the same design.

    static var surface: Color       { adaptive(light: 0xFFFFFF, darkGrey: 0x1C1F27, darkBlack: 0x0B0B0D) }
    static var surfaceStroke: Color { adaptive(light: 0xFFFFFF, darkGrey: 0x5A6172, darkBlack: 0x3A3D45)
                                        .opacity(glassOff ? 0.35 : 0.6) }
    static var surfaceShadow: Color { adaptive(light: 0x2A3350, darkGrey: 0x000000).opacity(0.10) }
    /// The translucent wash over the material. Near-transparent so "liquid glass" stays glassy.
    static var surfaceOverlay: Color {
        adaptive(light: 0xFFFFFF, darkGrey: 0x2A2E38, darkBlack: 0x101116)
            .opacity(glassOff ? 1 : 0.42)
    }

    // MARK: - Type — iOS system native (SF). `display` is the big-numeral face (rings, scores,
    // timers); SF Rounded is a native system face that reads cleanly on glass. Everything else uses
    // plain `.system(...)`.
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

extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

// MARK: - App background

/// Name kept for call-site stability; renders the neutral glass base in whichever scheme is active.
struct WarmBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
            // Soft cool blobs give the glass something to refract, at low opacity so it stays clean.
            // They are the whole point of a transparent design, so they survive in dark — just
            // dimmer. True black drops them entirely: any glow defeats the point of an OLED black.
            if !Theme.darkIsBlack {
                blob(color: Theme.adaptive(light: 0x8FA0D8, darkGrey: 0x5A6BB0).opacity(blobOpacity.0), size: 300)
                    .offset(x: -140, y: -210)
                blob(color: Theme.adaptive(light: 0x8FC8C6, darkGrey: 0x3E7C7A).opacity(blobOpacity.1), size: 300)
                    .offset(x: 150, y: 70)
                blob(color: Theme.adaptive(light: 0xB4ADE0, darkGrey: 0x6A5E9E).opacity(blobOpacity.2), size: 240)
                    .offset(x: -90, y: 330)
            }
        }
        .ignoresSafeArea()
    }

    @Environment(\.colorScheme) private var scheme

    private var gradient: [Color] {
        if scheme == .dark {
            return Theme.darkIsBlack
                ? [Color(hex: 0x000000), Color(hex: 0x000000), Color(hex: 0x000000)]
                : [Color(hex: 0x14161C), Color(hex: 0x11131A), Color(hex: 0x0D0F15)]
        }
        return [Color(hex: 0xF8FAFD), Color(hex: 0xEFF2F8), Color(hex: 0xE8ECF4)]
    }

    /// Dimmer in dark so the blobs read as depth rather than as coloured smears.
    private var blobOpacity: (Double, Double, Double) {
        scheme == .dark ? (0.14, 0.10, 0.09) : (0.22, 0.16, 0.14)
    }

    private func blob(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: 40)
    }
}

// MARK: - Glass surfaces
//
// One shape builder feeds both `GlassCard` and `glassList()` so the transparent and the
// Reduce-Transparency paths can never drift apart.

/// The one surface treatment. `GlassCard` and `glassList()` both go through this, so the
/// transparent and the Reduce-Transparency paths can never drift apart.
@ViewBuilder
private func glassFill(_ shape: RoundedRectangle, tint: Color?) -> some View {
    if Theme.glassOff {
        // Reduce Transparency is on: no material, no blur — a plain opaque card.
        shape.fill(Theme.surface)
    } else {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(tint ?? Theme.surfaceOverlay))
    }
}

extension View {
    fileprivate func glassSurface(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(glassFill(shape, tint: tint))
            .overlay(shape.strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
            .shadow(color: Theme.surfaceShadow, radius: 14, x: 0, y: 8)
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 22
    /// `nil` uses the theme's own wash. A caller-supplied tint is respected as-is (feature accents).
    var tint: Color?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: cornerRadius, tint: tint)
    }
}

extension View {
    /// Card that holds a vertical list of rows with hairline dividers (no inner padding).
    func glassList(cornerRadius: CGFloat = 22) -> some View {
        self
            .glassSurface(cornerRadius: cornerRadius)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
