import SwiftUI
import UniformTypeIdentifiers

// MARK: - Page scaffold
//
// Every Settings section lives behind the root menu as its own sheet page. Sheets (not
// NavigationLinks) because the tab content renders inside RootView's ScrollView — there is no
// NavigationStack to push onto, and every editor in the app already presents as a sheet.

struct SettingsSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) { content() }
                        .padding(16).padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } }
            }
        }
        .tint(Theme.accentDark)
    }
}

// MARK: - Shared rows

struct StepperRow: View {
    let label: String
    let value: String
    let dec: () -> Void
    let inc: () -> Void

    var body: some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).font(.system(size: 16)).foregroundStyle(Theme.tertiaryInk).frame(minWidth: 64, alignment: .trailing)
            HStack(spacing: 0) {
                Button(action: dec) { stepIcon("minus") }
                Divider().frame(height: 22)
                Button(action: inc) { stepIcon("plus") }
            }
            .background(Capsule().fill(Theme.surfaceOverlay))
            .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func stepIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accentDark)
            .frame(width: 38, height: 32)
    }
}

func pickerLabelRow(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
        Spacer()
        Text(value).font(.system(size: 16)).foregroundStyle(Theme.tertiaryInk)
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(Theme.quaternaryInk)
    }
    .padding(.horizontal, 16).padding(.vertical, 13)
}

struct ToggleTextRow: View {
    let label: String
    var sub: String = ""
    let on: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
                if !sub.isEmpty {
                    Text(sub).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            ToggleRow(on: on, action: action)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Intelligence

struct IntelligencePage: View {
    @EnvironmentObject var store: AppStore

    @State private var providersOpen = false
    @State private var apiKey = ""
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, running, ok(String), failed(String)
    }

    private var provider: AIProvider { Providers.provider(store.settings.provider) }

    var body: some View {
        SettingsSheet(title: "Intelligence") {
            intelligenceCard
            Text(provider.foot)
                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                .padding(.horizontal, 16).padding(.top, 7)
                .frame(maxWidth: .infinity, alignment: .leading)

            if provider.needsKey { apiKeyCard }
            if provider.id == "ollama" { ollamaHostCard }
            if provider.allowsCustomModel && store.settings.model == "custom" { customModelCard }
            testConnectionCard
            coachWritesCard
        }
        .onAppear { apiKey = Keychain.get(store.settings.provider) }
    }

    private var intelligenceCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { providersOpen.toggle() }
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: "sparkles", colors: providerTile)
                    Text("Provider").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(provider.name).font(.system(size: 16)).foregroundStyle(Theme.tertiaryInk)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
                        .rotationEffect(.degrees(providersOpen ? 90 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            Hairline()

            if providersOpen {
                ForEach(Providers.all) { p in
                    Button { selectProvider(p.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 15.5)).foregroundStyle(Theme.ink)
                                Text(p.tag).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                            }
                            Spacer()
                            if p.id == store.settings.provider { checkmark }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Theme.accent.opacity(0.06))
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
            }

            Text(provider.name + " models")
                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 9).padding(.bottom, 6)

