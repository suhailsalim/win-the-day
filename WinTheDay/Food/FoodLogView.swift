import SwiftUI

/// Meal buckets for the structured food log.
enum MealBucket: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snacks, drinks
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snacks: return "takeoutbag.and.cup.and.straw.fill"
        case .drinks: return "cup.and.saucer.fill"
        }
    }
}

/// One editable food row: name + serving, a qty stepper that recomputes live, a source badge,
/// and swipe-free inline delete. Tap opens the editor.
struct FoodEntryRow: View {
    @EnvironmentObject var store: AppStore
    let entry: FoodEntry
    @State private var showEdit = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.system(size: 15)).foregroundStyle(Theme.ink).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(Int(entry.totalKcal)) kcal · P\(Int(entry.totalProtein))")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                    sourceBadge
                }
            }
            Spacer(minLength: 6)
            stepper
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { showEdit = true }
        .sheet(isPresented: $showEdit) { FoodEntryEditor(entry: entry) }
    }

    private var stepper: some View {
        HStack(spacing: 8) {
            Button { store.setFoodQty(entry.id, qty: entry.qty - stepSize) } label: {
                Image(systemName: entry.qty <= stepSize ? "trash" : "minus")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentDark)
            }.buttonStyle(.plain)
            Text(qtyLabel).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(minWidth: 26)
            Button { store.setFoodQty(entry.id, qty: entry.qty + stepSize) } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentDark)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Theme.accent.opacity(0.12)))
    }
    private var stepSize: Double { entry.qty < 1 ? 0.25 : (entry.qty >= 4 ? 1 : 0.5) }
    private var qtyLabel: String { entry.qty == entry.qty.rounded() ? "×\(Int(entry.qty))" : String(format: "×%.2g", entry.qty) }

    private var sourceBadge: some View {
        Text(entry.source.label).font(.system(size: 9, weight: .semibold))
            .foregroundStyle(entry.source.trusted ? Theme.sage : Theme.tertiaryInk)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill((entry.source.trusted ? Theme.sage : Theme.tertiaryInk).opacity(0.12)))
    }
}

