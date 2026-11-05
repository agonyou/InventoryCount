//  BayView.swift
//  Scan a bay: scan the bay's QR code (or pick it from the store's bays) and see what the store
//  system says should be there: each item's on-hand and reorder level, next to the crew's latest
//  count of it at that bay. "Count this bay" sets the capture location. Read-only.
//
//  Bays match on rack, shelf and bin, not site: the store system names one store's site in more
//  than one way (store-001 uses both "generalstore-01" and "celios-downtown").

import SwiftUI

extension ItemLocation {
    /// The same bay of a store: rack, shelf and bin, any case; the site is not compared.
    func sameBay(as other: ItemLocation) -> Bool {
        [(rack, other.rack), (shelf, other.shelf), (bin, other.bin)]
            .allSatisfy { $0.0.caseInsensitiveCompare($0.1) == .orderedSame }
    }
    /// "Aisle 4 · Shelf 1 · Bin 4"
    var bayLabel: String { [rack, shelf, bin].filter { !$0.isEmpty }.joined(separator: " · ") }
}

struct BayView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var session: CaptureSession
    @State private var bay: ItemLocation?
    @State private var showingScanner = false
    @State private var notFound: String?

    var body: some View {
        let store = AppConfig.currentStoreID
        let stock = store.map { database.stock(store: $0) } ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Scan a bay", subtitle: bay?.bayLabel ?? store)
                if BarcodeScannerView.isSupported {
                    Button { showingScanner = true } label: { Label("Scan the bay's QR code", systemImage: "qrcode.viewfinder") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
                if let notFound {
                    Text(notFound).font(CDS.body(13)).foregroundStyle(CDS.red700)
                }
                if let bay {
                    bayDetail(bay, stock: stock)
                } else if stock.isEmpty {
                    ContentUnavailableCompat(title: "No bays yet", systemImage: "square.grid.3x3",
                                             message: store == nil ? "Set your crew to your store (like store-001) in Model & sync."
                                                                   : "The store's stock arrives with the next sync.")
                } else {
                    bayList(stock)
                }
            }
            .padding(16)
        }
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                BarcodeScannerView { code in
                    showingScanner = false
                    open(qr: code.value)
                }
                .ignoresSafeArea()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingScanner = false } } }
            }
        }
        .onAppear {
            #if DEBUG
            // `-tallyBay "Aisle 4/Shelf 1/Bin 4"` opens that bay. Used for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if bay == nil, let i = args.firstIndex(of: "-tallyBay"), i + 1 < args.count {
                let p = args[i + 1].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
                if p.count == 3 { bay = ItemLocation(rack: p[0], shelf: p[1], bin: p[2]) }
            }
            #endif
        }
    }

    /// A scanned QR: a reference location with that QR payload, else the payload read as
    /// "site / rack / shelf / bin".
    private func open(qr: String) {
        let location = database.location(forQR: qr)?.location ?? ItemLocation(parsing: qr)
        if location.rack.isEmpty && location.shelf.isEmpty && location.bin.isEmpty {
            notFound = "That QR code is not a bay this phone knows."
        } else {
            notFound = nil
            bay = location
        }
    }

    // MARK: - The store's bays

    private func bayList(_ stock: [StockRecord]) -> some View {
        var seen: [String: ItemLocation] = [:]
        var items: [String: Int] = [:]
        for r in stock where !r.location.bayLabel.isEmpty {
            let key = r.location.bayLabel.lowercased()
            seen[key] = seen[key] ?? r.location
            items[key, default: 0] += 1
        }
        let bays = seen.sorted { $0.value.bayLabel.localizedStandardCompare($1.value.bayLabel) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Or pick a bay · \(bays.count)")
            ForEach(bays, id: \.key) { key, location in
                Button { bay = location } label: {
                    HStack {
                        Text(location.bayLabel).font(CDS.mono(13, weight: .medium)).foregroundStyle(CDS.ink)
                        Spacer()
                        Text("\(items[key] ?? 0) item\(items[key] == 1 ? "" : "s")").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(CDS.inkSecondary)
                    }
                    .padding(12)
                    .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
                }
            }
        }
    }

    // MARK: - One bay

    private func bayDetail(_ bay: ItemLocation, stock: [StockRecord]) -> some View {
        let expected = stock.filter { $0.location.sameBay(as: bay) }.sorted { $0.itemName < $1.itemName }
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Should be here · \(expected.count)")
            if expected.isEmpty {
                Text("The store system has nothing at this bay.").font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
            }
            ForEach(expected) { r in expectedRow(r, bay: bay) }
            HStack(spacing: 10) {
                Button("Other bays") { self.bay = nil }.buttonStyle(PillButtonStyle())
                Button {
                    session.location = ItemLocation(site: expected.first?.location.site ?? bay.site,
                                                    rack: bay.rack, shelf: bay.shelf, bin: bay.bin)
                    path.removeLast(path.count)
                } label: { Label("Count this bay", systemImage: "mic") }
                .buttonStyle(PillButtonStyle(prominent: true))
            }
        }
    }

    private func expectedRow(_ r: StockRecord, bay: ItemLocation) -> some View {
        // The crew's latest count of this item at this bay, matched the same way as everywhere else
        // (sku, exact name, else closest name).
        let counted = database.entries.first { e in
            e.kind == .entry && e.location.sameBay(as: bay) && database.stockMatch(for: e).record?.sku == r.sku
        }
        let tint: Color = r.status == .outOfStock ? CDS.red700 : r.status == .lowStock ? CDS.amber : CDS.ink
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(r.itemName).font(CDS.body(14, weight: .semibold)).foregroundStyle(CDS.ink)
                Text("\(r.sku) · reorder at \(r.reorderLevel)").font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
                if let counted {
                    Text("Counted \(counted.countDisplay)").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                    SystemCompareLine(counted: counted.count, estimate: counted.countIsEstimate, match: database.stockMatch(for: counted))
                } else {
                    Text("Not counted yet").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(r.onHand)").font(CDS.mono(18, weight: .semibold)).foregroundStyle(tint)
                Text("system").font(CDS.body(11)).foregroundStyle(CDS.inkSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
        .accessibilityElement(children: .combine)
    }
}
