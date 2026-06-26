import SwiftUI

struct CoachChatView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @FocusState private var inputFocused: Bool

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
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accentDark)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.chatMessages.isEmpty {
                        Button { store.clearChat() } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.tertiaryInk)
                        }
                    }
                }
            }
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
                IconTile(symbol: "sparkles", colors: [Theme.accent, Color(hex: 0xC8632E)], size: 34, corner: 11)
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
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.isUser { Spacer(minLength: 40) }
            Text(m.text)
                .font(.system(size: 15))
                .foregroundStyle(m.isUser ? .white : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(m.isUser ? AnyShapeStyle(Theme.accentDark)
                                       : AnyShapeStyle(Color.white.opacity(0.7)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(m.isUser ? 0 : 0.7), lineWidth: 0.5)
                )
            if !m.isUser { Spacer(minLength: 40) }
        }
    }

    private var typingBubble: some View {
        HStack {
            Text("Coach is thinking…")
                .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.6)))
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
                .background(Capsule().fill(Color.white.opacity(0.7)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
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
