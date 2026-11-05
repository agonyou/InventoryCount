//  ScanProductView.swift
//  Scan a product: scan any barcode and see the store system's product (name, brand, price) with
//  this store's stock, reorder level and whether it is low or out. "Count it" saves a count of the
//  scanned item at the current location; a scan carries the sku, so Count check sees it.
//  Live camera on a phone; on a device without one (the Simulator), a photo of a barcode.

import SwiftUI
import PhotosUI

struct ScanProductView: View {
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var session: CaptureSession
    @State private var code: ScannedCode?
    @State private var photoItem: PhotosPickerItem?
    @State private var reading = false
    @State private var message: String?
    @State private var count = 1
    @State private var saved: CountEntry?

    var body: some View {
        let store = AppConfig.currentStoreID
        let product = code.flatMap { database.product(for: $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Scan a product", subtitle: code.map { "\($0.type.rawValue.uppercased()) \($0.value)" })
                if BarcodeScannerView.isSupported {
                    BarcodeScannerView { scanned in if scanned.type != .qr { show(scanned) } }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: CDS.cardRadius, style: .continuous))
                } else {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(reading ? "Reading…" : "Pick a photo of a barcode", systemImage: "barcode.viewfinder")
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    Text("This device has no camera scanner; a photo of the barcode works the same way.")
                        .font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                }
                if let message { Text(message).font(CDS.body(13)).foregroundStyle(CDS.red700) }
                if let product {
                    ProductCard(product: product, store: store)
                    countIt(product, store: store)
                } else if let code {
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Not in the store catalog").font(CDS.body(15, weight: .semibold)).foregroundStyle(CDS.ink)
                            Text("\(code.type.rawValue.uppercased()) \(code.value) is not one of the store's products on this phone.")
                                .font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
        .onAppear {
            #if DEBUG
            // `-tallyScan 010000100280` shows that barcode as if scanned. Used for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if code == nil, let i = args.firstIndex(of: "-tallyScan"), i + 1 < args.count {
                let v = args[i + 1]
                show(ScannedCode(type: v.count == 12 ? .upc : .ean, value: v))
            }
            #endif
        }
    }

    // MARK: - Count it

    private func countIt(_ product: StoreProduct, store: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Count it at \(session.location.chip)")
            HStack(spacing: 12) {
                Stepper(value: $count, in: 0...9999) {
                    Text("\(count)").font(CDS.mono(22, weight: .semibold)).foregroundStyle(CDS.ink)
                }
                Button("Save count") { save(product, store: store) }
                    .buttonStyle(PillButtonStyle(prominent: true)).frame(width: 150)
            }
            if let saved {
                SystemCompareLine(counted: saved.count, match: database.stockMatch(for: saved))
                Text("Saved \(saved.count) \(saved.itemName) at \(saved.location.chip).").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
            }
        }
    }

    private func save(_ product: StoreProduct, store: String?) {
        guard let code else { return }
        let entry = CountEntry(itemName: product.name, count: count, location: session.location, source: .code, code: code,
                               storeID: store, sku: store == nil ? nil : product.sku)
        do {
            try database.save(entry)
            session.sessionRows.insert(entry, at: 0)
            saved = entry
            message = nil
        } catch { message = error.localizedDescription }
    }

    // MARK: - Reading a code

    private func show(_ scanned: ScannedCode) {
        guard scanned != code else { return }
        code = scanned; count = 1; saved = nil; message = nil
    }

    private func read(_ item: PhotosPickerItem) async {
        reading = true
        defer { reading = false; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            message = "Could not open that photo."; return
        }
        let found = await VisionAnalyzer.analyze(image).codes.filter { $0.type != .qr }
        if let first = found.first { show(first) } else { message = "No barcode found in that photo." }
    }
}
