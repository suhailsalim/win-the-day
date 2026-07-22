import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Upload an InBody or lab report (camera / photo / PDF / text) → AI parse → save to Apple Health.
struct ImportReportView: View {
    enum Mode: Identifiable { case bodyComp, labs
        var id: String { self == .bodyComp ? "body" : "labs" }
        var title: String { self == .bodyComp ? "InBody report" : "Health checkup" }
        var blurb: String {
            self == .bodyComp
            ? "Snap or upload your InBody sheet. I\u{2019}ll read weight, body fat, lean & skeletal muscle, BMI and visceral fat — and save the supported ones to Apple Health."
            : "Snap or upload a lab / checkup report. I\u{2019}ll read every result; values Apple Health supports (glucose, SpO₂, temperature…) are saved there, the rest are kept in the app."
        }
    }

    let mode: Mode
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var health: HealthManager
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var imageBase64: String?
    @State private var thumbnail: UIImage?
    @State private var picker: ImagePicker.Source?
    @State private var showPDF = false
    @State private var parsing = false
    @State private var error = ""
    @State private var compResult: BodyComp?
    @State private var labResult: LabRecord?
    // Re-uploading the same report is common — a parsed record waits here until the user answers
    // Replace / Keep both / Cancel. Nothing is saved (and nothing reaches Apple Health) until then.
    @State private var pendingLab: LabRecord?
    @State private var duplicateOf: LabRecord?
    @State private var showDuplicate = false

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        sourceCard
                        if let compResult { bodyCompResultCard(compResult) }
                        if let labResult { labsResultCard(labResult) }
                        if !error.isEmpty {
                            Text(error).font(.system(size: 13)).foregroundStyle(Theme.coral)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.top, 12)
                        }
                    }
                    .padding(16).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } }
            }
            .fullScreenCover(item: $picker) { src in
                ImagePicker(source: src) { img in
                    thumbnail = img
                    imageBase64 = img.base64JPEG(maxDimension: 1600, quality: 0.7)
                }.ignoresSafeArea()
            }
            .fileImporter(isPresented: $showPDF, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result { loadPDF(url) }
            }
            .confirmationDialog(duplicateMessage, isPresented: $showDuplicate, titleVisibility: .visible) {
                Button("Replace") { commitPending(replacing: duplicateOf) }
                Button("Keep both") { commitPending(replacing: nil) }
                Button("Cancel", role: .cancel) { pendingLab = nil; duplicateOf = nil }
            }
        }
        .tint(Theme.accentDark)
    }

    private var duplicateMessage: String {
        let d = duplicateOf.map { BiologyCatalog.effectiveDate($0) } ?? ""
        return "This looks like a report you already imported\(d.isEmpty ? "" : " on \(d)")."
    }

    private func commitPending(replacing existing: LabRecord?) {
        guard let record = pendingLab else { return }
        labResult = store.commitLabImport(record, replacing: existing, health: health)
        pendingLab = nil; duplicateOf = nil
        Task { await health.refresh() }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode.blurb).font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFit()
                    .frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 8) {
                pill("Camera", "camera.fill") { picker = .camera }
                pill("Photo", "photo.fill") { picker = .library }
                pill("PDF", "doc.fill") { showPDF = true }
            }
            TextField("Optional notes / paste values", text: $text, axis: .vertical)
                .font(.system(size: 15)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceOverlay)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.surfaceStroke, lineWidth: 0.5)))
            Button { Task { await parse() } } label: {
                HStack(spacing: 6) {
                    if parsing { ProgressView().tint(.white) }
                    Text(parsing ? "Reading report…" : "Read & save to Health")
                }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentDark], startPoint: .top, endPoint: .bottom)))
            }
            .buttonStyle(.plain)
            .disabled(parsing || (imageBase64 == nil && text.trimmingCharacters(in: .whitespaces).isEmpty))
            .opacity((imageBase64 == nil && text.trimmingCharacters(in: .whitespaces).isEmpty) ? 0.6 : 1)
        }
        .padding(16)
        .glassList()
    }

    private func pill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.accentDark)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceOverlay)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
    }

    private func bodyCompResultCard(_ c: BodyComp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved ✓").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.sage)
            row("Weight", c.weight, "kg")
            row("Body fat", c.bodyFat, "%")
            row("Lean mass", c.leanMass, "kg")
            row("Skeletal muscle", c.skeletalMuscle, "kg")
            row("BMI", c.bmi, "")
            row("Visceral fat", c.visceralFat, "(app only)")
            Text("Weight, body fat, lean mass & BMI saved to Apple Health. Visceral fat is tracked in-app (Health has no type for it) and now drives your Trends prize.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryInk).padding(.top, 4)
        }
        .padding(16).glassList().padding(.top, 12)
    }

    private func labsResultCard(_ r: LabRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(r.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
            if !r.collectedDate.isEmpty {
                Text("Collected \(r.collectedDate)").font(.system(size: 12)).foregroundStyle(Theme.tertiaryInk)
            }
            ForEach(r.items) { item in
                HStack {
                    Text(item.name).font(.system(size: 14)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(trim(item.value)) \(item.unit)").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                    Image(systemName: item.written ? "heart.fill" : "tray.fill")
                        .font(.system(size: 11)).foregroundStyle(item.written ? Theme.adaptive(light: 0xFB1E4B, darkGrey: 0xFF5A79) : Theme.tertiaryInk)
                }
                .padding(.vertical, 4)
            }
            Text("♥ = saved to Apple Health · ▥ = kept in app (Health doesn\u{2019}t accept this type)")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk).padding(.top, 4)
            if store.settings.autoHealthNotes {
                Text("Any out-of-range results were also added as a finding note on the Health tab — your profile keeps itself up to date.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiaryInk)
            }
        }
        .padding(16).glassList().padding(.top, 12)
    }

    private func row(_ label: String, _ value: Double?, _ unit: String) -> some View {
        Group {
            if let value {
                HStack {
                    Text(label).font(.system(size: 14)).foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    Text("\(trim(value)) \(unit)").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private func trim(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }

    private func parse() async {
        parsing = true; error = ""; compResult = nil; labResult = nil
        do {
            let t = text.trimmingCharacters(in: .whitespaces)
            switch mode {
            case .bodyComp:
                compResult = try await store.importBodyComp(text: t.isEmpty ? nil : t, imageBase64: imageBase64, health: health)
            case .labs:
                let out = try await store.prepareLabImport(text: t.isEmpty ? nil : t, imageBase64: imageBase64)
                if let dup = out.duplicateOf {
                    pendingLab = out.record; duplicateOf = dup; showDuplicate = true
                } else {
                    labResult = store.commitLabImport(out.record, replacing: nil, health: health)
                }
            }
            await health.refresh()
        } catch {
            self.error = error.localizedDescription
        }
        parsing = false
    }

    private func loadPDF(_ url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else {
            error = "Couldn\u{2019}t read that PDF."; return
        }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = min(2, 1600 / max(bounds.width, bounds.height))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.set(); ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        thumbnail = img
        imageBase64 = img.base64JPEG(maxDimension: 1600, quality: 0.7)
    }
}