            ForEach(provider.models) { m in
                Hairline()
                Button { store.setModel(m.id); testState = .idle } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name).font(.system(size: 16)).foregroundStyle(Theme.ink)
                            if !m.sub.isEmpty {
                                Text(m.sub).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                            }
                        }
                        Spacer()
                        if m.id == store.settings.model { checkmark }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }
        }
        .glassList()
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accentDark)
    }

    private var providerTile: [Color] {
        SettingsView.providerTileColors(store.settings.provider)
    }

    private func selectProvider(_ id: String) {
        store.setProvider(id)
        withAnimation { providersOpen = false }
        apiKey = Keychain.get(id)
        testState = .idle
    }

    private var apiKeyCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "key.fill", colors: [Color(hex: 0xB0B0B5), Color(hex: 0x6E6E73)])
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(provider.name) API key").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Text("Stored in your device Keychain").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            Hairline()
            SecureField("Paste API key", text: $apiKey)
                .font(.system(size: 15)).foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 16).padding(.vertical, 13)
                .onChange(of: apiKey) { _, v in Keychain.set(v, for: store.settings.provider) }
        }
        .glassList()
        .padding(.top, 12)
    }

    private var testConnectionCard: some View {
        VStack(spacing: 0) {
            Button { runTest() } label: {
                HStack(spacing: 12) {
                    if testState == .running {
                        ProgressView().scaleEffect(0.85).frame(width: 22, height: 22)
                    } else {
                        IconTile(symbol: "bolt.horizontal.circle", colors: providerTile)
                    }
                    Text(testState == .running ? "Testing\u{2026}" : "Test connection")
                        .font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    switch testState {
                    case .ok:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sage)
                    case .failed:
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.coral)
                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .disabled(testState == .running)

            if case .ok(let msg) = testState {
                Hairline()
                Text("Connected \u{2014} \(provider.name) replied \u{201C}\(msg)\u{201D}.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            } else if case .failed(let msg) = testState {
                Hairline()
                Text(msg)
                    .font(.system(size: 12)).foregroundStyle(Theme.accentDark)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .glassList()
        .padding(.top, 12)
    }

    private var coachWritesCard: some View {
        VStack(spacing: 0) {
            ToggleTextRow(label: "Coach can propose changes",
                          sub: "Log food, set meal text/times, mark prayers \u{2014} always as a card you confirm first",
                          on: store.settings.coachWritesEnabled) {
                store.updateSettings { $0.coachWritesEnabled.toggle() }
            }
        }
        .glassList()
        .padding(.top, 12)
    }

    private func runTest() {
        testState = .running
        Task {
            do {
                let reply = try await store.testAIConnection()
                await MainActor.run { testState = .ok(reply) }
            } catch {
                await MainActor.run { testState = .failed(error.localizedDescription) }
            }
        }
    }

    private var customModelCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "slider.horizontal.3", colors: providerTile)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Custom model id").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Text(provider.id == "ollama" ? "Name of a model you\u{2019}ve pulled, e.g. llama3.1"
                                                  : "e.g. mistralai/mistral-large").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            Hairline()
            TextField("model id", text: Binding(
                get: { store.settings.customModel },
                set: { v in store.updateSettings { $0.customModel = v } }))
                .font(.system(size: 15)).foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .glassList()
        .padding(.top, 12)
    }

    private var ollamaHostCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "server.rack", colors: [Color(hex: 0xB0B0B5), Color(hex: 0x6E6E73)])
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ollama server").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Text("Your machine\u{2019}s address on this network").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            Hairline()
            TextField("http://192.168.1.10:11434", text: Binding(
                get: { store.settings.ollamaHost },
                set: { v in store.updateSettings { $0.ollamaHost = v } }))
                .font(.system(size: 15)).foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .padding(.horizontal, 16).padding(.vertical, 13)
            Hairline()
            Text("Run `OLLAMA_HOST=0.0.0.0 ollama serve` so your phone can reach it. localhost only works in the simulator.")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
                .padding(.horizontal, 16).padding(.vertical, 9)
        }
        .glassList()
        .padding(.top, 12)
    }
}

// MARK: - Appearance

