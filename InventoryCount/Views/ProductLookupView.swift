//  ProductLookupView.swift
//  Look up a product by name: type it or say it, and see the store system's product (name,
//  brand, department, price, SKU, barcode) with this store's on-hand, reorder level, status and
//  shelf. Searches the products synced to the phone, so it works with no signal; speech
//  recognition runs on the device too.

import SwiftUI

struct ProductLookupView: View {
    @EnvironmentObject private var database: DatabaseManager
    @StateObject private var speech = SpeechRecognizer()
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let store = AppConfig.currentStoreID
        let found = database.searchProducts(query, store: store)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Look up a product", subtitle: "\(database.products.count.formatted()) products on this phone")
                searchField
                if let error = speech.errorMessage { Text(error).font(CDS.body(12)).foregroundStyle(CDS.red700) }
                if database.products.isEmpty {
                    ContentUnavailableCompat(title: "No products yet", systemImage: "magnifyingglass",
                                             message: "The store's products arrive with the next sync. After that, lookups work with no signal.")
                } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Eyebrow(text: found.total == 0 ? "No match" : found.total > found.results.count
                            ? "Top \(found.results.count) of \(found.total) matches" : "\(found.total) match\(found.total == 1 ? "" : "es")")
                    ForEach(found.results) { ProductCard(product: $0, store: store) }
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // One phrase at a time: the search runs on what was said, then listening stops.
            let recognizer = speech
            recognizer.onUtteranceFinal = { [weak recognizer] _ in recognizer?.stop() }
            #if DEBUG
            // `-tallyQuery "wipes"` fills the search. Used for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if query.isEmpty, let i = args.firstIndex(of: "-tallyQuery"), i + 1 < args.count { query = args[i + 1] }
            #endif
        }
        .onChange(of: speech.transcript) { _, heard in if speech.isListening || !heard.isEmpty { query = heard } }
        .onDisappear { speech.stop() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(CDS.inkSecondary)
            TextField("Name, brand or SKU", text: $query)
                .font(CDS.body(16)).focused($focused)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
            if !query.isEmpty {
                Button { query = ""; speech.reset() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(CDS.inkSecondary) }
                    .accessibilityLabel("Clear")
            }
            Button {
                if speech.isListening { speech.stop() } else {
                    Task {
                        guard await speech.requestPermissions() else { return }
                        focused = false; speech.reset(); query = ""; speech.start()
                    }
                }
            } label: {
                Image(systemName: speech.isListening ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(speech.isListening ? CDS.red : CDS.ink)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(speech.isListening ? "Stop listening" : "Say the product")
        }
        .padding(.horizontal, 12).frame(height: 48)
        .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(speech.isListening ? CDS.red : CDS.borderSubtle))
    }
}

/// One store product with this store's stock: shared by Look up a product and Scan a product.
struct ProductCard: View {
    let product: StoreProduct
    let store: String?
    @EnvironmentObject private var database: DatabaseManager

    var body: some View {
        let p = product
        let stock = database.systemStock(store: store, sku: p.sku, itemName: p.name)
        let details = [p.brand, p.department.isEmpty ? p.category : p.department].filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.name).font(CDS.body(15, weight: .semibold)).foregroundStyle(CDS.ink)
                Spacer(minLength: 8)
                if let price = p.unitPrice {
                    Text(price, format: .currency(code: "USD")).font(CDS.mono(14, weight: .medium)).foregroundStyle(CDS.ink)
                }
            }
            if !details.isEmpty { Text(details).font(CDS.body(12)).foregroundStyle(CDS.inkSecondary) }
            Text([p.sku, p.code.map { "UPC \($0.value)" }].compactMap { $0 }.joined(separator: " · "))
                .font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
            if let stock {
                let tint: Color = stock.status == .outOfStock ? CDS.red700 : stock.status == .lowStock ? CDS.amber : CDS.success
                HStack(spacing: 8) {
                    Badge(text: stock.status == .outOfStock ? "Out of stock" : stock.status == .lowStock ? "Low"
                                : stock.status == .overstocked ? "Overstocked" : "In stock", color: tint)
                    Text("\(stock.onHand) on hand · reorder at \(stock.reorderLevel)").font(CDS.body(12, weight: .semibold)).foregroundStyle(CDS.ink)
                }
                if !stock.location.bayLabel.isEmpty {
                    Text(stock.location.bayLabel).font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
                }
            } else if let store {
                Text("Not stocked at \(store)").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
        .accessibilityElement(children: .combine)
    }
}