/// Edit a logged entry's name and per-serving numbers (corrections flow into the day totals).
struct FoodEntryEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var entry: FoodEntry

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            row("Name") { TextField("Name", text: $entry.name).multilineTextAlignment(.trailing) }
                            Hairline()
                            row("Serving") { TextField("1 serving", text: $entry.servingLabel).multilineTextAlignment(.trailing) }
                            Hairline()
                            numRow("Calories (per serving)", $entry.kcal)
                            Hairline(); numRow("Protein (g)", $entry.protein)
                            Hairline(); numRow("Carbs (g)", $entry.carbs)
                            Hairline(); numRow("Fat (g)", $entry.fat)
                            Hairline(); numRow("Fiber (g)", $entry.fiber)
                            Hairline(); numRow("Sodium (mg)", $entry.sodium)
                        }.glassList()
                        Button(role: .destructive) { store.removeFoodEntry(entry.id); dismiss() } label: {
                            Text("Remove").frame(maxWidth: .infinity)
                        }.padding(.top, 22)
                    }.padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit food").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { store.updateFoodEntry(entry); dismiss() }.fontWeight(.semibold)
                }
            }
        }.tint(Theme.accentDark)
    }
    private func row<V: View>(_ label: String, @ViewBuilder _ field: () -> V) -> some View {
        HStack { Text(label).foregroundStyle(Theme.ink); field() }
            .font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 12)
    }
    private func numRow(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer()
            TextField("0", value: value, format: .number).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).font(.system(size: 16)).frame(width: 80)
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// Add a food to a meal: instant offline search (library → DB), an online (Open Food Facts) toggle,
/// manual entry, and a "describe it" AI path — the last only touches the LLM when nothing local matched.
struct FoodAddSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var mealKey: String
    @State private var query = ""
    @State private var localResults: [FoodMatch] = []
    @State private var onlineResults: [FoodMatch] = []
    @State private var searchingOnline = false
    @State private var nlText = ""
    @State private var parsing = false
    @State private var manualName = ""
    @State private var manualKcal = ""
    @FocusState private var searchFocused: Bool
    // Meal photo → AI rows. `photoRows` is a proposal only; nothing is logged until the review sheet saves.
    @State private var photoPicker: ImagePicker.Source?
    @State private var photoCaption = ""
    @State private var photoParsing = false
    @State private var photoRows: [MealPhotoRow] = []
    @State private var photoNote = ""
    @State private var showPhotoReview = false

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        mealPicker
                        searchField
                        if !localResults.isEmpty { resultsCard("From your library & database", localResults) }
                        if !query.isEmpty && localResults.isEmpty && !searchingOnline && onlineResults.isEmpty {
                            noLocalHint
                        }
                        if !onlineResults.isEmpty { resultsCard("Open Food Facts", onlineResults) }
                        manualCard
                        if canSnapPlate { photoCard }
                        describeCard
                    }.padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Add food").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .fullScreenCover(item: $photoPicker) { src in
                ImagePicker(source: src) { img in
                    if let b64 = img.base64JPEG(maxDimension: 1024, quality: 0.6) { Task { await readPlate(b64) } }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showPhotoReview) {
                MealPhotoReviewSheet(mealKey: mealKey, note: photoNote, rows: photoRows) { dismiss() }
            }
        }
        .tint(Theme.accentDark)
        .onAppear { searchFocused = true }
    }

    /// Hidden entirely when the selected provider/model can't take an image — no dead camera button.
    private var canSnapPlate: Bool {
        Providers.supportsVision(provider: store.settings.provider, model: store.settings.model,
                                 custom: store.settings.customModel)
    }

    private var mealPicker: some View {
        Picker("Meal", selection: $mealKey) {
            ForEach(MealBucket.allCases) { Text($0.label).tag($0.rawValue) }
        }.pickerStyle(.segmented)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiaryInk)
            TextField("Search a food (e.g. dosa, curd, banana)", text: $query)
                .focused($searchFocused)
                .onChange(of: query) { _, q in
                    onlineResults = []
                    localResults = store.searchFood(q)
                }
            if searchingOnline { ProgressView() }
        }
        .padding(.horizontal, 14).padding(.vertical, 11).glassList()
    }

    private func resultsCard(_ title: String, _ matches: [FoodMatch]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.3)
                .foregroundStyle(Theme.tertiaryInk).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            ForEach(matches) { m in
                Button { store.addFoodMatch(m, mealKey: mealKey); reset() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name).font(.system(size: 15)).foregroundStyle(Theme.ink)
                            Text("\(m.servingLabel.isEmpty ? "1 serving" : m.servingLabel) · \(Int(m.kcal)) kcal · P\(Int(m.protein))")
                                .font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accentDark)
                    }.padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if m.id != matches.last?.id { Hairline() }
            }
        }.glassList()
    }

    private var noLocalHint: some View {
        VStack(spacing: 8) {
            Text("Not in your library or the database yet.").font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
            Button { Task { searchingOnline = true; onlineResults = await store.searchFoodOnline(query); searchingOnline = false } } label: {
                Label("Search Open Food Facts", systemImage: "globe").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.accentDark))
            }.buttonStyle(.plain)
        }.padding(14).frame(maxWidth: .infinity).glassList()
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter manually").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            HStack {
                TextField("Name", text: $manualName).font(.system(size: 15))
                TextField("kcal", text: $manualKcal).keyboardType(.numberPad).frame(width: 60).multilineTextAlignment(.trailing)
                Button {
                    guard !manualName.isEmpty, let k = Double(manualKcal), k > 0 else { return }
                    store.addManualFood(name: manualName, kcal: k, mealKey: mealKey); reset()
                } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.accentDark) }
                    .buttonStyle(.plain)
            }
        }.padding(14).glassList()
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "camera.viewfinder").font(.system(size: 12)).foregroundStyle(Theme.accentDark)
                Text("Snap your plate (AI)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            Text("\(Providers.provider(store.settings.provider).name) lists what it sees — you approve every row before anything is logged. The photo isn\u{2019}t saved.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Optional hint, e.g. \u{201C}the curry is fish\u{201D}", text: $photoCaption, axis: .vertical)
                .font(.system(size: 15)).padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
            if photoParsing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading your plate\u{2026}").font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                    Spacer()
                }.padding(.vertical, 3)
            } else {
                HStack(spacing: 10) {
                    photoPill("Camera", "camera.fill") { photoPicker = .camera }
                    photoPill("Photo", "photo.fill") { photoPicker = .library }
                }
            }
        }.padding(14).glassList()
    }

    private func photoPill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentDark)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 0.5)))
        }.buttonStyle(.plain)
    }

    /// Never throws or dead-ends: the store always hands back at least one editable row.
    private func readPlate(_ imageBase64: String) async {
        photoParsing = true
        let result = await store.mealPhotoRows(imageBase64: imageBase64, caption: photoCaption, mealKey: mealKey)
        photoRows = result.rows; photoNote = result.note
        photoParsing = false
        showPhotoReview = true
    }

    private var describeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Theme.accentDark)
                Text("Describe it (AI)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            Text("Known foods use your database values — AI only fills in the rest.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk)
            TextField("e.g. 2 dosa, sambar and a filter coffee", text: $nlText, axis: .vertical)
                .font(.system(size: 15)).padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
            Button {
                let t = nlText
                Task { parsing = true; _ = try? await store.logMealText(t, mealKey: mealKey); parsing = false; nlText = ""; dismiss() }
            } label: {
                HStack(spacing: 6) {
                    if parsing { ProgressView().tint(.white) }
                    Text(parsing ? "Reading…" : "Add from description")
                }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accentDark))
            }.buttonStyle(.plain).disabled(parsing || nlText.trimmingCharacters(in: .whitespaces).isEmpty)
        }.padding(14).glassList()
    }

    private func reset() {
        query = ""; localResults = []; onlineResults = []; manualName = ""; manualKcal = ""
        searchFocused = true
    }
}

