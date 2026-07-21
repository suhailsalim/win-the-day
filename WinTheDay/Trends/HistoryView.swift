import SwiftUI

/// Browse past days, jump to any date, and compare progress photos.
struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickDate = Date()
    @State private var exportedText: ExportedDayText?

    private struct ExportedDayText: Identifiable { let id = UUID(); let text: String }

    private var days: [Entry] {
        store.sortedEntries().reversed()   // newest first
    }

    // (date, filename) pairs for progress photos, oldest → newest
    private var photoTimeline: [(date: String, name: String)] {
        store.sortedEntries().flatMap { e in e.photos.map { (e.date, $0) } }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        SectionHeader(text: "Jump to a day")
                        DatePicker("", selection: $pickDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact).labelsHidden()
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .glassList()
                            // Only navigate on a real user pick of a DIFFERENT day. Without this
                            // guard, `.onAppear` seeding `pickDate` to today fires onChange and the
                            // sheet dismisses itself the moment it opens.
                            .onChange(of: pickDate) { _, d in
                                guard AppStore.dateString(d) != store.date else { return }
                                store.goTo(date: d); dismiss()
                            }

                        if photoTimeline.count >= 2 {
                            SectionHeader(text: "Progress photos")
                            PhotoCompareView(first: photoTimeline.first!, last: photoTimeline.last!)
                        }

                        SectionHeader(text: "Logged days")
                        if days.isEmpty {
                            Text("Nothing logged yet.").font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16).glassList()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(days.enumerated()), id: \.element.id) { idx, e in
                                    Button { store.goTo(date: e.date); dismiss() } label: { dayRow(e) }
                                        .buttonStyle(.plain)
                                    if idx < days.count - 1 { Hairline() }
                                }
                            }
                            .glassList()
                        }
                    }
                    .padding(16).padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .onAppear { pickDate = AppStore.parse(store.date) }
            .sheet(item: $exportedText) { ShareSheet(items: [$0.text]) }
        }
        .tint(Theme.accentDark)
    }

    private func dayRow(_ e: Entry) -> some View {
        let s = store.score(e)
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.2), lineWidth: 4)
                Circle().trim(from: 0, to: CGFloat(s) / 5)
                    .stroke(s >= 3 ? Theme.sage : Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(s)").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(longDate(e.date)).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                Text(subtitle(e)).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
            }
            Spacer()
            if e.isMeaningful {
                Button { exportedText = ExportedDayText(text: store.exportDayText(e.date)) } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDark)
                }.buttonStyle(.plain).padding(.trailing, 4)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func subtitle(_ e: Entry) -> String {
        var parts: [String] = []
        parts.append("\(e.prayers.count)/5 prayers")
        if let w = Double(e.weight), w > 0 { parts.append(String(format: "%.1fkg", w)) }
        if !e.photos.isEmpty { parts.append("\(e.photos.count) 📷") }
        return parts.joined(separator: " · ")
    }

    private func longDate(_ ds: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE, d MMM yyyy"
        return f.string(from: AppStore.parse(ds))
    }
}

/// Before/after comparison with a draggable divider.
struct PhotoCompareView: View {
    let first: (date: String, name: String)
    let last: (date: String, name: String)
    @State private var split: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    if let after = PhotoStore.load(last.name) {
                        Image(uiImage: after).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height).clipped()
                    }
                    if let before = PhotoStore.load(first.name) {
                        Image(uiImage: before).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height).clipped()
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: geo.size.width * split)
                            }
                    }
                    // divider handle
                    Rectangle().fill(.white).frame(width: 2)
                        .offset(x: geo.size.width * split - 1)
                    Circle().fill(.white).frame(width: 28, height: 28)
                        .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentDark))
                        .shadow(radius: 3)
                        .offset(x: geo.size.width * split - 14)
                    // labels
                    VStack { Spacer()
                        HStack {
                            tag(shortDate(first.date)); Spacer(); tag(shortDate(last.date))
                        }.padding(8)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { v in
                    split = min(1, max(0, v.location.x / geo.size.width))
                })
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Drag to compare your first and latest photo.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk)
        }
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.4)))
    }

    private func shortDate(_ ds: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"
        return f.string(from: AppStore.parse(ds))
    }
}
