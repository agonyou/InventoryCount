//  BarcodeScanner.swift
//  Live QR / UPC / EAN scanning with VisionKit's DataScannerViewController (camera only;
//  on the Simulator use Photo mode, which runs Vision on a picked image).

import SwiftUI
import VisionKit

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (ScannedCode) -> Void

    static var isSupported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr, .upce, .ean13, .ean8])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (ScannedCode) -> Void
        init(onScan: @escaping (ScannedCode) -> Void) { self.onScan = onScan }
        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in added {
                if case .barcode(let b) = item, let v = b.payloadStringValue {
                    let kind: ScannedCode.Kind
                    switch b.observation.symbology {
                    case .qr: kind = .qr
                    case .upce: kind = .upc
                    default: kind = v.count == 12 ? .upc : .ean
                    }
                    onScan(ScannedCode(type: kind, value: v))
                }
            }
        }
    }
}