/// Approve-before-save editor for meal-photo rows. Photo portion estimates run overconfident, so
/// nothing reaches the day until Save is tapped: every row stays editable (name, kcal, qty) and
/// removable, and cancelling logs nothing.
struct MealPhotoReviewSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let mealKey: String
    let note: String
    @State var rows: [MealPhotoRow]
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        if !note.isEmpty {
                            Text(note).font(.system(size: 13)).foregroundStyle(Color(hex: 0xD86B4A))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14).glassList()
                        }
                        SectionHeader(text: "On the plate")
                        rowsCard
                        Text("Photo estimates run high — check the portions before saving. Rows badged \u{201C}Your library\u{201D} use your own saved values with the portion from the photo.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.top, 10)
                    }
                    .padding(16).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Review meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(rows.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } }
            }
        }.tint(Theme.accentDark)
    }

    @ViewBuilder private var rowsCard: some View {
        if rows.isEmpty {
            Text("Nothing left to save.").font(.system(size: 13)).foregroundStyle(Theme.tertiaryInk)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14).glassList()
        } else {
            VStack(spacing: 0) {
                ForEach($rows) { $row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            TextField("Name", text: $row.entry.name)
                                .font(.system(size: 15)).foregroundStyle(Theme.ink)
                            Button { rows.removeAll { $0.id == row.id } } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 17))
                                    .foregroundStyle(Theme.tertiaryInk)
                            }.buttonStyle(.plain)
                        }
                        HStack(spacing: 6) {
                            Text(row.entry.servingLabel.isEmpty ? "1 serving" : row.entry.servingLabel)
                                .font(.system(size: 12)).foregroundStyle(Theme.secondaryInk).lineLimit(1)
                            badge(row.entry.source.label, trusted: row.entry.source.trusted)
                            if row.lowConfidence { badge("not sure", trusted: false) }
                            Spacer(minLength: 4)
                            TextField("0", value: $row.entry.kcal, format: .number).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).font(.system(size: 13)).frame(width: 48)
                            Text("kcal").font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                            qtyStepper($row.entry.qty)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if row.id != rows.last?.id { Hairline().padding(.leading, 14) }
                }
            }.glassList()
        }
    }

    private func qtyStepper(_ qty: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Button { qty.wrappedValue = max(0.25, qty.wrappedValue - 0.5) } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accentDark)
            }.buttonStyle(.plain)
            Text(qty.wrappedValue == qty.wrappedValue.rounded() ? "×\(Int(qty.wrappedValue))"
                                                                : String(format: "×%.2g", qty.wrappedValue))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).frame(minWidth: 24)
            Button { qty.wrappedValue += 0.5 } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accentDark)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Theme.accent.opacity(0.12)))
    }

    private func badge(_ text: String, trusted: Bool) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold))
            .foregroundStyle(trusted ? Theme.sage : Theme.tertiaryInk)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill((trusted ? Theme.sage : Theme.tertiaryInk).opacity(0.12)))
    }

    private func save() {
        for row in rows where !row.entry.name.trimmingCharacters(in: .whitespaces).isEmpty {
            var e = row.entry
            e.mealKey = mealKey
            store.addFoodEntry(e)
        }
        onSave()
        dismiss()
    }
}
