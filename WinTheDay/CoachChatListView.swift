import SwiftUI

/// The coach's conversation list — new/rename/delete threads, then push into `CoachChatView`
/// for the active one. Replaces the old single always-on transcript.
struct CoachChatListView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: CoachThread?
    @State private var renameText = ""
    @State private var pushActive = false

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                if store.threadsOrdered.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(store.threadsOrdered) { t in
                                Button {
                                    store.switchThread(t.id)
                                    pushActive = true
                                } label: { row(t) }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { store.deleteThread(t.id) } label: { Label("Delete", systemImage: "trash") }
                                    Button { renaming = t; renameText = t.title } label: { Label("Rename", systemImage: "pencil") }
                                        .tint(Theme.accentDark)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() }.foregroundStyle(Theme.accentDark) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.newThread()
                        pushActive = true
                    } label: { Image(systemName: "square.and.pencil") }
                    .foregroundStyle(Theme.accentDark)
                }
            }
            .navigationDestination(isPresented: $pushActive) { CoachChatView(showsChatsButton: true) }
            .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") { if let r = renaming { store.renameThread(r.id, title: renameText) }; renaming = nil }
            }
        }
        .tint(Theme.accentDark)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            IconTile(symbol: "sparkles", colors: [Theme.accent, Color(hex: 0x3B4A7C)], size: 40, corner: 13)
            Text("No chats yet").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Start a conversation — Coach can see your logs.")
                .font(.system(size: 13.5)).foregroundStyle(Theme.secondaryInk).multilineTextAlignment(.center)
            Button {
                store.newThread()
                pushActive = true
            } label: {
                Label("New chat", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(Theme.accentDark))
            }.buttonStyle(.plain).padding(.top, 4)
        }
        .padding(24)
    }

    private func row(_ t: CoachThread) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 16)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(t.messages.last?.text ?? "No messages yet")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.tertiaryInk).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