struct AppearancePage: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var theme: ThemeController

    var body: some View {
        SettingsSheet(title: "Appearance") {
            SectionHeader(text: "Color theme")
            paletteCard
            SectionHeader(text: "Light & dark")
            modeCard
        }
    }

    /// One swatch per palette — the two accent dots preview the actual colours.
    private var paletteCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(ThemePalette.allCases.enumerated()), id: \.element) { idx, p in
                let spec = Theme.spec(p)
                let on = store.settings.palette == p
                Button { store.updateSettings { $0.themePalette = p.rawValue } } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color(hex: spec.bg.2)).frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
                            HStack(spacing: 2) {
                                Circle().fill(Color(hex: spec.accent.light)).frame(width: 11, height: 11)
                                Circle().fill(Color(hex: spec.deep.light)).frame(width: 11, height: 11)
                            }
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.label).font(.system(size: 16)).foregroundStyle(Theme.ink)
                            Text(p.note).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                        }
                        Spacer()
                        if on {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accentDark)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                if idx < ThemePalette.allCases.count - 1 { Hairline() }
            }
        }
        .glassList()
    }

    @ViewBuilder private var modeCard: some View {
        VStack(spacing: 0) {
            Menu {
                ForEach(ThemeMode.allCases, id: \.self) { m in
                    Button(m.label) { store.updateSettings { $0.themeMode = m.rawValue } }
                }
            } label: {
                pickerLabelRow("Theme", store.settings.theme.label)
            }
            // Only meaningful once something can actually be dark.
            if store.settings.theme != .light {
                Hairline()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dark style").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    HStack(spacing: 0) {
                        ForEach(DarkStyle.allCases, id: \.self) { s in
                            let on = store.settings.dark == s
                            Button { store.updateSettings { $0.darkStyle = s.rawValue } } label: {
                                Text(s.label).font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .background(on ? Theme.accentDark : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.surfaceOverlay).clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 0.5))
                    Text(store.settings.dark.note)
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
            Hairline()
            HStack(spacing: 8) {
                Image(systemName: theme.glassOn ? "circle.hexagongrid.fill" : "square.fill")
                    .font(.system(size: 13)).foregroundStyle(Theme.accentDark)
                Text(theme.glassOn
                     ? "Liquid glass is on. Turn on Reduce Transparency in iOS Settings → Accessibility → Display & Text Size to switch to solid surfaces."
                     : "Solid surfaces, because Reduce Transparency is on in iOS Accessibility settings.")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .glassList()
    }
}

// MARK: - Today layout (modules, colors, pillar names)

struct TodayLayoutPage: View {
    @EnvironmentObject var store: AppStore
    @State private var showModulesEditor = false

    private let colorableModules = ["rings", "coach", "weather", "prayer", "quran", "ramadan", "fasting", "sleep", "health", "meals", "hydration",
                                    "regimen",
                                    "quickLog", "habits", "score", "workStudy", "training", "photos"]

    var body: some View {
        SettingsSheet(title: "Today layout") {
            SectionHeader(text: "Modules")
            Button { showModulesEditor = true } label: {
                HStack {
                    Image(systemName: "arrow.up.arrow.down").foregroundStyle(Theme.accentDark)
                    Text("Reorder modules").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
                }
                .padding(.horizontal, 16).padding(.vertical, 13).glassList()
            }
            .buttonStyle(.plain).padding(.bottom, 10)
            modulesCard

            SectionHeader(text: "Module colors")
            moduleColorsCard

            SectionHeader(text: "Pillar names")
            pillarNamesCard
        }
        .sheet(isPresented: $showModulesEditor) { ModulesEditorView() }
    }

    private var modulesCard: some View {
        VStack(spacing: 0) {
            moduleToggle("AI coach", \.coach) { m, v in m.coach = v }
            Hairline()
            moduleToggle("Prayer times", \.prayer) { m, v in m.prayer = v }
            Hairline()
            moduleToggle("Apple Health card", \.health) { m, v in m.health = v }
            Hairline()
            moduleToggle("Meals & calories", \.meals) { m, v in m.meals = v }
            Hairline()
            moduleToggle("Hydration", \.hydration) { m, v in m.hydration = v }
            Hairline()
            moduleToggle("Quick log", \.quickLog) { m, v in m.quickLog = v }
            Hairline()
            moduleToggle("Work & study", \.workStudy) { m, v in m.workStudy = v }
            Hairline()
            moduleToggle("Training & body", \.training) { m, v in m.training = v }
            Hairline()
            moduleToggle("Photos", \.photos) { m, v in m.photos = v }
        }
        .glassList()
    }

    private func moduleToggle(_ label: String, _ kp: KeyPath<ModulePrefs, Bool>, _ set: @escaping (inout ModulePrefs, Bool) -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer()
            ToggleRow(on: store.modules[keyPath: kp]) {
                store.updateModules { set(&$0, !$0[keyPath: kp]) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private var moduleColorsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(colorableModules.enumerated()), id: \.offset) { idx, key in
                HStack {
                    Text(store.modules.label(key)).font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { store.moduleColor(key) },
                        set: { c in store.updatePersonal { $0.moduleColors[key] = SettingsView.hex(of: c) } }))
                        .labelsHidden()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                if idx < colorableModules.count - 1 { Hairline() }
            }
        }
        .glassList()
    }

    private var pillarNamesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(Pillar.allCases.enumerated()), id: \.element) { idx, p in
                HStack(spacing: 12) {
                    Image(systemName: p.icon).font(.system(size: 14)).foregroundStyle(Color(hex: p.hex)).frame(width: 22)
                    TextField(p.title, text: Binding(
                        get: { store.personal.pillarTitles[p.rawValue] ?? "" },
                        set: { v in store.updatePersonal { $0.pillarTitles[p.rawValue] = v } }))
                        .font(.system(size: 16)).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                if idx < Pillar.allCases.count - 1 { Hairline() }
            }
        }
        .glassList()
    }
}

// MARK: - Targets & profile (daily targets, eating profile, the prize)

