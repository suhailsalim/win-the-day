import UIKit
import SwiftUI

/// Lightweight system share sheet for sharing/saving a file URL (e.g. the PDF report).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Renders a doctor-ready health summary PDF from the user's data.
extension AppStore {
    func exportHealthPDF() -> URL? {
        let pageW: CGFloat = 612, pageH: CGFloat = 792
        let margin: CGFloat = 48
        let bounds = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        let title = UIFont.systemFont(ofSize: 24, weight: .bold)
        let h2 = UIFont.systemFont(ofSize: 15, weight: .semibold)
        let body = UIFont.systemFont(ofSize: 11, weight: .regular)
        let small = UIFont.systemFont(ofSize: 9, weight: .regular)
        let ink = UIColor(white: 0.12, alpha: 1)
        let grey = UIColor(white: 0.45, alpha: 1)

        let st = weeklyStats()
        let dateStr = Self.dateString(Date())

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("win-the-day-health-\(dateStr).pdf")

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = margin

                func newPageIfNeeded(_ needed: CGFloat) {
                    if y + needed > pageH - margin { ctx.beginPage(); y = margin }
                }
                func draw(_ text: String, _ font: UIFont, _ color: UIColor, x: CGFloat = margin) {
                    let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                    let h = (text as NSString).boundingRect(
                        with: CGSize(width: pageW - margin - x, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attr, context: nil).height
                    newPageIfNeeded(h)
                    (text as NSString).draw(in: CGRect(x: x, y: y, width: pageW - margin - x, height: h), withAttributes: attr)
                    y += h + 4
                }
                func row(_ cols: [String], widths: [CGFloat], font: UIFont, color: UIColor) {
                    newPageIfNeeded(16)
                    var x = margin
                    for (i, c) in cols.enumerated() {
                        let w = widths[i]
                        (c as NSString).draw(in: CGRect(x: x, y: y, width: w - 4, height: 14),
                                             withAttributes: [.font: font, .foregroundColor: color])
                        x += w
                    }
                    y += 16
                }
                func divider() {
                    newPageIfNeeded(10)
                    let p = UIBezierPath()
                    p.move(to: CGPoint(x: margin, y: y)); p.addLine(to: CGPoint(x: pageW - margin, y: y))
                    UIColor(white: 0.85, alpha: 1).setStroke(); p.lineWidth = 0.5; p.stroke()
                    y += 12
                }

                draw("Win the Day — Health Report", title, ink)
                draw("Generated \(dateStr)", small, grey)
                y += 8; divider()

                // Prize
                draw("Priority metric", h2, ink)
                let arrow = targets.prizeLowerIsBetter ? "≤" : "≥"
                draw("\(targets.prizeName): \(fmtNum(targets.prizeCurrent))\(targets.prizeUnit) (goal \(arrow)\(fmtNum(targets.prizeTarget))\(targets.prizeUnit))", body, ink)
                y += 6; divider()

                // Weekly stats
                draw("This week", h2, ink)
                let wChange = st.weightChange.map { String(format: "%+.1f kg", $0) } ?? "n/a"
                let prot = st.avgProtein.map { "\(Int($0)) g" } ?? "n/a"
                draw("Days logged: \(st.daysLogged)/7    Avg score: \(String(format: "%.1f", st.avgScore))/5    Perfect days: \(st.perfectDays)", body, ink)
                draw("Weight change: \(wChange)    Avg protein: \(prot)    Prayers: \(st.prayersDone)/\(st.prayersPossible)", body, ink)
                y += 6; divider()

                // Body composition
                let comps = data.bodyComps.sorted { $0.date < $1.date }
                if !comps.isEmpty {
                    draw("Body composition", h2, ink)
                    let widths: [CGFloat] = [90, 70, 70, 80, 60, 60]
                    row(["Date", "Weight", "Body fat", "Lean mass", "BMI", "Visc."], widths: widths, font: small, color: grey)
                    for c in comps {
                        row([c.date,
                             c.weight.map { String(format: "%.1f kg", $0) } ?? "—",
                             c.bodyFat.map { String(format: "%.1f%%", $0) } ?? "—",
                             c.leanMass.map { String(format: "%.1f kg", $0) } ?? "—",
                             c.bmi.map { String(format: "%.1f", $0) } ?? "—",
                             c.visceralFat.map { String(format: "%.0f", $0) } ?? "—"],
                            widths: widths, font: body, color: ink)
                    }
                    y += 6; divider()
                }

                // Labs (most recent record)
                if let lab = data.labs.sorted(by: { $0.date < $1.date }).last, !lab.items.isEmpty {
                    draw("Lab results — \(lab.title) (\(lab.date))", h2, ink)
                    let widths: [CGFloat] = [300, 120, 96]
                    row(["Test", "Value", "Unit"], widths: widths, font: small, color: grey)
                    for it in lab.items {
                        row([it.name, fmtNum(it.value), it.unit], widths: widths, font: body, color: ink)
                    }
                    y += 6; divider()
                }

                draw("Generated by Win the Day. Reference values are general adult guidance, not medical advice.", small, grey)
            }
            return url
        } catch {
            return nil
        }
    }

    private func fmtNum(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d) }
}
