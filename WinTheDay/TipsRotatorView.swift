import SwiftUI

/// A small auto-advancing carousel of AI tips (or the deterministic fallback) — the ¾-width
/// companion to the weather mini tile. Auto-advances every 8s, pauses while loading, and lets
/// the user tap through manually or force a refresh.
struct TipsRotatorView: View {
    let tips: [String]
    let loading: Bool
    let onRefresh: () async -> Void

    @State private var index = 0

    var body: some View {
        GlassCard(padding: 12, cornerRadius: 20, tint: Theme.accent.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(Theme.accentDark)
                    Text("Tip").font(.system(size: 11, weight: .semibold)).tracking(0.3).foregroundStyle(Theme.tertiaryInk)
                    Spacer()
                    if !tips.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(tips.indices, id: \.self) { i in
                                Circle().fill(i == index ? Theme.accentDark : Theme.accent.opacity(0.25))
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                    Button { Task { await onRefresh() } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiaryInk)
                    }.buttonStyle(.plain).disabled(loading)
                }
                Text(loading && tips.isEmpty ? "Thinking of a tip\u{2026}" : (tips.indices.contains(index) ? tips[index] : "\u{2014}"))
                    .font(.system(size: 13.5)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 34, alignment: .top)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .task {
            // A view-lifecycle-scoped loop instead of a stored `Timer.publish` — this View struct
            // is a value type SwiftUI recreates on nearly every re-render (incl. during scrolling),
            // and a `let timer = Timer.publish(...).autoconnect()` would spin up a brand-new,
            // independent timer on each recreation while old ones keep firing in the background —
            // several overlapping timers all animating `index` is what caused the jiggle. `.task`
            // runs exactly once per view identity and cancels automatically on disappear.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { break }
                if !loading { advance() }
            }
        }
        .onChange(of: tips) { _, _ in index = 0 }
    }

    private func advance() {
        guard !tips.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) { index = (index + 1) % tips.count }
    }
}