struct TargetsPage: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        SettingsSheet(title: "Targets & profile") {
            SectionHeader(text: "Daily targets")
            targetsCard
            SectionHeader(text: "Eating score profile")
            eatingProfileCard
            SectionHeader(text: "The prize")
            prizeCard
            Text("The prize is your one priority metric — it headlines the Trends tab.")
                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                .padding(.horizontal, 16).padding(.top, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var targetsCard: some View {
        VStack(spacing: 0) {
            StepperRow(label: "Calories", value: "\(Int(store.targets.calories)) kcal",
                       dec: { store.updateTargets { $0.calories = max(800, $0.calories - 50) } },
                       inc: { store.updateTargets { $0.calories += 50 } })
            Hairline()
            StepperRow(label: "Protein", value: "\(Int(store.targets.protein)) g",
                       dec: { store.updateTargets { $0.protein = max(40, $0.protein - 5) } },
                       inc: { store.updateTargets { $0.protein += 5 } })
            Hairline()
            StepperRow(label: "Steps", value: "\(Int(store.targets.steps))",
                       dec: { store.updateTargets { $0.steps = max(1000, $0.steps - 500) } },
                       inc: { store.updateTargets { $0.steps += 500 } })
        }
        .glassList()
    }

    private var eatingProfileCard: some View {
        VStack(spacing: 0) {
            StepperRow(label: "Age", value: "\(Int(store.targets.ageYears))",
                       dec: { store.updateTargets { $0.ageYears = max(13, $0.ageYears - 1) } },
                       inc: { store.updateTargets { $0.ageYears += 1 } })
            Hairline()
            StepperRow(label: "Height", value: "\(Int(store.targets.heightCm)) cm",
                       dec: { store.updateTargets { $0.heightCm = max(120, $0.heightCm - 1) } },
                       inc: { store.updateTargets { $0.heightCm += 1 } })
            Hairline()
            HStack {
                Text("Sex (for BMR)").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                Picker("", selection: Binding(get: { store.targets.sexMale }, set: { v in store.updateTargets { $0.sexMale = v } })) {
                    Text("Male").tag(true)
                    Text("Female").tag(false)
                }.labelsHidden().tint(Theme.accentDark)
            }.padding(.horizontal, 16).padding(.vertical, 6)
            Hairline()
            HStack {
                Text("Goal").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                Picker("", selection: Binding(get: { store.targets.goal }, set: { v in store.updateTargets { $0.goal = v } })) {
                    Text("Cut").tag("cut")
                    Text("Maintain").tag("maintain")
                    Text("Bulk").tag("bulk")
                }.labelsHidden().tint(Theme.accentDark)
            }.padding(.horizontal, 16).padding(.vertical, 6)
        }
        .glassList()
    }

    private var prizeCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Name").font(.system(size: 16)).foregroundStyle(Theme.ink).frame(width: 80, alignment: .leading)
                TextField("e.g. Visceral fat, Savings", text: Binding(
                    get: { store.targets.prizeName },
                    set: { v in store.updateTargets { $0.prizeName = v } }))
                    .multilineTextAlignment(.trailing).font(.system(size: 16))
            }.padding(.horizontal, 16).padding(.vertical, 12)
            Hairline()
            HStack {
                Text("Unit").font(.system(size: 16)).foregroundStyle(Theme.ink).frame(width: 80, alignment: .leading)
                TextField("e.g. %, kg, ₹ (optional)", text: Binding(
                    get: { store.targets.prizeUnit },
                    set: { v in store.updateTargets { $0.prizeUnit = v } }))
                    .multilineTextAlignment(.trailing).font(.system(size: 16))
            }.padding(.horizontal, 16).padding(.vertical, 12)
            Hairline()
            StepperRow(label: "Start", value: Self.fmt(store.targets.prizeStart),
                       dec: { store.updateTargets { $0.prizeStart = max(0, $0.prizeStart - 1) } },
                       inc: { store.updateTargets { $0.prizeStart += 1 } })
            Hairline()
            StepperRow(label: "Now", value: Self.fmt(store.targets.prizeCurrent),
                       dec: { store.updateTargets { $0.prizeCurrent = max(0, $0.prizeCurrent - 1) } },
                       inc: { store.updateTargets { $0.prizeCurrent += 1 } })
            Hairline()
            StepperRow(label: "Target", value: Self.fmt(store.targets.prizeTarget),
                       dec: { store.updateTargets { $0.prizeTarget = max(0, $0.prizeTarget - 1) } },
                       inc: { store.updateTargets { $0.prizeTarget += 1 } })
            Hairline()
            ToggleTextRow(label: "Lower is better", on: store.targets.prizeLowerIsBetter) {
                store.updateTargets { $0.prizeLowerIsBetter.toggle() }
            }
        }
        .glassList()
    }

    static func fmt(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d) }
}

// MARK: - Apple Health

struct HealthSettingsPage: View {
    @EnvironmentObject var store: AppStore
    @State private var pdfURL: URL?
    @State private var showPDFShare = false

    var body: some View {
        SettingsSheet(title: "Apple Health") {
            healthSyncCard
            autoNotesCard
        }
        .sheet(isPresented: $showPDFShare) {
            if let pdfURL { ShareSheet(items: [pdfURL]) }
        }
    }

    private var healthSyncCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "heart.fill", colors: [Color(hex: 0xFF5E7A), Color(hex: 0xFB1E4B)])
                Text("Sync with Health").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                ToggleRow(on: store.settings.healthkit) { store.toggleHealthKit() }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Hairline()
            Button {
                pdfURL = store.exportHealthPDF()
                if pdfURL != nil { showPDFShare = true }
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: "doc.richtext", colors: [Color(hex: 0xB0B0B5), Color(hex: 0x6E6E73)])
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Export health report (PDF)").font(.system(size: 16)).foregroundStyle(Theme.ink)
                        Text("Body comp, labs & weekly stats — for your doctor")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    }
                    Spacer()
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14)).foregroundStyle(Theme.accentDark)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .glassList()
    }

    private var autoNotesCard: some View {
        VStack(spacing: 0) {
            ToggleTextRow(label: "Auto notes from imports",
                          sub: "Out-of-range results in an imported report become a finding note on the Health tab — computed on-device from general reference ranges",
                          on: store.settings.autoHealthNotes) {
                store.updateSettings { $0.autoHealthNotes.toggle() }
            }
        }
        .glassList()
        .padding(.top, 12)
    }
}

// MARK: - Hydration

struct HydrationPage: View {
    @EnvironmentObject var hydration: HydrationManager

