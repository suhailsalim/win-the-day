import SwiftUI
import VisionKit

/// Live barcode scanner (VisionKit DataScanner). Returns the first barcode payload.
struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        try? vc.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BarcodeScanner
        private var done = false
        init(_ parent: BarcodeScanner) { self.parent = parent }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(added)
        }
        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }
        private func handle(_ items: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case let .barcode(code) = item, let payload = code.payloadStringValue {
                    done = true
                    parent.onScan(payload)
                    parent.dismiss()
                    return
                }
            }
        }
    }
}

/// Wrapper sheet with a header (DataScanner has no chrome of its own).
struct BarcodeScanSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if BarcodeScanner.isSupported {
                    BarcodeScanner(onScan: onScan).ignoresSafeArea()
                } else {
                    ZStack {
                        WarmBackground()
                        Text("Barcode scanning isn\u{2019}t available on this device.")
                            .font(.system(size: 15)).foregroundStyle(Theme.secondaryInk)
                            .multilineTextAlignment(.center).padding()
                    }
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
    }
}
