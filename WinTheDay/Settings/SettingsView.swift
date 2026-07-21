import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var prayer: PrayerManager
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var fasting: FastingManager
    @EnvironmentObject var calendar: CalendarManager
    @Binding var confirmReset: Bool

    @State private var providersOpen = false
    @State private var apiKey = ""
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showModulesEditor = false
    @State private var showRingEditor = false
    @State private var exportURL: URL?
    @State private var pdfURL: URL?
    @State private var showPDFShare = false
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, running, ok(String), failed(String)
    }

    private var provider: AIProvider { Providers.provider(store.settings.provider) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle(sub: nil, title: "Settings")

            SectionHeader(text: "Intelligence")
            intelligenceCard
            Text(provider.foot)
                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                .padding(.horizontal, 16).padding(.top, 7)
                .frame(maxWidth: .infinity, alignment: .leading)

            if provider.needsKey { apiKeyCard }
            if provider.id == "ollama" { ollamaHostCard }
            if provider.allowsCustomModel && store.settings.model == "custom" { customModelCard }
            testConnectionCard

            SectionHeader(text: "Hydration")
            hydrationCard

            SectionHeader(text: "Prayer times")
            prayerCard

            SectionHeader(text: "Fasting")
            fastingCard

            SectionHeader(text: "Calendar & Reminders")
            calendarCard

            SectionHeader(text: "Apple Health")
            healthSyncCard
            SectionHeader(text: "Daily targets")
            targetsCard

            SectionHeader(text: "Eating score profile")
            eatingProfileCard

            SectionHeader(text: "Rings")
            Button { showRingEditor = true } label: {
                HStack {
                    Image(systemName: "circle.grid.2x2").foregroundStyle(Theme.accentDark)
                    Text("Manage rings").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
                }
                .padding(.horizontal, 16).padding(.vertical, 13).glassList()
            }

            SectionHeader(text: "The prize")
            prizeCard

            SectionHeader(text: "Pillar names")
            pillarNamesCard

            SectionHeader(text: "Module colors")
            moduleColorsCard

            SectionHeader(text: "Today layout")
            Button { showModulesEditor = true } label: {
                HStack {
                    Image(systemName: "arrow.up.arrow.down").foregroundStyle(Theme.accentDark)
                    Text("Reorder modules").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
                }
                .padding(.horizontal, 16).padding(.vertical, 13).glassList()
            }
            .buttonStyle(.plain).padding(.bottom, 10)
            modulesCard
            SectionHeader(text: "Setup")
            Button { store.replayOnboarding() } label: {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accentDark)
                    Text("Run setup again").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
                }
                .padding(.horizontal, 16).padding(.vertical, 13).glassList()
            }
            .buttonStyle(.plain)

            SectionHeader(text: "Backup & data")
            dataCard
            if !store.importMessage.isEmpty {
                Text(store.importMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(store.importMessage.hasPrefix("Restored") ? Color(hex: 0x3DA876) : Color(hex: 0xD86B4A))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.top, 10)
            }
            Text(autoBackupNote)
                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 8)

            Text("Win the Day · v1.0\nNo accounts. No backend. Your data, your device.")
                .font(.system(size: 12)).foregroundStyle(Color(white: 0.27).opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.top, 22)
        }
        .onAppear { apiKey = Keychain.get(store.settings.provider) }
        .sheet(isPresented: $showModulesEditor) { ModulesEditorView() }
        .sheet(isPresented: $showRingEditor) { RingEditorView() }
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
    }

    // MARK: - Intelligence

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
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
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
        switch store.settings.provider {
        case "apple": return [Color(hex: 0xB0B0B5), Color(hex: 0x6E6E73)]
        case "openai": return [Color(hex: 0x3FC8A8), Color(hex: 0x10A37F)]
        case "gemini": return [Color(hex: 0x6FA8FF), Color(hex: 0x3B6CF0)]
        case "openrouter": return [Color(hex: 0x8E7CF0), Color(hex: 0x5B45D6)]
        case "deepseek": return [Color(hex: 0x5B8DEF), Color(hex: 0x2E5BC8)]
        case "ollama": return [Color(hex: 0x9AA0A6), Color(hex: 0x3C4043)]
        case "ollamacloud": return [Color(hex: 0x7D8590), Color(hex: 0x1F2328)]
        default: return [Color(hex: 0x6470A6), Color(hex: 0x3B4A7C)]
        }
    }

    private func selectProvider(_ id: String) {
        store.setProvider(id)
        withAnimation { providersOpen = false }
        apiKey = Keychain.get(id)
        testState = .idle
    }

    // MARK: - API key (cloud providers)

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
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color(hex: 0xD86B4A))
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
                    .font(.system(size: 12)).foregroundStyle(Color(hex: 0x3B4A7C))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
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

    // MARK: - Hydration

    private var hydrationCard: some View {
        VStack(spacing: 0) {
            stepperRow("Daily target", value: "\(hydration.targetMl) ml",
                       dec: { hydration.targetMl = max(500, hydration.targetMl - 250) },
                       inc: { hydration.targetMl += 250 })
            Hairline()
            stepperRow("Glass size", value: "\(hydration.glassMl) ml",
                       dec: { hydration.glassMl = max(50, hydration.glassMl - 50) },
                       inc: { hydration.glassMl += 50 })
            Hairline()
            HStack {
                Text("Reminders").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                ToggleRow(on: hydration.remindersOn) { hydration.remindersOn.toggle() }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if hydration.remindersOn {
                Hairline()
                stepperRow("Every", value: "\(hydration.intervalHours) h",
                           dec: { hydration.intervalHours = max(1, hydration.intervalHours - 1) },
                           inc: { hydration.intervalHours = min(6, hydration.intervalHours + 1) })
                Hairline()
                stepperRow("From", value: "\(hydration.startHour):00",
                           dec: { hydration.startHour = max(4, hydration.startHour - 1) },
                           inc: { hydration.startHour = min(hydration.endHour - 1, hydration.startHour + 1) })
                Hairline()
                stepperRow("Until", value: "\(hydration.endHour):00",
                           dec: { hydration.endHour = max(hydration.startHour + 1, hydration.endHour - 1) },
                           inc: { hydration.endHour = min(23, hydration.endHour + 1) })
            }
        }
        .glassList()
    }

    private func stepperRow(_ label: String, value: String, dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).font(.system(size: 16)).foregroundStyle(Theme.tertiaryInk).frame(minWidth: 64, alignment: .trailing)
            HStack(spacing: 0) {
                Button(action: dec) { stepIcon("minus") }
                Divider().frame(height: 22)
                Button(action: inc) { stepIcon("plus") }
            }
            .background(Capsule().fill(Color.white.opacity(0.5)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func stepIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accentDark)
            .frame(width: 38, height: 32)
    }

    private func pickerLabel(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).font(.system(size: 16)).foregroundStyle(Theme.tertiaryInk)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(Color(white: 0.27).opacity(0.3))
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    // MARK: - Personalize (pillar names + module colors)

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

    private let colorableModules = ["rings", "coach", "weather", "prayer", "fasting", "sleep", "health", "meals", "hydration",
                                    "quickLog", "habits", "score", "workStudy", "training", "photos"]

    private var moduleColorsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(colorableModules.enumerated()), id: \.offset) { idx, key in
                HStack {
                    Text(store.modules.label(key)).font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { store.moduleColor(key) },
                        set: { c in store.updatePersonal { $0.moduleColors[key] = Self.hex(of: c) } }))
                        .labelsHidden()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                if idx < colorableModules.count - 1 { Hairline() }
            }
        }
        .glassList()
    }

    private static func hex(of color: Color) -> UInt {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt(max(0, r) * 255) << 16) | (UInt(max(0, g) * 255) << 8) | UInt(max(0, b) * 255)
    }

    // MARK: - Calendar & Reminders

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
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
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
                HStack {
                    Text("Add sessions to Calendar").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Spacer()
                    ToggleRow(on: store.settings.calendarSync) { store.updateSettings { $0.calendarSync.toggle() } }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Hairline()
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Create Reminders").font(.system(size: 16)).foregroundStyle(Theme.ink)
                        Text(calendar.remindersAuthorized ? "For sessions & event prep" : "Reminders access is off")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                    }
                    Spacer()
                    ToggleRow(on: store.settings.remindersSync) { store.updateSettings { $0.remindersSync.toggle() } }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .glassList()
    }

    // MARK: - Fasting

    private var fastingCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Track fasting").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                ToggleRow(on: fasting.enabled) { fasting.enabled.toggle(); syncFastingModule() }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
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
                                    .foregroundStyle(on ? .white : Theme.ink)
                                    .padding(.horizontal, 13).padding(.vertical, 8)
                                    .background(Capsule().fill(on ? AnyShapeStyle(Theme.accentDark) : AnyShapeStyle(Color.white.opacity(0.55))))
                                    .overlay(Capsule().strokeBorder(.white.opacity(on ? 0 : 0.6), lineWidth: 0.5))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 10)
                if fasting.protocolName == "custom" {
                    Hairline()
                    stepperRow("Target hours", value: "\(Int(fasting.targetHours)) h",
                               dec: { fasting.targetHours = max(8, fasting.targetHours - 1) },
                               inc: { fasting.targetHours = min(23, fasting.targetHours + 1) })
                }
            }
            Hairline()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ramadan mode").font(.system(size: 16)).foregroundStyle(Theme.ink)
                    Text("Suhoor & iftar reminders from your prayer times")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
                Spacer()
                ToggleRow(on: prayer.ramadanMode) { prayer.setRamadan(!prayer.ramadanMode); syncFastingModule() }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .glassList()
    }

    /// Show the Today fasting module whenever fasting or Ramadan mode is on.
    private func syncFastingModule() {
        let want = fasting.enabled || prayer.ramadanMode
        if store.modules.enabled("fasting") != want {
            store.updateModules { $0.setEnabled("fasting", want) }
        }
    }

    // MARK: - Prayers

    private var prayerCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "moon.stars.fill", colors: [Color(hex: 0x6470A6), Color(hex: 0x3B4A7C)])
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
                    pickerLabel("School", prayer.branch == "shia" ? "Shia (Jafari)" : "Sunni")
                }
                if prayer.branch == "sunni" {
                    Hairline()
                    Menu {
                        ForEach(PrayerManager.madhabs, id: \.self) { m in
                            Button(m.capitalized) { prayer.setMadhab(m) }
                        }
                    } label: {
                        pickerLabel("Madhab", prayer.madhab.capitalized)
                    }
                    Hairline()
                    Menu {
                        ForEach(CalcMethod.all, id: \.name) { m in
                            Button(m.name) { prayer.setMethod(m) }
                        }
                    } label: {
                        pickerLabel("Method", prayer.method.name)
                    }
                }
            }
            if !prayer.statusNote.isEmpty {
                Hairline()
                Text(prayer.statusNote)
                    .font(.system(size: 12)).foregroundStyle(Color(hex: 0xD86B4A))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .glassList()
    }

    // MARK: - Health sync

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
        .sheet(isPresented: $showPDFShare) {
            if let pdfURL { ShareSheet(items: [pdfURL]) }
        }
    }

    // MARK: - Targets

    private var targetsCard: some View {
        VStack(spacing: 0) {
            stepperRow("Calories", value: "\(Int(store.targets.calories)) kcal",
                       dec: { store.updateTargets { $0.calories = max(800, $0.calories - 50) } },
                       inc: { store.updateTargets { $0.calories += 50 } })
            Hairline()
            stepperRow("Protein", value: "\(Int(store.targets.protein)) g",
                       dec: { store.updateTargets { $0.protein = max(40, $0.protein - 5) } },
                       inc: { store.updateTargets { $0.protein += 5 } })
            Hairline()
            stepperRow("Steps", value: "\(Int(store.targets.steps))",
                       dec: { store.updateTargets { $0.steps = max(1000, $0.steps - 500) } },
                       inc: { store.updateTargets { $0.steps += 500 } })
        }
        .glassList()
    }

    // MARK: - Eating-score profile (BMR/TDEE inputs — drives the Eating ring & weekly projection)

    private var eatingProfileCard: some View {
        VStack(spacing: 0) {
            stepperRow("Age", value: "\(Int(store.targets.ageYears))",
                       dec: { store.updateTargets { $0.ageYears = max(13, $0.ageYears - 1) } },
                       inc: { store.updateTargets { $0.ageYears += 1 } })
            Hairline()
            stepperRow("Height", value: "\(Int(store.targets.heightCm)) cm",
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

    // MARK: - The prize (personal priority metric)

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
            stepperRow("Start", value: fmt(store.targets.prizeStart),
                       dec: { store.updateTargets { $0.prizeStart = max(0, $0.prizeStart - 1) } },
                       inc: { store.updateTargets { $0.prizeStart += 1 } })
            Hairline()
            stepperRow("Now", value: fmt(store.targets.prizeCurrent),
                       dec: { store.updateTargets { $0.prizeCurrent = max(0, $0.prizeCurrent - 1) } },
                       inc: { store.updateTargets { $0.prizeCurrent += 1 } })
            Hairline()
            stepperRow("Target", value: fmt(store.targets.prizeTarget),
                       dec: { store.updateTargets { $0.prizeTarget = max(0, $0.prizeTarget - 1) } },
                       inc: { store.updateTargets { $0.prizeTarget += 1 } })
            Hairline()
            HStack {
                Text("Lower is better").font(.system(size: 16)).foregroundStyle(Theme.ink)
                Spacer()
                ToggleRow(on: store.targets.prizeLowerIsBetter) {
                    store.updateTargets { $0.prizeLowerIsBetter.toggle() }
                }
            }.padding(.horizontal, 16).padding(.vertical, 11)
        }
        .glassList()
    }

    // MARK: - Today modules

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

    private func fmt(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d) }

    private var autoBackupNote: String {
        let base = "A backup holds everything on this device — entries, habits, targets, settings, coach chats, prayer/hydration/fasting setup, library, labs, body comp & photos. Your API keys are not included: they stay in the Keychain, so you'll re-enter them after a restore.\n\nAuto-backup writes to the Files app (On My iPhone → Win the Day) every time you leave the app, and it rides along in your iCloud device backup. Tap Back up to also drop a copy in iCloud Drive."
        if let d = store.lastAutoBackup {
            let f = DateFormatter(); f.dateFormat = "d MMM, h:mm a"
            return "Last auto-backup: \(f.string(from: d)).\n\n" + base
        }
        return base
    }

    // MARK: - Data

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
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
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
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.27).opacity(0.3))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            Hairline()
            Button { confirmReset = true } label: {
                HStack {
                    Text("Reset all data").font(.system(size: 16)).foregroundStyle(Color(hex: 0xD86B4A))
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
        .glassList()
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
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xD86B4A)))
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