    var body: some View {
        SettingsSheet(title: "Hydration") {
            VStack(spacing: 0) {
                StepperRow(label: "Daily target", value: "\(hydration.targetMl) ml",
                           dec: { hydration.targetMl = max(500, hydration.targetMl - 250) },
                           inc: { hydration.targetMl += 250 })
                Hairline()
                StepperRow(label: "Glass size", value: "\(hydration.glassMl) ml",
                           dec: { hydration.glassMl = max(50, hydration.glassMl - 50) },
                           inc: { hydration.glassMl += 50 })
                Hairline()
                ToggleTextRow(label: "Reminders", on: hydration.remindersOn) { hydration.remindersOn.toggle() }
                if hydration.remindersOn {
                    Hairline()
                    StepperRow(label: "Every", value: "\(hydration.intervalHours) h",
                               dec: { hydration.intervalHours = max(1, hydration.intervalHours - 1) },
                               inc: { hydration.intervalHours = min(6, hydration.intervalHours + 1) })
                    Hairline()
                    StepperRow(label: "From", value: "\(hydration.startHour):00",
                               dec: { hydration.startHour = max(4, hydration.startHour - 1) },
                               inc: { hydration.startHour = min(hydration.endHour - 1, hydration.startHour + 1) })
                    Hairline()
                    StepperRow(label: "Until", value: "\(hydration.endHour):00",
                               dec: { hydration.endHour = max(hydration.startHour + 1, hydration.endHour - 1) },
                               inc: { hydration.endHour = min(23, hydration.endHour + 1) })
                }
            }
            .glassList()
        }
    }
}

// MARK: - Reminders (smart nudges + wind-down)

