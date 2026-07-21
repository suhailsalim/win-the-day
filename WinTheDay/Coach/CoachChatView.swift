import SwiftUI

struct CoachChatView: View {
    @EnvironmentObject var store: AppStore
    /// Supplies prayer times so a confirmed `togglePrayer` gets the same on-time band the Today
    /// toggle records instead of an untimed mark.
    @EnvironmentObject var prayer: PrayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var showWriteLog = false
    @FocusState private var inputFocused: Bool
    /// True when pushed from `CoachChatListView` — leaves the automatic back button in place
    /// instead of a "Done" button, and shows the thread title.
    var showsChatsButton = false

    private let starters = [
        "How\u{2019}s my week going?",
        "A dinner to hit my protein?",
        "What should I focus on right now?",
        "Quiz me on today\u{2019}s subject"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                VStack(spacing: 0) {
                    messages
                    inputBar
                }
            }
            .navigationTitle(store.activeThread?.title ?? "Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showsChatsButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }.foregroundStyle(Theme.accentDark)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.coachWriteLog.isEmpty {
                        Button { showWriteLog = true } label: {
                            Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(Theme.accentDark)
                        }
                        .accessibilityLabel("Coach changes")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.chatMessages.isEmpty {
                        Button { store.clearChat() } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.tertiaryInk)
                        }
                    }
                }
            }
            .sheet(isPresented: $showWriteLog) { CoachWriteLogView() }
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.chatMessages.isEmpty { emptyState }
                    ForEach(store.chatMessages) { m in
                        bubble(m).id(m.id)
                    }
                    if store.chatLoading {
                        typingBubble.id("typing")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.chatMessages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: store.chatLoading) { _, _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if store.chatLoading { proxy.scrollTo("typing", anchor: .bottom) }
            else if let last = store.chatMessages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                IconTile(symbol: "sparkles", colors: [Theme.accent, Theme.accentDark], size: 34, corner: 11)
                Text("Ask me anything about your day, your week, meals, training or study. I can see your logs.")
                    .font(.system(size: 14.5)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 4)
            ForEach(starters, id: \.self) { s in
                Button { send(s) } label: {
                    HStack {
                        Text(s).font(.system(size: 14)).foregroundStyle(Theme.accentDark)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.accentDark.opacity(0.6))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surfaceOverlay))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        if let w = m.pendingWrite { writeCard(w) } else { textBubble(m) }
    }

    // MARK: - Staged write card
    //
    // Nothing has been written when this appears. Confirm is the ONLY thing that mutates data.

    @ViewBuilder private func writeCard(_ w: PendingCoachWrite) -> some View {
        GlassCard(padding: 14, cornerRadius: 18, tint: Theme.tipBG) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentDark)
                    Text(w.isPending ? "Coach wants to change your log" : "Coach change")
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.accentDark)
                    Spacer(minLength: 0)
                }
                Text(w.summary.isEmpty ? "A change to your log" : w.summary)
                    .font(.system(size: 14.5)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !w.isKnownKind {
                    Text("This app version doesn\u{2019}t know how to apply that \u{2014} nothing was changed.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                } else if w.isPending {
                    HStack(spacing: 8) {
                        Button {
                            store.commitCoachWrite(w, times: prayer.today, nextFajr: prayer.nextFajr)
                        } label: {
                            Text("Confirm")
                                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 18).padding(.vertical, 8)
                                .background(Capsule().fill(Theme.accentDark))
                        }
                        .buttonStyle(.plain)
                        Button { store.rejectCoachWrite(w) } label: {
                            Text("Dismiss")
                                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.secondaryInk)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Capsule().fill(Theme.surfaceOverlay))
                                .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: resolvedIcon(w.status))
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(resolvedTint(w.status))
                        Text(resolvedLabel(w.status))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(resolvedTint(w.status))
                    }
                }
            }
        }
        .padding(.trailing, 24)
    }

    private func resolvedLabel(_ status: String) -> String {
        switch status {
        case "confirmed": return "Applied"
        case "undone": return "Undone"
        default: return "Dismissed"
        }
    }
    private func resolvedIcon(_ status: String) -> String {
        switch status {
        case "confirmed": return "checkmark.circle.fill"
        case "undone": return "arrow.uturn.backward.circle.fill"
        default: return "xmark.circle.fill"
        }
    }
    private func resolvedTint(_ status: String) -> Color {
        status == "confirmed" ? Theme.sage : Theme.tertiaryInk
    }

    private func textBubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.isUser { Spacer(minLength: 40) }
            Text(m.text)
                .font(.system(size: 15))
                .foregroundStyle(m.isUser ? Theme.onAccent : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(m.isUser ? AnyShapeStyle(Theme.accentDark)
                                       : AnyShapeStyle(Theme.surfaceOverlay))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(m.isUser ? Color.clear : Theme.surfaceStroke, lineWidth: 0.5)
                )
            if !m.isUser { Spacer(minLength: 40) }
        }
    }

    private var typingBubble: some View {
        HStack {
            Text("Coach is thinking…")
                .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surfaceOverlay))
            Spacer(minLength: 40)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message your coach…", text: $input, axis: .vertical)
                .font(.system(size: 15)).foregroundStyle(Theme.ink)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Theme.surfaceOverlay))
                .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
            Button { send(input) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.accentDark : Theme.tertiaryInk.opacity(0.5))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.chatLoading
    }

    private func send(_ text: String) {
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }
        input = ""
        inputFocused = false
        Task { await store.sendChat(msg) }
    }
}

/// The journal of coach changes the user confirmed, newest first, each one tap undoable.
/// Capped at 20 records by `AppStore`, so this list never grows without bound.
struct CoachWriteLogView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        if store.coachWriteLog.isEmpty {
                            Text("No coach changes yet. Anything the coach proposes shows up here once you confirm it.")
                                .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        } else {
                            ForEach(Array(store.coachWriteLog.reversed())) { r in
                                if r.id != store.coachWriteLog.last?.id { Hairline() }
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.summary.isEmpty ? r.kind : r.summary)
                                            .font(.system(size: 14.5)).foregroundStyle(Theme.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(when(r.epoch))
                                            .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                                    }
                                    Spacer(minLength: 8)
                                    Button { store.undoCoachWrite(r) } label: {
                                        Text("Undo")
                                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                                            .padding(.horizontal, 14).padding(.vertical, 7)
                                            .background(Capsule().fill(Theme.surfaceOverlay))
                                            .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                            }
                        }
                    }
                    .glassList()
                    .padding(.horizontal, 16).padding(.top, 12)
                }
            }
            .navigationTitle("Coach changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accentDark)
                }
            }
        }
    }

    private func when(_ epoch: Double) -> String {
        guard epoch > 0 else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM, h:mm a"
        return f.string(from: Date(timeIntervalSince1970: epoch))
    }
}
