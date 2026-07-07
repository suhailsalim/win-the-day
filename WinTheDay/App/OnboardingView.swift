import SwiftUI

/// Adaptive first-run setup — pages shown depend on the life areas you pick.
struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var health: HealthManager
    @EnvironmentObject var prayer: PrayerManager
    @EnvironmentObject var hydration: HydrationManager
    @EnvironmentObject var fasting: FastingManager

    enum Step { case welcome, areas, faith, work, targets, prize, intelligence, permissions }

    @State private var index = 0
    @State private var areas: Set<Pillar> = [.health, .spirituality]
    @State private var faith = "islam"            // islam / other / none
    @State private var spiritualityName = ""
    @State private var weight = ""
    @State private var prizeNow = ""
    @State private var apiKey = ""
    @State private var trackFasting = false
    @State private var addCountdown = false
    @State private var countdownName = ""
    @State private var countdownDate = Date()

    private var steps: [Step] {
        var s: [Step] = [.welcome, .areas]
        if areas.contains(.spirituality) { s.append(.faith) }
        if areas.contains(.work) { s.append(.work) }
        s.append(contentsOf: [.targets, .prize, .intelligence, .permissions])
        return s
    }
    private var current: Step { steps[min(index, steps.count - 1)] }
    private var isLast: Bool { min(index, steps.count - 1) == steps.count - 1 }

    var body: some View {
        ZStack {
            WarmBackground()
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Capsule().fill(i <= index ? Theme.accentDark : Color(white: 0.27).opacity(0.18))
                            .frame(width: i == index ? 20 : 6, height: 6)
                    }
                }
                .padding(.top, 20)
                .animation(.easeInOut, value: steps.count)

                ScrollView {
                    VStack { content }.frame(maxWidth: .infinity).padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)

                Button(isLast ? "Start winning days" : "Continue") {
                    if isLast { finish() } else { withAnimation { index = min(index + 1, steps.count - 1) } }
                }
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [Color(hex: 0x6470A6), Color(hex: 0x3B4A7C)], startPoint: .top, endPoint: .bottom)))
                .padding(.horizontal, 22).padding(.bottom, 6)

                if index > 0 {
                    Button("Back") { withAnimation { index = max(0, index - 1) } }
                        .font(.system(size: 14)).foregroundStyle(Theme.tertiaryInk).padding(.bottom, 10)
                } else { Color.clear.frame(height: 26) }
            }
        }
        .tint(Theme.accentDark)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } } }
    }

    @ViewBuilder private var content: some View {
        switch current {
        case .welcome: welcome
        case .areas: areasStep
        case .faith: faithStep
        case .work: workStep
        case .targets: targetsStep
        case .prize: prizeStep
        case .intelligence: intelligenceStep
        case .permissions: permissionsStep
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        page("🌅", "Win the Day", "Build your own daily scoreboard — health, faith, work or study, whatever matters to you. Win most of your non-negotiables, win the day. Let's tailor it to you.") { EmptyView() }
    }

    private var areasStep: some View {
        page("🧭", "What do you want to win at?", "Pick the areas to track. You can change everything later in Settings.") {
            VStack(spacing: 10) {
                ForEach(Pillar.allCases) { p in
                    let on = areas.contains(p)
                    Button {
                        if on { areas.remove(p) } else { areas.insert(p) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p.icon).foregroundStyle(Color(hex: p.hex)).frame(width: 24)
                            Text(p.title).font(.system(size: 16)).foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(on ? Theme.sage : Color(white: 0.47).opacity(0.3))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(on ? 0.7 : 0.4)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var faithStep: some View {
        page("🕌", "Your faith & practice", "Make this pillar yours. Islam unlocks prayer times, Qibla and reminders. Other faiths or none just use your own habits.") {
            VStack(spacing: 12) {
                segmented(["islam": "Islam", "other": "Other faith", "none": "Just habits"], selection: $faith)
                if faith == "islam" {
                    segmented(["sunni": "Sunni", "shia": "Shia"], selection: Binding(
                        get: { prayer.branch }, set: { prayer.setBranch($0) }))
                    if prayer.branch == "sunni" {
                        menuRow("Madhab", prayer.madhab.capitalized) {
                            ForEach(PrayerManager.madhabs, id: \.self) { m in Button(m.capitalized) { prayer.setMadhab(m) } }
                        }
                        menuRow("Method", prayer.method.name) {
                            ForEach(CalcMethod.all, id: \.name) { m in Button(m.name) { prayer.setMethod(m) } }
                        }
                    }
                    Toggle(isOn: $trackFasting) {
                        Text("Track fasting (Ramadan & intermittent)").font(.system(size: 15)).foregroundStyle(Theme.ink)
                    }.tint(Theme.sage).padding(.horizontal, 4)
                } else {
                    field("Pillar name", text: $spiritualityName, placeholder: "Faith / Spirituality / Dharma…")
                    Text("Add your own practices (prayer, meditation, gratitude…) as habits later.")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                }
            }
        }
    }

    private var workStep: some View {
        page("📚", "Work or study?", "This shapes the labels — sessions, hours, items and countdowns.") {
            VStack(spacing: 12) {
                segmented(["study": "Study", "work": "Work"], selection: Binding(
                    get: { store.targets.workMode }, set: { v in store.updateTargets { $0.workMode = v } }))
                Toggle(isOn: $addCountdown) {
                    Text("Add a \(store.workVocab.countdown.lowercased()) countdown").font(.system(size: 15)).foregroundStyle(Theme.ink)
                }.tint(Theme.sage).padding(.horizontal, 4)
                if addCountdown {
                    field("Name", text: $countdownName, placeholder: store.targets.workMode == "work" ? "Q3 launch" : "NEET PG")
                    DatePicker("Date", selection: $countdownDate, in: Date()..., displayedComponents: .date)
                        .tint(Theme.accentDark).font(.system(size: 15))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
                }
            }
        }
    }

    private var targetsStep: some View {
        page("🎯", "Your daily targets", "Tune these any time in Settings.") {
            VStack(spacing: 12) {
                if areas.contains(.health) {
                    stepper("Calories", "\(Int(store.targets.calories)) kcal",
                            { store.updateTargets { $0.calories = max(800, $0.calories - 50) } },
                            { store.updateTargets { $0.calories += 50 } })
                    stepper("Protein", "\(Int(store.targets.protein)) g",
                            { store.updateTargets { $0.protein = max(40, $0.protein - 5) } },
                            { store.updateTargets { $0.protein += 5 } })
                    stepper("Steps", "\(Int(store.targets.steps))",
                            { store.updateTargets { $0.steps = max(1000, $0.steps - 500) } },
                            { store.updateTargets { $0.steps += 500 } })
                    stepper("Water", "\(hydration.targetMl) ml",
                            { hydration.targetMl = max(500, hydration.targetMl - 250) },
                            { hydration.targetMl += 250 })
                }
                if areas.contains(.work) {
                    stepper("\(store.workVocab.hours)", "\(Int(store.targets.studyHours)) h",
                            { store.updateTargets { $0.studyHours = max(1, $0.studyHours - 1) } },
                            { store.updateTargets { $0.studyHours += 1 } })
                }
                if !areas.contains(.health) && !areas.contains(.work) {
                    Text("No numeric targets needed for your areas — you're set.")
                        .font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
    }

    private var prizeStep: some View {
        page("🏆", "Your one prize", "The single metric that matters most — visceral fat, body fat, savings, anything. It headlines your Trends.") {
            VStack(spacing: 12) {
                field("Name", text: Binding(get: { store.targets.prizeName }, set: { v in store.updateTargets { $0.prizeName = v } }),
                      placeholder: "Visceral fat")
                field("Unit (optional)", text: Binding(get: { store.targets.prizeUnit }, set: { v in store.updateTargets { $0.prizeUnit = v } }),
                      placeholder: "%, kg, ₹…")
                field("Where it is now", text: $prizeNow, placeholder: "current value", keyboard: .decimalPad)
                stepper("Target", fmt(store.targets.prizeTarget),
                        { store.updateTargets { $0.prizeTarget = max(0, $0.prizeTarget - 1) } },
                        { store.updateTargets { $0.prizeTarget += 1 } })
                Toggle(isOn: Binding(get: { store.targets.prizeLowerIsBetter }, set: { v in store.updateTargets { $0.prizeLowerIsBetter = v } })) {
                    Text("Lower is better").font(.system(size: 15)).foregroundStyle(Theme.ink)
                }.tint(Theme.sage).padding(.horizontal, 4)
            }
        }
    }

    private var intelligenceStep: some View {
        page("✨", "Pick your AI", "Powers meal estimates, label scanning and your coach. Apple Intelligence is on-device & free; cloud providers need a key.") {
            VStack(spacing: 10) {
                ForEach(Providers.all) { p in
                    Button { store.setProvider(p.id); apiKey = Keychain.get(p.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 15.5)).foregroundStyle(Theme.ink)
                                Text(p.tag).font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
                            }
                            Spacer()
                            if p.id == store.settings.provider { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accentDark) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(p.id == store.settings.provider ? 0.7 : 0.4)))
                    }.buttonStyle(.plain)
                }
                if Providers.provider(store.settings.provider).needsKey {
                    SecureField("Paste API key", text: $apiKey)
                        .font(.system(size: 15)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.6)))
                        .onChange(of: apiKey) { _, v in Keychain.set(v, for: store.settings.provider) }
                }
            }
        }
    }

    private var permissionsStep: some View {
        page("🔐", "A few permissions", permissionsBlurb) { EmptyView() }
    }

    private var permissionsBlurb: String {
        var bits = ["Notifications (reminders)"]
        if areas.contains(.health) { bits.insert("Apple Health (steps, weight)", at: 0) }
        if areas.contains(.spirituality) && faith == "islam" { bits.append("Location (prayer times)") }
        return "Next, iOS will ask for: " + bits.joined(separator: ", ") + ". Allow what you're comfortable with — you can change these later."
    }

    // MARK: - Building blocks

    private func page<C: View>(_ emoji: String, _ title: String, _ subtitle: String, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 14) {
            Text(emoji).font(.system(size: 54)).padding(.top, 26)
            Text(title).font(.system(size: 27, weight: .bold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            content().padding(.horizontal, 22).padding(.top, 8)
        }
    }

    private func segmented(_ options: [String: String], selection: Binding<String>) -> some View {
        // Preserve a stable order for known keys.
        let order = ["islam", "other", "none", "sunni", "shia", "study", "work"]
        let keys = order.filter { options[$0] != nil }
        return HStack(spacing: 0) {
            ForEach(keys, id: \.self) { key in
                let on = selection.wrappedValue == key
                Button { selection.wrappedValue = key } label: {
                    Text(options[key] ?? key).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? .white : Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(on ? Theme.accentDark : Color.clear)
                }.buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.5)).clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
    }

    private func menuRow<C: View>(_ label: String, _ value: String, @ViewBuilder menu: () -> C) -> some View {
        Menu { menu() } label: {
            HStack {
                Text(label).font(.system(size: 15)).foregroundStyle(Theme.ink)
                Spacer()
                Text(value).font(.system(size: 15)).foregroundStyle(Theme.tertiaryInk)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Color(white: 0.27).opacity(0.3))
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String = "", keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(Theme.ink)
            Spacer()
            TextField(placeholder, text: text).keyboardType(keyboard).multilineTextAlignment(.trailing)
                .font(.system(size: 15)).foregroundStyle(Theme.ink).frame(maxWidth: 160)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
    }

    private func stepper(_ label: String, _ value: String, _ dec: @escaping () -> Void, _ inc: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.tertiaryInk)
            HStack(spacing: 0) {
                Button(action: dec) { Image(systemName: "minus").frame(width: 36, height: 30) }
                Button(action: inc) { Image(systemName: "plus").frame(width: 36, height: 30) }
            }
            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accentDark)
            .background(Capsule().fill(Color.white.opacity(0.6)))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
    }

    private func fmt(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d) }

    // MARK: - Finish

    private func finish() {
        store.applyOnboarding(areas: areas, faith: faith, spiritualityName: spiritualityName)
        let muslim = areas.contains(.spirituality) && faith == "islam"
        prayer.setEnabled(muslim)
        let fastOn = muslim && trackFasting
        fasting.enabled = fastOn
        prayer.setRamadan(fastOn)
        store.updateModules { $0.setEnabled("fasting", fastOn) }

        if let w = Double(weight), w > 0 { store.mutate { $0.weight = String(format: "%.1f", w) } }
        if let v = Double(prizeNow), v > 0 { store.updateTargets { $0.prizeStart = v; $0.prizeCurrent = v } }
        if areas.contains(.work) && addCountdown {
            let nm = countdownName.trimmingCharacters(in: .whitespaces)
            if !nm.isEmpty { store.addCountdown(name: nm, date: countdownDate, kind: store.targets.workMode) }
        }
        store.completeOnboarding()
        if areas.contains(.health) { Task { await health.requestAuthorization() } }
        hydration.start()
    }
}