struct RemindersPage: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        SettingsSheet(title: "Reminders") {
            SectionHeader(text: "Smart reminders")
            smartRemindersCard
            SectionHeader(text: "Evening wind-down")
            windDownCard
        }
    }

    private var smartRemindersCard: some View {
        VStack(spacing: 0) {
            smartRow("Smart nudges", "Rules over today's data — no AI, nothing leaves the phone",
                     store.settings.smartReminders) { $0.smartReminders.toggle() }
            if store.settings.smartReminders {
                Hairline()
                smartRow("Streak at risk", "Evening ping when the day is still winnable",
                         store.settings.smartStreakRule) { $0.smartStreakRule.toggle() }
                Hairline()
                StepperRow(label: "Evening check", value: "\(store.settings.smartEveningHour):00",
                           dec: { store.updateSmartReminders { $0.smartEveningHour = max(16, $0.smartEveningHour - 1) } },
                           inc: { store.updateSmartReminders { $0.smartEveningHour = min(23, $0.smartEveningHour + 1) } })
                Hairline()
                smartRow("Dinner window", "30 min before tonight's dinner cutoff",
                         store.settings.smartDinnerRule) { $0.smartDinnerRule.toggle() }
                Hairline()
                smartRow("Wind down", "30 min before the recommended bed time",
                         store.settings.smartBedtimeRule) { $0.smartBedtimeRule.toggle() }
                Hairline()
                smartRow("Protein check", "At 6pm if protein is still well short",
                         store.settings.smartProteinRule) { $0.smartProteinRule.toggle() }
            }
        }
        .glassList()
    }

    private func smartRow(_ label: String, _ sub: String, _ on: Bool,
                          _ change: @escaping (inout AppSettings) -> Void) -> some View {
        ToggleTextRow(label: label, sub: sub, on: on) { store.updateSmartReminders(change) }
    }

    private var windDownCard: some View {
        VStack(spacing: 0) {
            ToggleTextRow(label: "Wind-down nudge",
                          sub: "Close today, then name tomorrow's one thing — replaces the plain bedtime nudge",
                          on: store.settings.windDownEnabled) {
                store.updateWindDown { $0.windDownEnabled.toggle() }
            }
            if store.settings.windDownEnabled {
                Hairline()
                // −1 is "auto": 45 minutes before tonight's recommended bedtime, which moves with
                // the sleep plan. Stepping below 0 returns to it.
                StepperRow(label: "Fires at",
                           value: store.settings.windDownHour < 0 ? "Auto" : "\(store.settings.windDownHour):00",
                           dec: { store.updateWindDown { $0.windDownHour = max(-1, $0.windDownHour - 1) } },
                           inc: { store.updateWindDown { $0.windDownHour = min(23, $0.windDownHour + 1) } })
                Text(store.settings.windDownHour < 0 ? "Auto = 45 min before the recommended bedtime." : "")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    .padding(.horizontal, 16).padding(.bottom, store.settings.windDownHour < 0 ? 10 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassList()
    }
}

// MARK: - Prayer times

struct PrayerPage: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var prayer: PrayerManager

    var body: some View {
        SettingsSheet(title: "Prayer times") {
            prayerCard
        }
    }

    private var jumuahModeLabel: String {
        switch prayer.jumuahMode {
        case "on": return "Always"
        case "off": return "Never"
        default: return prayer.userIsMale ? "Automatic · shown" : "Automatic · hidden"
        }
    }

    /// The congregation time is set by the mosque, not by astronomy, so it can only be entered.
    /// Unset means "follow the computed Dhuhr", which is when the Jumu'ah window opens.
    @ViewBuilder private var jumuahTimeRow: some View {
        let base = Calendar.current.startOfDay(for: Date())
        let current = prayer.jumuahMinute >= 0
            ? base.addingTimeInterval(Double(prayer.jumuahMinute) * 60)
            : (prayer.today?[.dhuhr] ?? base.addingTimeInterval(13 * 3600))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Jumu'ah time").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                if prayer.jumuahMinute >= 0 {
                    Button("Clear") { prayer.setJumuahMinute(-1) }
                        .font(.system(size: 13)).foregroundStyle(Theme.accentDark)
                }
                DatePicker("", selection: Binding(
                    get: { current },
                    set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        prayer.setJumuahMinute((c.hour ?? 13) * 60 + (c.minute ?? 0))
                    }), displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Text(prayer.jumuahMinute >= 0
                 ? "Your mosque's khutbah time."
                 : "Following the computed Dhuhr — set your mosque's time if it differs.")
                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private var prayerCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "moon.stars.fill", colors: [Theme.accent, Theme.accentDark])
                VStack(alignment: .leading, spacing: 1) {
                    Text("Islamic prayers").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Text(prayer.placeName.isEmpty ? "Times, Qibla & reminders"
                                                  : "\(prayer.placeName)")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
                Spacer()
                ToggleRow(on: prayer.enabled) { prayer.setEnabled(!prayer.enabled) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if prayer.enabled {
                Hairline()
                Menu {
                    Button("Sunni") { prayer.setBranch("sunni") }
                    Button("Shia (Jafari)") { prayer.setBranch("shia") }
                } label: {
                    pickerLabelRow("School", prayer.branch == "shia" ? "Shia (Jafari)" : "Sunni")
                }
                Hairline()
                Menu {
                    Button("Automatic") { prayer.setJumuahMode("auto") }
                    Button("Always") { prayer.setJumuahMode("on") }
                    Button("Never") { prayer.setJumuahMode("off") }
                } label: {
                    pickerLabelRow("Friday Jumu'ah", jumuahModeLabel)
                }
                if prayer.observesJumuah { Hairline(); jumuahTimeRow }
                if prayer.branch == "sunni" {
                    Hairline()
                    Menu {
                        ForEach(PrayerManager.madhabs, id: \.self) { m in
                            Button(m.capitalized) { prayer.setMadhab(m) }
                        }
                    } label: {
                        pickerLabelRow("Madhab", prayer.madhab.capitalized)
                    }
                    Hairline()
                    Menu {
                        ForEach(CalcMethod.all, id: \.name) { m in
                            Button(m.name) { prayer.setMethod(m) }
                        }
                    } label: {
                        pickerLabelRow("Method", prayer.method.name)
                    }
                }
            }
            if !prayer.statusNote.isEmpty {
                Hairline()
                Text(prayer.statusNote)
                    .font(.system(size: 12)).foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .glassList()
    }
}

// MARK: - Fasting & Ramadan

struct FastingPage: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var fasting: FastingManager
    @EnvironmentObject var ramadan: RamadanManager

    var body: some View {
        SettingsSheet(title: "Fasting") {
            fastingCard
        }
    }

    private var fastingCard: some View {
        VStack(spacing: 0) {
            ToggleTextRow(label: "Track fasting", on: fasting.enabled) {
                fasting.enabled.toggle(); syncFastingModule()
            }
            if fasting.enabled {
                Hairline()
                Text("Fasting window")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 9).padding(.bottom, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FastingManager.protocols, id: \.id) { p in
                            let on = fasting.protocolName == p.id
                            Button { fasting.protocolName = p.id } label: {
                                Text(p.label).font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                                    .padding(.horizontal, 13).padding(.vertical, 8)
                                    .background(Capsule().fill(on ? AnyShapeStyle(Theme.accentDark) : AnyShapeStyle(Theme.surfaceOverlay)))
                                    .overlay(Capsule().strokeBorder(Theme.surfaceStroke.opacity(on ? 0 : 1), lineWidth: 0.5))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 10)
                if fasting.protocolName == "custom" {
                    Hairline()
                    StepperRow(label: "Target hours", value: "\(Int(fasting.targetHours)) h",
                               dec: { fasting.targetHours = max(8, fasting.targetHours - 1) },
                               inc: { fasting.targetHours = min(23, fasting.targetHours + 1) })
                }
            }
            Hairline()
            // Ramadan mode: dates are auto-detected (Umm al-Qura ± a sighting adjustment) and suhoor
            // /iftar come from the computed Fajr/Maghrib — never a hardcoded clock time.
            ToggleTextRow(label: "Ramadan mode", sub: ramadan.statusLine, on: ramadan.mode != .off) {
                ramadan.setMode(ramadan.mode == .off ? .auto : .off)
                syncFastingModule()
            }
            if ramadan.mode != .off {
                Hairline()
                ToggleTextRow(label: "Always on", sub: "Ignore the calendar and keep the mode on",
                              on: ramadan.mode == .on) {
                    ramadan.setMode(ramadan.mode == .on ? .auto : .on)
                    syncFastingModule()
                }
                Hairline()
                StepperRow(label: "Month started", value: ramadan.adjustmentLabel,
                           dec: { ramadan.setDayAdjustment(ramadan.dayAdjustment - 1) },
                           inc: { ramadan.setDayAdjustment(ramadan.dayAdjustment + 1) })
                Hairline()
                ToggleTextRow(label: "Auto start & stop the fast",
                              sub: "Opens at Fajr, closes at Maghrib \u{2014} ending it by hand always wins",
                              on: ramadan.autoFast) { ramadan.setAutoFast(!ramadan.autoFast) }
                Hairline()
                StepperRow(label: "Suhoor warning", value: "\(ramadan.suhoorLeadMinutes) min",
                           dec: { ramadan.setSuhoorLead(ramadan.suhoorLeadMinutes - 5) },
                           inc: { ramadan.setSuhoorLead(ramadan.suhoorLeadMinutes + 5) })
                Hairline()
                ToggleTextRow(label: "Nudge 10 min before iftar", on: ramadan.preIftarReminder) {
                    ramadan.setPreIftarReminder(!ramadan.preIftarReminder)
                }
            }
        }
        .glassList()
    }

    /// Show the Today fasting module whenever fasting or Ramadan mode is on.
    private func syncFastingModule() {
        let want = fasting.enabled || ramadan.mode != .off
        if store.modules.enabled("fasting") != want {
            store.updateModules { $0.setEnabled("fasting", want) }
        }
    }
}

// MARK: - Calendar & Reminders

struct CalendarPage: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var calendar: CalendarManager

    var body: some View {
        SettingsSheet(title: "Calendar & Reminders") {
            calendarCard
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 0) {
            if !calendar.calAuthorized {
                Button { Task { await calendar.requestAccess() } } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "calendar.badge.plus", colors: [Color(hex: 0x6FA8FF), Color(hex: 0x3B6CF0)])
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Connect Calendar & Reminders").font(.system(size: 16)).foregroundStyle(Theme.ink)
                            Text("Plan around your real schedule").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                if !calendar.statusNote.isEmpty {
                    Hairline()
                    Text(calendar.statusNote).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 9)
                }
            } else {
                HStack(spacing: 12) {
                    IconTile(symbol: "calendar", colors: [Color(hex: 0x6FA8FF), Color(hex: 0x3B6CF0)])
                    Text("Calendar connected").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sage)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Hairline()
                ToggleTextRow(label: "Add sessions to Calendar", on: store.settings.calendarSync) {
                    store.updateSettings { $0.calendarSync.toggle() }
                }
                Hairline()
                ToggleTextRow(label: "Create Reminders",
                              sub: calendar.remindersAuthorized ? "For sessions & event prep" : "Reminders access is off",
                              on: store.settings.remindersSync) {
                    store.updateSettings { $0.remindersSync.toggle() }
                }
            }
        }
        .glassList()
    }
}

