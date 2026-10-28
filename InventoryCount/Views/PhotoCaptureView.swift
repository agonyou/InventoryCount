//  PhotoCaptureView.swift
//  Photo with detected-bin overlay, QR → location chip, UPC → catalogue chip,
//  scene description card, detected items, Retake / Add N rows.

import SwiftUI
import PhotosUI
import UIKit

struct PhotoCaptureView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var session: CaptureSession
    @EnvironmentObject private var model: InventoryModel
    @EnvironmentObject private var settings: CaptureSettings

    @State private var image: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingScanner = false
    @State private var analysis: PhotoAnalysis?
    @State private var items: [DetectedItem] = []
    @State private var highlightedBin = 0
    @State private var notes = ""
    @State private var parsed: ParseResult?
    @State private var rows: [ParsedRow] = []
    @State private var isWorking = false
    @State private var error: String?
    @State private var unknownCode: ScannedCode?
    @State private var newCodeName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let image { photoCard(image) } else { pickerCard }
                if let a = analysis, !a.codes.isEmpty { codeChips(a.codes) }
                if let error { Text(error).font(CDS.body(13)).foregroundStyle(CDS.red700) }
                if let parsed, !parsed.sceneDescription.isEmpty {
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(text: "Scene")
                            Text(parsed.sceneDescription).font(CDS.body(14)).foregroundStyle(CDS.ink)
                        }
                    }
                }
                if image != nil && parsed == nil {
                    TextField("Optional notes to go with the photo", text: $notes, axis: .vertical)
                        .font(CDS.body(15)).lineLimit(2...5).padding(12)
                        .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
                    HStack(spacing: 10) {
                        Button("Retake") { reset() }.buttonStyle(PillButtonStyle())
                        Button { Task { await analyzeAndParse() } } label: {
                            HStack { if isWorking { ProgressView().tint(.white) }; Text(isWorking ? "Counting…" : "Count items") }
                        }
                        .buttonStyle(PillButtonStyle(prominent: true)).disabled(isWorking)
                    }
                }
                if parsed != nil {
                    HStack { Eyebrow(text: "Detected items"); Spacer(); if rows.contains(where: { $0.countIsEstimate || $0.confidence < settings.confidenceThreshold }) { Badge(text: "Review counts", color: CDS.amber) } }
                    ParsedRowsPreview(rows: $rows, modelName: parsed?.modelName ?? "", onSave: save, onDiscard: reset)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .fullScreenCover(isPresented: $showingCamera) { CameraPicker(image: $image).ignoresSafeArea() }
        .sheet(isPresented: $showingScanner) { scannerSheet }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { if let data = try? await item.loadTransferable(type: Data.self) { image = UIImage(data: data); analysis = nil; parsed = nil } }
        }
        .onChange(of: image) { _, img in if img != nil { Task { await analyze() } } }
        .alert("Name this product", isPresented: Binding(get: { unknownCode != nil }, set: { if !$0 { unknownCode = nil } })) {
            TextField("Product name", text: $newCodeName)
            Button("Save") { saveCatalogue() }
            Button("Cancel", role: .cancel) { unknownCode = nil }
        } message: { Text("\(unknownCode?.type.rawValue.uppercased() ?? "") \(unknownCode?.value ?? "") is not in the catalogue yet. Name it once; later scans reuse it.") }
    }

    private var pickerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Photograph the items")
                Text("Frame a rack, shelf or bin. Barcodes and printed labels in the frame are read on device.")
                    .font(CDS.body(14)).foregroundStyle(CDS.inkSecondary)
                HStack(spacing: 10) {
                    if CameraPicker.isAvailable {
                        Button { showingCamera = true } label: { Label("Camera", systemImage: "camera") }.buttonStyle(PillButtonStyle(prominent: true))
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Library", systemImage: "photo.on.rectangle") }
                        .buttonStyle(PillButtonStyle(prominent: !CameraPicker.isAvailable))
                }
                if BarcodeScannerView.isSupported {
                    Button { showingScanner = true } label: { Label("Scan a barcode", systemImage: "barcode.viewfinder") }.buttonStyle(PillButtonStyle())
                }
            }
        }
    }

    private func photoCard(_ img: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                        let r = it.box
                        let rect = CGRect(x: r.minX * geo.size.width, y: (1 - r.maxY) * geo.size.height,
                                          width: r.width * geo.size.width, height: r.height * geo.size.height)
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(i == highlightedBin ? CDS.red : Color.white.opacity(0.75), lineWidth: i == highlightedBin ? 3 : 1.5)
                            Text("\(i + 1)").font(CDS.mono(10, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(i == highlightedBin ? CDS.red : Color.black.opacity(0.55), in: Capsule())
                                .offset(x: 4, y: 4)
                        }
                        .frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                        .onTapGesture { highlightedBin = i }
                    }
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: CDS.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CDS.cardRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
            if analysis != nil {
                Text(items.isEmpty ? "No items detected — counting from labels and notes."
                     : "\(items.count) item\(items.count == 1 ? "" : "s") detected · tap one to highlight")
                    .font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                if !items.isEmpty, highlightedBin < items.count {
                    let it = items[highlightedBin]
                    Card(padding: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Eyebrow(text: "Item \(highlightedBin + 1)")
                            Text(it.summaryLine.isEmpty ? "No readable label; colour \(it.color)" : it.summaryLine)
                                .font(CDS.body(13)).foregroundStyle(CDS.ink)
                        }
                    }
                }
                if let tags = analysis?.sceneTags, !tags.isEmpty, parsed == nil {
                    Text("Scene: " + tags.prefix(4).map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", "))
                        .font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                }
            }
        }
    }

    private func codeChips(_ codes: [ScannedCode]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(codes, id: \.self) { c in
                    if c.type == .qr {
                        Button { applyQR(c) } label: {
                            Label("QR → \(database.location(forQR: c.value)?.location.chip ?? c.value)", systemImage: "qrcode")
                        }
                    } else {
                        let known = database.catalogueItem(for: c)
                        Button { if known == nil { unknownCode = c } } label: {
                            Label(known?.name ?? "\(c.type.rawValue.uppercased()) \(c.value) · name it", systemImage: "barcode")
                        }
                    }
                }
            }
        }
        .font(CDS.mono(12, weight: .medium)).foregroundStyle(CDS.ink)
        .buttonStyle(.bordered).tint(CDS.ink)
    }

    private var scannerSheet: some View {
        NavigationStack {
            BarcodeScannerView { code in
                showingScanner = false
                if code.type == .qr { applyQR(code) }
                else if database.catalogueItem(for: code) == nil { unknownCode = code }
                else { addCatalogueRow(code) }
            }
            .ignoresSafeArea()
            .navigationTitle("Scan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingScanner = false } }
                       ToolbarItem(placement: .confirmationAction) { Button("Done") { showingScanner = false } } }
        }
    }

    // MARK: - Actions

    private func analyze() async {
        guard let image else { return }
        analysis = await VisionAnalyzer.analyze(image)
        items = analysis?.items ?? []
        highlightedBin = 0
        if let qr = analysis?.codes.first(where: { $0.type == .qr }) { applyQR(qr) }
    }

    private func analyzeAndParse() async {
        guard let image else { return }
        isWorking = true; error = nil
        defer { isWorking = false }
        if analysis == nil { analysis = await VisionAnalyzer.analyze(image) }
        do {
            let r = try await model.parse(text: notes, photo: analysis, imageJPEG: image.inventoryJPEG(),
                                          defaultLocation: session.location,
                                          knownLocations: database.locations.map(\.location.display))
            parsed = r; rows = r.rows
            if !r.items.isEmpty { items = r.items; highlightedBin = 0 }
            if r.rows.isEmpty { error = "No items recognised. Add a note describing the shelf and try again." }
        } catch { self.error = error.localizedDescription }
    }

    private func applyQR(_ code: ScannedCode) {
        if let ref = database.location(forQR: code.value) { session.location = ref.location }
        else { session.location = ItemLocation(parsing: code.value) }
    }

    private func saveCatalogue() {
        guard let code = unknownCode, !newCodeName.isEmpty else { return }
        try? database.save(CatalogueItem(code: code, name: newCodeName))
        unknownCode = nil; newCodeName = ""
        addCatalogueRow(code)
    }

    private func addCatalogueRow(_ code: ScannedCode) {
        guard let item = database.catalogueItem(for: code) else { return }
        rows.append(ParsedRow(itemName: item.name, count: 1, countIsEstimate: false, attributes: item.attributes,
                              annotation: "Scanned \(code.type.rawValue.uppercased()) \(code.value)",
                              location: session.location.display, confidence: 100))
        if parsed == nil { parsed = ParseResult(rows: rows, sceneDescription: "", modelName: "Barcode") }
    }

    private func save() {
        do {
            try RowSaver.save(rows, source: image != nil ? .photo : .code, codes: analysis?.codes ?? [],
                              photo: image?.inventoryJPEG(), database: database, session: session, settings: settings)
            reset()
        } catch { self.error = error.localizedDescription }
    }

    private func reset() { image = nil; photoItem = nil; analysis = nil; items = []; parsed = nil; rows = []; notes = ""; error = nil }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController(); p.sourceType = .camera; p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage; parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
