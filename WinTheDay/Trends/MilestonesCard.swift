import SwiftUI

/// `MilestoneTier.tintHex` stays a raw hex so the engine file can remain Foundation-only; the
/// SwiftUI side resolves it to the adaptive token of the same hue so badges survive dark mode.
extension MilestoneTier {
    var tint: Color {
        switch self {
        case .early:  return Theme.accent      // 0x6470A6
        case .steady: return Theme.sage        // 0x2FA36B
        case .rare:   return Theme.accentDark  // 0x3B4A7C
        }
    }
}

/// Milestones on Trends: what you've already earned, the lifetime totals behind it, and — quietly,
/// at the bottom — what the next records happen to be. No countdowns, no expiry, no nagging.
struct MilestonesCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let earned = store.earnedMilestones()
        let stats = store.lifetimeStats()
        let next = store.upcomingMilestones()

        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Milestones").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(earned.count) of \(MilestoneEngine.catalog.count)")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }

                if earned.isEmpty {
                    Text("Nothing yet — these are records of what you\u{2019}ve already done, so they arrive on their own.")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                              spacing: 10) {
                        ForEach(earned, id: \.def.id) { item in
                            MilestoneBadge(def: item.def, earned: item.earned)
                        }
                    }
                }

                Hairline()

                VStack(alignment: .leading, spacing: 6) {
                    Text("SINCE YOU STARTED")
                        .font(.system(size: 11.5, weight: .semibold)).tracking(0.5)
                        .foregroundStyle(Theme.accentDark)
                    ForEach(lifetimeLines(stats), id: \.self) { line in
                        Text(line).font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                    }
                }

                if !next.isEmpty {
                    Hairline()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NEXT UP")
                            .font(.system(size: 11.5, weight: .semibold)).tracking(0.5)
                            .foregroundStyle(Theme.tertiaryInk)
                        ForEach(next) { p in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(p.def.title).font(.system(size: 13)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text("\(fmt(p.current)) / \(fmt(p.def.threshold))")
                                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Theme.tertiaryInk.opacity(0.15)).frame(height: 6)
                                        Capsule().fill(p.def.tier.tint)
                                            .frame(width: geo.size.width * p.fraction, height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private func lifetimeLines(_ s: MilestoneEngine.Stats) -> [String] {
        var out = ["\(fmt(s.daysLogged)) days logged · \(fmt(s.daysWon)) won",
                   "Longest streak \(fmt(s.longestStreak)) days · \(fmt(s.perfectDays)) perfect days"]
        if s.workouts > 0 { out.append("\(fmt(s.workouts)) workouts logged") }
        if s.prayersMarked > 0 { out.append("\(fmt(s.prayersMarked)) prayers marked · \(fmt(s.prayersOnTime)) on time") }
        if s.waterGlasses > 0 { out.append("\(fmt(s.waterGlasses)) glasses of water") }
        if s.studyHours > 0 { out.append("\(fmt(s.studyHours)) focus hours") }
        if s.sleepNights > 0 { out.append("\(fmt(s.sleepNights)) nights of sleep data") }
        return out
    }

    private func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }
}

/// One earned record — icon, name, and the day it landed.
struct MilestoneBadge: View {
    let def: MilestoneDef
    var earned: EarnedMilestone?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: def.symbol)
                .font(.system(size: 16))
                .foregroundStyle(def.tier.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(def.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(earnedLabel).font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceOverlay)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
        )
    }

    private var earnedLabel: String {
        guard let d = earned?.earnedDate else { return def.detail }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}

// MARK: - Celebration

/// The one-time acknowledgement. Deliberately calm: no confetti, no streak-loss language — it
/// states what happened and gets out of the way.
struct MilestoneCelebrationSheet: View {
    let event: MilestoneEvent
    @Environment(\.dismiss) private var dismiss
    @State private var share: ShareImage?

    private struct ShareImage: Identifiable { let id = UUID(); let image: UIImage }

    var body: some View {
        ZStack {
            WarmBackground().ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                switch event {
                case .earned(let def):
                    MilestoneShareCard(def: def)
                    Text(def.detail)
                        .font(.system(size: 13)).foregroundStyle(Theme.tertiaryInk)
                case .batch(let n):
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 34)).foregroundStyle(Theme.accentDark)
                        Text("You\u{2019}ve already earned \(n) milestones")
                            .font(Theme.serif(26)).foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                        Text("Your history already cleared them. They\u{2019}re on the Trends tab.")
                            .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 8)
                }
                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    if case .earned(let def) = event {
                        Button {
                            share = renderShare(def).map { ShareImage(image: $0) }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.accentDark)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .glassList(cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        dismiss()
                    } label: {
                        Text("Good")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accentDark))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
        }
        .presentationDetents([.medium])
        .sheet(item: $share) { ShareSheet(items: [$0.image]) }
    }

    /// Render the card itself as an image so sharing sends the milestone, not a screenshot.
    @MainActor private func renderShare(_ def: MilestoneDef) -> UIImage? {
        // The shared image is a fixed light card wherever it lands, so it is rendered in the light
        // scheme explicitly — otherwise the theme inks resolve near-white on this pale background.
        let renderer = ImageRenderer(content:
            MilestoneShareCard(def: def)
                .padding(24)
                .frame(width: 360)
                .background(Color(hex: 0xF4F6FB))
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// The shareable face of a milestone — also what the celebration sheet shows.
struct MilestoneShareCard: View {
    let def: MilestoneDef

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: def.symbol)
                .font(.system(size: 40))
                .foregroundStyle(def.tier.tint)
            Text(def.title)
                .font(Theme.serif(30)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(def.line)
                .font(.system(size: 15)).foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
    }
}