// MARK: - Privacy (app lock)

struct PrivacyPage: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var lock: AppLock
    @State private var lockNote = ""

    var body: some View {
        SettingsSheet(title: "Privacy") {
            privacyCard
            Text("The lock covers this app only — widgets, the watch app and notifications are governed by iOS.")
                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                .padding(.horizontal, 16).padding(.top, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var privacyCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "lock.fill", colors: [Theme.accent, Theme.accentDark])
                VStack(alignment: .leading, spacing: 1) {
                    Text("Require \(AppLock.biometryLabel)").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Text("Lock Win the Day when you leave it").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
                Spacer()
                ToggleRow(on: store.settings.appLockEnabled) { toggleAppLock() }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if store.settings.appLockEnabled {
                Hairline()
                Menu {
                    ForEach(AppSettings.appLockGraceOptions, id: \.self) { m in
                        Button(Self.graceLabel(m)) { store.updateSettings { $0.appLockGraceMinutes = m } }
                    }
                } label: {
                    pickerLabelRow("Ask again after", Self.graceLabel(store.settings.appLockGraceMinutes))
                }
            }
            if !lockNote.isEmpty {
                Hairline()
                Text(lockNote)
                    .font(.system(size: 12)).foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 9)
            }
        }
        .glassList()
        .onAppear { lockNote = lock.unavailableNote }
    }

    /// Flipping the toggle on authenticates once first — proving it works before we can lock the
    /// user out of their own data. A refusal (no device passcode) explains itself and stays off.
    private func toggleAppLock() {
        if store.settings.appLockEnabled {
            store.updateSettings { $0.appLockEnabled = false }
            lock.syncEnabled(false)
            lockNote = ""
            return
        }
        Task {
            if let why = await lock.authenticate(reason: "Turn on app lock for Win the Day") {
                lockNote = why
            } else {
                lockNote = ""
                store.updateSettings { $0.appLockEnabled = true }
                lock.syncEnabled(true)
            }
        }
    }

    private static func graceLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Immediately"
        case 1: return "1 minute"
        default: return "\(minutes) minutes"
        }
    }
}

