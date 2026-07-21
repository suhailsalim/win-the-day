import SwiftUI

/// Manage the library of known supplements & foods.
struct CatalogView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CatalogItem?
    @State private var startKind: CatalogKind = .supplement
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(CatalogKind.allCases, id: \.self) { kind in
                            section(kind)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .searchable(text: $searchText, prompt: "Search your library")
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(item: $editing) { item in
                ItemEditor(item: item)
            }
        }
        .tint(Theme.accentDark)
    }

    private func section(_ kind: CatalogKind) -> some View {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let items = store.items(of: kind).filter { query.isEmpty || $0.name.lowercased().contains(query) }
        return VStack(spacing: 0) {
            HStack {
                SectionHeader(text: kind.title)
                Spacer()
                Button {
                    editing = CatalogItem(kind: kind, name: "")
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accentDark)
                }
                .padding(.trailing, 8).padding(.top, 14)
            }

            if items.isEmpty {
                Text(!query.isEmpty ? "No matches for \u{201C}\(searchText)\u{201D}."
                     : (kind == .supplement
                        ? "Add your whey, creatine, magnesium… once, then tick them off daily."
                        : "Add foods you eat often — log them with one tap from Today."))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .glassList()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        Button { editing = item } label: { row(item) }
                            .buttonStyle(.plain)
                        if idx < items.count - 1 { Hairline() }
                    }
                }
                .glassList()
            }
        }
    }

    private func row(_ item: CatalogItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 16)).foregroundStyle(Theme.ink)
                Text(macroLine(item)).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func macroLine(_ item: CatalogItem) -> String {
        var parts: [String] = []
        if !item.serving.isEmpty { parts.append(item.serving) }
        parts.append("\(Int(item.calories)) kcal · P\(Int(item.protein))")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Add / edit a single item

struct ItemEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State var item: CatalogItem
    @State private var nlText = ""
    @State private var picker: ImagePicker.Source?
    @State private var showScanner = false
    @State private var parsing = false
    @State private var errorMsg = ""

    private var isNew: Bool { !store.data.catalog.contains { $0.id == item.id } }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        autofillCard
                        SectionHeader(text: "Details")
                        detailsCard
                        SectionHeader(text: "Quick-add")
                        quickAddCard
                        SectionHeader(text: "Vitamins & minerals")
                        microsCard
                        if !errorMsg.isEmpty {
                            Text(errorMsg).font(.system(size: 13)).foregroundStyle(Theme.coral)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.top, 10)
                        }
                        if !isNew {
                            Button(role: .destructive) {
                                store.deleteCatalogItem(item.id); dismiss()
                            } label: {
                                Text("Delete item").frame(maxWidth: .infinity)
                            }
                            .padding(.top, 22)
                        }
                    }
                    .padding(16).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isNew ? "New \(item.kind == .supplement ? "supplement" : "food")" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { store.addOrUpdate(item); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } }
            }
            .fullScreenCover(item: $picker) { src in
                ImagePicker(source: src) { img in
                    if let b64 = img.base64JPEG() { Task { await autofill(image: b64) } }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScanSheet { code in Task { await lookupBarcode(code) } }
            }
        }
        .tint(Theme.accentDark)
    }

    private var autofillCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Autofill with AI").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Snap the nutrition label or describe it — \(Providers.provider(store.settings.provider).name) fills in the macros.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                pillButton("Camera", "camera.fill") { picker = .camera }
                pillButton("Photo", "photo.fill") { picker = .library }
                if item.kind == .food {
                    pillButton("Barcode", "barcode.viewfinder") { showScanner = true }
                }
            }
            TextField("Or type, e.g. \u{201C}1 scoop ON gold whey\u{201D}", text: $nlText, axis: .vertical)
                .font(.system(size: 15)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceOverlay)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.surfaceStroke, lineWidth: 0.5)))
            Button { Task { await autofill(image: nil) } } label: {
                HStack(spacing: 6) {
                    if parsing { ProgressView().tint(.white) }
                    Text(parsing ? "Reading…" : "Autofill from text")
                }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentDark], startPoint: .top, endPoint: .bottom)))
            }
            .buttonStyle(.plain)
            .disabled(parsing || nlText.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity((parsing || nlText.trimmingCharacters(in: .whitespaces).isEmpty) ? 0.6 : 1)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 0.5))
        )
    }

    private func pillButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentDark)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceOverlay)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            textRow("Name", text: $item.name, placeholder: "Whey isolate")
            Hairline()
            textRow("Serving", text: $item.serving, placeholder: "1 scoop (30g)")
            Hairline()
            numRow("Calories", value: $item.calories)
            Hairline()
            numRow("Protein (g)", value: $item.protein)
            Hairline()
            numRow("Carbs (g)", value: $item.carbs)
            Hairline()
            numRow("Fat (g)", value: $item.fat)
            Hairline()
            numRow("Fiber (g)", value: $item.fiber)
        }
        .glassList()
    }

    private static let mealChips: [(key: String, label: String)] = [
        ("breakfast", "Breakfast"), ("snacks", "Snacks"), ("lunch", "Lunch"), ("dinner", "Dinner"), ("drinks", "Drinks")
    ]

    /// Which meal(s) surface this item as a quick-add chip, plus a favorite flag — this is what
    /// keeps Today's quick-log short instead of dumping the whole library as chips.
    private var quickAddCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Always suggest").font(.system(size: 14)).foregroundStyle(Theme.ink)
                Spacer()
                ToggleRow(on: item.favorite) { item.favorite.toggle() }
            }
            Text("Leave all off to show it whenever it's used often, or pick specific meals so it only shows then.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk)
            FlowLayout(spacing: 8) {
                ForEach(Self.mealChips, id: \.key) { chip in
                    let on = item.mealTags.contains(chip.key)
                    Button {
                        if on { item.mealTags.removeAll { $0 == chip.key } } else { item.mealTags.append(chip.key) }
                    } label: {
                        Text(chip.label).font(.system(size: 13, weight: .medium)).foregroundStyle(on ? .white : Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(on ? AnyShapeStyle(Theme.sage) : AnyShapeStyle(Theme.surfaceOverlay)))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .glassList()
    }

    private var microsCard: some View {
        VStack(spacing: 0) {
            if item.micros.isEmpty {
                Text("No vitamins/minerals yet. Scan a label or autofill to pull them in, or add your own.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                ForEach($item.micros) { $m in
                    HStack {
                        TextField("Name", text: $m.name).font(.system(size: 15)).foregroundStyle(Theme.ink)
                        Spacer()
                        TextField("0", value: $m.amount, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .font(.system(size: 15)).frame(width: 60)
                        TextField("unit", text: $m.unit).font(.system(size: 13)).foregroundStyle(Theme.tertiaryInk)
                            .frame(width: 42)
                        Button { item.micros.removeAll { $0.id == m.id } } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 16)).foregroundStyle(Theme.coral)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    Hairline()
                }
            }
            Button { item.micros.append(Micro(name: "", amount: 0, unit: "mg")) } label: {
                Label("Add a vitamin / mineral", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentDark)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.plain)
        }
        .glassList()
    }

    private func textRow(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink).frame(width: 90, alignment: .leading)
            TextField(placeholder, text: text).font(.system(size: 16)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private func numRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .font(.system(size: 16)).foregroundStyle(Theme.ink).frame(width: 90)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private func lookupBarcode(_ code: String) async {
        parsing = true; errorMsg = ""
        if let found = await store.lookupBarcode(code, kind: item.kind) {
            item.name = found.name; item.serving = found.serving
            item.calories = found.calories; item.protein = found.protein
            item.carbs = found.carbs; item.fat = found.fat
            item.fiber = found.fiber; item.micros = found.micros
        } else {
            errorMsg = "Couldn\u{2019}t find that barcode. Try the camera or type it in."
        }
        parsing = false
    }

    private func autofill(image: String?) async {
        let text = nlText.trimmingCharacters(in: .whitespaces)
        guard image != nil || !text.isEmpty else { return }
        parsing = true; errorMsg = ""
        do {
            let parsed = try await store.parseCatalogItem(kind: item.kind,
                                                          text: text.isEmpty ? nil : text,
                                                          imageBase64: image)
            item.name = parsed.name
            item.serving = parsed.serving
            item.calories = parsed.calories
            item.protein = parsed.protein
            item.carbs = parsed.carbs
            item.fat = parsed.fat
            item.fiber = parsed.fiber
            item.micros = parsed.micros
        } catch {
            errorMsg = error.localizedDescription
        }
        parsing = false
    }
}

extension ImagePicker.Source: Identifiable {
    var id: Int { self == .camera ? 0 : 1 }
}
