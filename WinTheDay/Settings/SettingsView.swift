import SwiftUI

/// The Settings root is deliberately just a menu — every section lives on its own page
/// (see SettingsPages.swift) so nothing here competes for attention.
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var prayer: PrayerManager
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var fasting: FastingManager
    @EnvironmentObject var ramadan: RamadanManager
    @EnvironmentObject var calendar: CalendarManager

    /// Which section sheet is up. One route enum instead of a dozen booleans.
    private enum Page: String, Identifiable {
        case intelligence, appearance, todayLayout, rings, targets, reminders
        case hydration, prayer, fasting, health, calendar, privacy, backup
        var id: String { rawValue }
    }
    @State private var page: Page?

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle(sub: "Make it yours", title: "Settings")

            SectionHeader(text: "Coach & intelligence")
            VStack(spacing: 0) {
                row("sparkles", tile: Self.providerTileColors(store.settings.provider),
                    title: "Intelligence", sub: Providers.provider(store.settings.provider).name) { page = .intelligence }
            }
            .glassList()

            SectionHeader(text: "Your day")
            VStack(spacing: 0) {
                row("square.grid.2x2.fill", tile: [Theme.accent, Theme.accentDark],
                    title: "Today layout", sub: "Modules, order, colors & names") { page = .todayLayout }
                Hairline()
                row("circle.circle.fill", tile: [Theme.adaptive(light: 0x5FE08A, darkGrey: 0x84EAA6), Theme.adaptive(light: 0x16B45A, darkGrey: 0x3FD182)],
                    title: "Rings", sub: "\(store.settings.visibleRingCount) on Today") { page = .rings }
                Hairline()
                row("target", tile: [Theme.adaptive(light: 0xFF9E6B, darkGrey: 0xFFB78E), Theme.adaptive(light: 0xF4631E, darkGrey: 0xFF8A50)],
                    title: "Targets & profile",
                    sub: "\(Int(store.targets.calories)) kcal · \(Int(store.targets.protein))g protein · \(Int(store.targets.steps)) steps") { page = .targets }
                Hairline()
                row("bell.badge.fill", tile: [Theme.adaptive(light: 0x9D8CFF, darkGrey: 0xB7ABFF), Theme.adaptive(light: 0x5B43E0, darkGrey: 0x8471F2)],
                    title: "Reminders", sub: store.settings.smartReminders ? "Smart nudges on" : "Smart nudges off") { page = .reminders }
            }
            .glassList()

            SectionHeader(text: "Trackers")
            VStack(spacing: 0) {
                row("drop.fill", tile: [Theme.adaptive(light: 0x7AC0FF, darkGrey: 0x9BD2FF), Theme.adaptive(light: 0x1E8AE0, darkGrey: 0x5AB0F0)],
                    title: "Hydration", sub: "\(hydration.targetMl) ml a day") { page = .hydration }
                Hairline()
                row("moon.stars.fill", tile: [Theme.accent, Theme.accentDark],
                    title: "Prayer times",
                    sub: prayer.enabled ? (prayer.placeName.isEmpty ? "On" : prayer.placeName) : "Off") { page = .prayer }
                Hairline()
                row("timer", tile: [Theme.adaptive(light: 0xFFC36B, darkGrey: 0xFFD394), Theme.adaptive(light: 0xF0961E, darkGrey: 0xFFB44F)],
                    title: "Fasting", sub: fastingSub) { page = .fasting }
                Hairline()
                row("heart.fill", tile: [Color(hex: 0xFF5E7A), Color(hex: 0xFB1E4B)],
                    title: "Apple Health", sub: store.settings.healthkit ? "Connected" : "Off") { page = .health }
                Hairline()
                row("calendar", tile: [Color(hex: 0x6FA8FF), Color(hex: 0x3B6CF0)],
                    title: "Calendar & Reminders", sub: calendar.calAuthorized ? "Connected" : "Not connected") { page = .calendar }
            }
            .glassList()

            SectionHeader(text: "App")
            VStack(spacing: 0) {
                row("paintpalette.fill", tile: [Theme.accent, Theme.accentDark],
                    title: "Appearance",
                    sub: "\(store.settings.palette.label) · \(store.settings.theme.label)") { page = .appearance }
                Hairline()
                row("lock.fill", tile: [Color(hex: 0xB0B0B5), Color(hex: 0x6E6E73)],
                    title: "Privacy", sub: store.settings.appLockEnabled ? "App lock on" : "App lock off") { page = .privacy }
                Hairline()
                row("externaldrive.fill.badge.icloud", tile: [Color(hex: 0x6FA8FF), Color(hex: 0x3B6CF0)],
                    title: "Backup & data", sub: backupSub) { page = .backup }
                Hairline()
                row("wand.and.stars", tile: [Theme.adaptive(light: 0x9D8CFF, darkGrey: 0xB7ABFF), Theme.adaptive(light: 0x5B43E0, darkGrey: 0x8471F2)],
                    title: "Run setup again", sub: "Replay the guided onboarding") { store.replayOnboarding() }
            }
            .glassList()

            Text("Win the Day · v1.0\nNo accounts. No backend. Your data, your device.")
                .font(.system(size: 12)).foregroundStyle(Theme.quaternaryInk)
                .multilineTextAlignment(.center)
                .padding(.top, 22)
        }
        .sheet(item: $page) { p in
            switch p {
            case .intelligence: IntelligencePage()
            case .appearance:   AppearancePage()
            case .todayLayout:  TodayLayoutPage()
            case .rings:        RingEditorView()
            case .targets:      TargetsPage()
            case .reminders:    RemindersPage()
            case .hydration:    HydrationPage()
            case .prayer:       PrayerPage()
            case .fasting:      FastingPage()
            case .health:       HealthSettingsPage()
            case .calendar:     CalendarPage()
            case .privacy:      PrivacyPage()
            case .backup:       BackupPage()
            }
        }
    }

    private var fastingSub: String {
        if ramadan.mode != .off { return "Ramadan mode" }
        return fasting.enabled ? "\(fasting.protocolName) window" : "Off"
    }

    private var backupSub: String {
        if let d = store.lastAutoBackup {
            let f = DateFormatter(); f.dateFormat = "d MMM, h:mm a"
            return "Auto-backup \(f.string(from: d))"
        }
        return "Export, restore or reset"
    }

    private func row(_ symbol: String, tile: [Color], title: String, sub: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, colors: tile, size: 32, corner: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Text(sub).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared helpers (used by SettingsPages too)

    static func providerTileColors(_ provider: String) -> [Color] {
        switch provider {
        case "apple": return [Color(hex: 0xB0B0B5), Color(hex: 0x6E6E73)]
        case "openai": return [Color(hex: 0x3FC8A8), Color(hex: 0x10A37F)]
        case "gemini": return [Color(hex: 0x6FA8FF), Color(hex: 0x3B6CF0)]
        case "openrouter": return [Color(hex: 0x8E7CF0), Color(hex: 0x5B45D6)]
        case "deepseek": return [Color(hex: 0x5B8DEF), Color(hex: 0x2E5BC8)]
        // The two near-black vendor greys would sink into the dark card, so they get lifted.
        case "ollama": return [Color(hex: 0x9AA0A6), Theme.adaptive(light: 0x3C4043, darkGrey: 0x5F656C)]
        case "ollamacloud": return [Color(hex: 0x7D8590), Theme.adaptive(light: 0x1F2328, darkGrey: 0x4A515C)]
        default: return [Theme.accent, Theme.accentDark]
        }
    }

    static func hex(of color: Color) -> UInt {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt(max(0, r) * 255) << 16) | (UInt(max(0, g) * 255) << 8) | UInt(max(0, b) * 255)
    }
}