// MARK: - Backup & data

struct BackupPage: View {
    @EnvironmentObject var store: AppStore

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var confirmReset = false

    var body: some View {
        SettingsSheet(title: "Backup & data") {
            dataCard
            if !store.importMessage.isEmpty {
                Text(store.importMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(store.importMessage.hasPrefix("Restored") ? Theme.sage : Theme.coral)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.top, 10)
            }
            Text(autoBackupNote)
                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 8)
        }
        .fileExporter(isPresented: $showExporter,
                      document: exportURL.map { JSONDocument(url: $0) },
                      contentType: .json,
                      defaultFilename: "win-the-day-\(AppStore.dateString(Date()))") { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { store.prepareImport(from: url) }
        }
        // Confirm before anything is overwritten. By now the archive is parsed and validated, but
        // nothing has been written to disk.
        .sheet(isPresented: Binding(get: { store.pendingSummary != nil },
                                    set: { if !$0 { store.cancelPendingRestore() } })) {
            if let summary = store.pendingSummary {
                RestoreConfirmSheet(summary: summary,
                                    onConfirm: { store.commitPendingRestore() },
                                    onCancel: { store.cancelPendingRestore() })
            }
        }
        .alert("Restored", isPresented: $store.restoreNeedsRelaunch) {
            Button("OK") {}
        } message: {
            Text("Your backup is in. Close and reopen Win the Day so every screen picks up the restored data.")
        }
        .confirmationDialog("Reset all data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) { store.reset() }
            Button("Keep my data", role: .cancel) {}
        } message: {
            Text("This clears every entry on this device. Export a backup first if you\u{2019}re unsure.")
        }
    }

    private var dataCard: some View {
        VStack(spacing: 0) {
            Button {
                exportURL = store.exportJSON()
                if exportURL != nil { showExporter = true }
            } label: {
                HStack {
                    IconTile(symbol: "icloud.and.arrow.up.fill", colors: [Color(hex: 0x6FA8FF), Color(hex: 0x3B6CF0)])
                    Text("Back up to iCloud Drive / Files").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            Hairline()
            Button { showImporter = true } label: {
                HStack {
                    IconTile(symbol: "icloud.and.arrow.down.fill", colors: [Color(hex: 0x7AD7B0), Color(hex: 0x16A06A)])
                    Text("Restore from a backup").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.quaternaryInk)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            Hairline()
            Button { confirmReset = true } label: {
                HStack {
                    Text("Reset all data").font(.system(size: 16)).foregroundStyle(Theme.coral)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
        .glassList()
    }

    private var autoBackupNote: String {
        let base = "A backup holds everything on this device — entries, habits, targets, settings, coach chats, prayer/hydration/fasting setup, library, labs, body comp & photos. Your API keys are not included: they stay in the Keychain, so you'll re-enter them after a restore.\n\nAuto-backup writes to the Files app (On My iPhone → Win the Day) every time you leave the app, and it rides along in your iCloud device backup. Tap Back up to also drop a copy in iCloud Drive."
        if let d = store.lastAutoBackup {
            let f = DateFormatter(); f.dateFormat = "d MMM, h:mm a"
            return "Last auto-backup: \(f.string(from: d)).\n\n" + base
        }
        return base
    }
}

// MARK: - Restore confirmation

/// What's actually inside the chosen backup, shown before a single byte is overwritten.
struct RestoreConfirmSheet: View {
    let summary: BackupSummary
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    SectionHeader(text: "This backup")
                    VStack(spacing: 0) {
                        row("Made", value: madeText)
                        Hairline()
                        row("Days logged", value: "\(summary.days)")
                        Hairline()
                        row("Habits", value: "\(summary.habits)")
                        Hairline()
                        row("Photos", value: "\(summary.photos)")
                        if summary.isFullArchive {
                            Hairline()
                            row("Coach chats", value: "\(summary.chats)")
                        }
                    }
                    .glassList()

                    Text(footnote)
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 10)

                    Button {
                        onConfirm()
                        dismiss()
                    } label: {
                        Text("Replace my data")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.coral))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.top, 18)

                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Text("Keep what's on this phone")
                            .font(.system(size: 16)).foregroundStyle(Theme.accentDark)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(WarmBackground())
            .navigationTitle("Restore backup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).font(.system(size: 16)).foregroundStyle(Theme.tertiaryInk)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var madeText: String {
        guard let d = summary.created else { return "Unknown" }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy, h:mm a"
        return f.string(from: d)
    }

    private var footnote: String {
        let keys = "API keys aren\u{2019}t in backups — they stay in the Keychain, so re-enter yours in Settings afterwards."
        if summary.isFullArchive {
            return "Everything on this phone is replaced with the backup: entries, habits, targets, settings, coach chats and your prayer/hydration/fasting setup. \(keys)"
        }
        return "This is an older backup — it only carries entries, habits and photos, so your current settings are left alone. \(keys)"
    }
}

// MARK: - JSON document for export

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(url: URL) { data = (try? Data(contentsOf: url)) ?? Data() }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
