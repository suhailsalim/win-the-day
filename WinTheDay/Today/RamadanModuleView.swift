import SwiftUI

/// Today's Ramadan module: day N, a live countdown (to iftar inside the fast, to suhoor's end
/// before Fajr), the day's fast progress, and the per-day "not fasting today" escape.
///
/// Hides itself entirely outside Ramadan even when the module is enabled — the point of a *mode*
/// is that it costs nothing for eleven months. Lives in its own file (like `QuranModuleView`)
/// because it carries its own ticker and actions.
struct RamadanModuleView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var prayer: PrayerManager
    @EnvironmentObject var ramadan: RamadanManager

    /// Cheap reconcile loop: the auto-fast can only flip at Fajr/Maghrib, so a minute is plenty.
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        if ramadan.isActiveToday {
            VStack(spacing: 0) {
                SectionHeader(text: headerText, color: store.moduleColor("ramadan"))
                card
            }
            .onReceive(tick) { _ in
                ramadan.refresh()
                store.setRamadanFasting(ramadan.isFastingToday)
            }
        }
    }

    private var headerText: String {
        if let n = ramadan.dayNumber { return "Ramadan · day \(n)" }
        return "Ramadan"
    }

    // MARK: - Card

    private var card: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date
            GlassCard(padding: 16, cornerRadius: 20, tint: Theme.accentDark.opacity(0.12)) {
                VStack(alignment: .leading, spacing: 12) {
                    headline(now: now)
                    if ramadan.hasComputedTimes {
                        if fastingToday { windowBar(now: now) }
                        boundaryRow
                    } else {
                        Text("Prayer times aren\u{2019}t available yet — turn on location on the Prayer screen and suhoor/iftar will fill in. Until then the fast stays manual.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
                    }
                    actionRow
                }
            }
            .padding(.bottom, 4)
        }
    }

    private var fastingToday: Bool { !ramadan.isSkipped(ramadan.todayKey) }

    private func headline(now: Date) -> some View {
        HStack(spacing: 13) {
            IconTile(symbol: "moon.stars.fill",
                     colors: [Theme.adaptive(light: 0x6470A6, darkGrey: 0x7C89C8),
                              Theme.adaptive(light: 0x3B4A7C, darkGrey: 0x5766A8)], size: 36, corner: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(now: now))
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
    }

    /// The one line that matters right now.
    private func title(now: Date) -> String {
        guard fastingToday else { return "Not fasting today" }
        guard ramadan.hasComputedTimes else { return "Ramadan mode is on" }
        if ramadan.inFastingWindow(now) {
            return "Iftar in \(countdown(to: ramadan.iftar, from: now))"
        }
        // Before Fajr → today's suhoor still open. After Maghrib → tomorrow's Fajr, not today's.
        let target = (ramadan.suhoorEnd.map { now < $0 } ?? false) ? ramadan.suhoorEnd : ramadan.nextSuhoorEnd
        return "Suhoor ends in \(countdown(to: target, from: now))"
    }

    private var subtitle: String {
        if let left = ramadan.daysRemaining {
            return left == 1 ? "Last day of the month" : "\(left) days of Ramadan left"
        }
        return "Ramadan mode"
    }

    private var boundaryRow: some View {
        HStack(spacing: 12) {
            Text("Suhoor \(timeStr(ramadan.suhoorEnd))").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
            Text("Iftar \(timeStr(ramadan.iftar))").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
            Spacer(minLength: 0)
        }
    }

    /// Fajr → Maghrib progress for the day (the fast ring, flattened into the card).
    private func windowBar(now: Date) -> some View {
        let progress = dayProgress(now: now)
        return VStack(spacing: 5) {
            HStack {
                Text(ramadan.inFastingWindow(now) ? "Fasting" : (progress >= 1 ? "Fast complete" : "Before Fajr"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(progress >= 1 ? Theme.sage : Theme.accentDark)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.tertiaryInk.opacity(0.15)).frame(height: 8)
                    Capsule().fill(progress >= 1 ? Theme.sage : Theme.accentDark)
                        .frame(width: geo.size.width * progress, height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                ramadan.setSkipped(fastingToday, day: ramadan.todayKey)
                store.setRamadanFasting(ramadan.isFastingToday)
            } label: {
                Text(fastingToday ? "Not fasting today" : "Fasting today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(fastingToday ? Theme.accentDark : .white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(fastingToday ? AnyShapeStyle(Theme.surfaceOverlay)
                                                            : AnyShapeStyle(Theme.accentDark)))
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(fastingToday ? 0.4 : 0), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Helpers

    /// 0…1 across today's Fajr→Maghrib window (0 before Fajr, 1 from Maghrib on).
    private func dayProgress(now: Date) -> Double {
        guard let fajr = ramadan.suhoorEnd, let maghrib = ramadan.iftar, maghrib > fajr else { return 0 }
        return min(1, max(0, now.timeIntervalSince(fajr) / maghrib.timeIntervalSince(fajr)))
    }

    private func countdown(to date: Date?, from now: Date) -> String {
        guard let date else { return "\u{2014}" }
        var secs = Int(date.timeIntervalSince(now))
        if secs < 0 { secs += 24 * 3600 }   // wrap to tomorrow for display
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func timeStr(_ date: Date?) -> String {
        guard let date else { return "\u{2014}" }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
