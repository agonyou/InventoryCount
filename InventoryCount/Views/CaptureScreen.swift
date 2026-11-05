//  CaptureScreen.swift
//  Home: location chip + sheet button header, one capture mode at a time,
//  segmented control at the bottom to switch Voice / Text / Photo in one tap.

import SwiftUI

enum CaptureMode: String, CaseIterable, Identifiable {
    case voice, text, photo
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String { self == .voice ? "mic" : self == .text ? "text.alignleft" : "camera" }
}

struct CaptureScreen: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var session: CaptureSession
    @State private var mode: CaptureMode = .voice

    var body: some View {
        VStack(spacing: 0) {
            header
            NomadStrip(path: $path)
            Group {
                switch mode {
                case .voice: VoiceCaptureView(path: $path)
                case .text:  TextCaptureView(path: $path)
                case .photo: PhotoCaptureView(path: $path)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            modePicker
        }
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 10) {
            LocationChip(path: $path)
            Spacer()
            if AppConfig.currentStoreID != nil {
                Button { path.append(Route.snapshot) } label: {
                    Image(systemName: "storefront").font(.system(size: 17, weight: .medium)).foregroundStyle(CDS.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Store snapshot")
            }
            Button { path.append(Route.modelSync) } label: {
                Image(systemName: "cpu").font(.system(size: 17, weight: .medium)).foregroundStyle(CDS.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Model and sync")
            Button { path.append(Route.sheet) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tablecells").font(.system(size: 14, weight: .semibold))
                    Text("Sheet").font(CDS.body(14, weight: .semibold))
                    let n = database.entries.filter { $0.kind == .entry }.count
                    if n > 0 { Text("\(n)").font(CDS.mono(12, weight: .medium)) }
                }
                .foregroundStyle(CDS.ink)
                .padding(.horizontal, 14).frame(height: 44)
                .background(CDS.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(CDS.borderSubtle))
            }
            .accessibilityLabel("Open inventory sheet")
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(CaptureMode.allCases) { m in
                Button { withAnimation(.easeInOut(duration: 0.15)) { mode = m } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m.systemImage).font(.system(size: 14, weight: .semibold))
                        Text(m.label).font(CDS.body(14, weight: .semibold))
                    }
                    .foregroundStyle(mode == m ? CDS.ink : CDS.inkSecondary)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(mode == m ? CDS.surface : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(mode == m ? CDS.borderSubtle : .clear))
                }
                .accessibilityLabel("\(m.label) mode")
                .accessibilityAddTraits(mode == m ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(hex: 0xF3ECE1), in: Capsule())
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/// "System 31 · −3" or "Matches the system": a count next to the store system's on-hand for the
/// same item, shown the moment it is counted. Nothing when the item is not a store product.
struct SystemCompareLine: View {
    let counted: Int
    var estimate = false
    let match: StockMatch

    var body: some View {
        switch match {
        case .exact(let system), .closest(let system):
            let gap = counted - system.onHand
            VStack(alignment: .leading, spacing: 1) {
                if case .closest = match {
                    // A guess from the name: say which item, so the counter can check it.
                    Text("Closest: \(system.itemName)").font(CDS.body(11)).foregroundStyle(CDS.inkSecondary).lineLimit(1)
                }
                HStack(spacing: 4) {
                    Image(systemName: gap == 0 ? "checkmark.circle.fill" : "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text(gap == 0 ? "Matches the system (\(system.onHand))"
                                  : "System \(system.onHand) · \(estimate ? "≈" : "")\(gap > 0 ? "+" : "−")\(abs(gap))")
                        .font(CDS.body(12, weight: .semibold))
                }
                .foregroundStyle(gap == 0 ? CDS.success : CDS.amber)
            }
            .accessibilityElement(children: .combine)
        case .several(let n):
            Text("\(n) store items fit this name: say the pack size or scan it")
                .font(CDS.body(11)).foregroundStyle(CDS.inkSecondary)
        case .none:
            EmptyView()
        }
    }
}

/// The rows saved this session, each next to the store system's number. Shared by Voice and Text.
struct SessionRowsList: View {
    @Binding var path: NavigationPath
    var title = "Heard this session"
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var session: CaptureSession

    var body: some View {
        if !session.sessionRows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: title)
                ForEach(session.sessionRows.prefix(12)) { e in
                    HStack(spacing: 10) {
                        Image(systemName: e.source.systemImage).font(.system(size: 13)).foregroundStyle(CDS.inkSecondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.itemName).font(CDS.body(14, weight: .semibold)).foregroundStyle(CDS.ink)
                            Text(e.location.chip).font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
                            SystemCompareLine(counted: e.count, estimate: e.countIsEstimate, match: database.stockMatch(for: e))
                        }
                        Spacer()
                        Text(e.countBadge).font(CDS.mono(15, weight: .medium)).foregroundStyle(e.countIsEstimate ? CDS.amber : CDS.ink)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
                    .onTapGesture { path.append(Route.entry(e)) }
                }
            }
        }
    }
}

/// Rows the model parsed, shown before they are saved. Shared by all three modes.
struct ParsedRowsPreview: View {
    @Binding var rows: [ParsedRow]
    var sceneDescription: String = ""
    var modelName: String = ""
    let onSave: () -> Void
    let onDiscard: () -> Void
    @EnvironmentObject private var settings: CaptureSettings
    @EnvironmentObject private var database: DatabaseManager

    /// Id-keyed binding: never indexes the array by position, so a row that was removed
    /// (or a list that was cleared on Save/Discard) can't trigger "Index out of range".
    private func binding(for id: UUID) -> Binding<ParsedRow> {
        Binding(
            get: { rows.first { $0.id == id } ?? ParsedRow(itemName: "", count: 0, countIsEstimate: false, attributes: "", annotation: "", location: "", confidence: 0) },
            set: { new in if let i = rows.firstIndex(where: { $0.id == id }) { rows[i] = new } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Preview · \(rows.count) row\(rows.count == 1 ? "" : "s")")
                Spacer()
                if !modelName.isEmpty { Text(modelName).font(CDS.body(11)).foregroundStyle(CDS.inkSecondary) }
            }
            if !sceneDescription.isEmpty {
                Card(padding: 12) { Text(sceneDescription).font(CDS.body(13)).foregroundStyle(CDS.ink) }
            }
            ForEach(rows) { item in
                let row = binding(for: item.id)
                let low = item.confidence < settings.confidenceThreshold && settings.flagLowConfidence
                Card(padding: 12, tint: (item.countIsEstimate || low) ? CDS.amberTint : CDS.surface,
                     border: (item.countIsEstimate || low) ? CDS.amberSoft : CDS.borderSubtle, dashed: item.countIsEstimate) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Item", text: row.itemName).font(CDS.body(15, weight: .semibold)).foregroundStyle(CDS.ink)
                            TextField("Size · shape · color", text: row.attributes).font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
                            TextField("Annotation", text: row.annotation, axis: .vertical).font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
                            HStack(spacing: 6) {
                                Text(item.location).font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
                                if low { Badge(text: "Review", color: CDS.amber) }
                            }
                            SystemCompareLine(counted: item.count, estimate: item.countIsEstimate,
                                              match: database.stockMatch(store: AppConfig.currentStoreID, sku: nil, itemName: item.itemName))
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 6) {
                            HStack(spacing: 2) {
                                if item.countIsEstimate { Text("≈").font(CDS.mono(18)).foregroundStyle(CDS.amber) }
                                TextField("0", value: row.count, format: .number)
                                    .font(CDS.mono(20, weight: .semibold)).multilineTextAlignment(.trailing)
                                    .keyboardType(.numberPad).frame(width: 64)
                            }
                            HStack(spacing: 10) {
                                Toggle("≈", isOn: row.countIsEstimate).labelsHidden().scaleEffect(0.7).frame(width: 36, height: 20)
                                Button { rows.removeAll { $0.id == item.id } } label: {
                                    Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(CDS.inkSecondary)
                                        .frame(width: 32, height: 32)
                                }
                                .accessibilityLabel("Remove row")
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Discard", action: onDiscard).buttonStyle(PillButtonStyle())
                Button("Add \(rows.count) row\(rows.count == 1 ? "" : "s")", action: onSave)
                    .buttonStyle(PillButtonStyle(prominent: true)).disabled(rows.isEmpty)
            }
        }
    }
}

/// Converts parsed rows into CountEntry documents and saves them.
@MainActor
enum RowSaver {
    static func save(_ rows: [ParsedRow], source: CaptureSource, codes: [ScannedCode] = [], photo: Data? = nil,
                     database: DatabaseManager, session: CaptureSession, settings: CaptureSettings, speech: SpeechRecognizer? = nil) throws {
        let now = Date()
        let code = codes.first { $0.type != .qr }
        let storeID = AppConfig.currentStoreID
        let entries = rows.map { r -> CountEntry in
            let low = settings.flagLowConfidence && r.confidence < settings.confidenceThreshold
            // On a store team, a row that is a store product carries its sku: by the scanned code
            // when that code is this row's product, else by its exact name.
            var sku: String?
            if storeID != nil {
                // The scanned code is this row's when the row carries either name the code has: the
                // store product's, or the team catalog's (Photo mode names a scan by the catalog first).
                let names = [code.flatMap { database.product(for: $0)?.name }, code.flatMap { database.catalogItem(for: $0)?.name }]
                let isScannedRow = names.contains { $0?.caseInsensitiveCompare(r.itemName) == .orderedSame }
                sku = (isScannedRow ? code.flatMap { database.product(for: $0) }?.sku : nil)
                    ?? database.product(named: r.itemName)?.sku
            }
            return CountEntry(itemName: r.itemName, count: r.count, countIsEstimate: r.countIsEstimate,
                              attributes: r.attributes, annotation: r.annotation,
                              location: r.location.isEmpty ? session.location : ItemLocation(parsing: r.location),
                              source: source, code: code, storeID: storeID, sku: sku, confidence: r.confidence,
                              needsReview: low, capturedAt: now, hasPhoto: photo != nil)
        }
        try database.saveAll(entries, photo: photo)
        session.sessionRows.insert(contentsOf: entries, at: 0)
        if settings.readCountsAloud, let speech {
            // A count that differs from the store system is followed by the system's number.
            speech.speak(entries.map { e in
                var said = "\(e.countIsEstimate ? "about " : "")\(e.count) \(e.itemName)"
                if let system = database.stockMatch(for: e).record, system.onHand != e.count { said += ", system says \(system.onHand)" }
                return said
            }.joined(separator: ", "))
        }
    }
}
