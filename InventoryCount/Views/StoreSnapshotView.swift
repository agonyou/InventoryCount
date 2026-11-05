//  StoreSnapshotView.swift
//  Store snapshot: what is out, what is low, and the fastest sellers, from the store system's
//  stock records synced to this store's crew. Read-only; works offline from the last sync.

import SwiftUI

struct StoreSnapshotView: View {
    @EnvironmentObject private var database: DatabaseManager
    @Binding var path: NavigationPath
    @State private var expanded: Set<String> = []
    private let collapsedRows = 5

    var body: some View {
        let store = AppConfig.currentStoreID
        let stock = store.map { database.stock(store: $0) } ?? []
        let out = stock.filter { $0.status == .outOfStock }.sorted(by: Self.bySales)
        let low = stock.filter { $0.status == .lowStock }.sorted(by: Self.bySales)
        let fastest = stock.sorted(by: Self.bySales).prefix(20).filter { $0.sales30d > 0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Store snapshot",
                             subtitle: stock.first.map { "\($0.storeName.isEmpty ? $0.storeID : $0.storeName) · \(stock.count) SKUs" } ?? store)
                if let store {
                    Button { path.append(Route.lookup) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold))
                            Text("Look up a product").font(CDS.body(14, weight: .semibold))
                            Text("type or say it").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(CDS.inkSecondary)
                        }
                        .foregroundStyle(CDS.ink)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(CDS.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(CDS.borderSubtle))
                    }
                    Button { path.append(Route.scanProduct) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "barcode.viewfinder").font(.system(size: 14, weight: .semibold))
                            Text("Scan a product").font(CDS.body(14, weight: .semibold))
                            Text("stock, price, reorder").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(CDS.inkSecondary)
                        }
                        .foregroundStyle(CDS.ink)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(CDS.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(CDS.borderSubtle))
                    }
                    let coming = database.shipments.filter { $0.storeID == store }.count
                    Button { path.append(Route.deliveries) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "truck.box").font(.system(size: 14, weight: .semibold))
                            Text("Deliveries and trucks").font(CDS.body(14, weight: .semibold))
                            Text(coming == 0 ? "none coming" : "\(coming) coming").font(CDS.mono(12)).foregroundStyle(CDS.inkSecondary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(CDS.inkSecondary)
                        }
                        .foregroundStyle(CDS.ink)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(CDS.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(CDS.borderSubtle))
                    }
                    Button { path.append(Route.bay) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "qrcode.viewfinder").font(.system(size: 14, weight: .semibold))
                            Text("Scan a bay").font(CDS.body(14, weight: .semibold))
                            Text("what should be on a shelf").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(CDS.inkSecondary)
                        }
                        .foregroundStyle(CDS.ink)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(CDS.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(CDS.borderSubtle))
                    }
                }
                if store == nil {
                    ContentUnavailableCompat(title: "No store", systemImage: "storefront",
                                             message: "Set your crew to your store (like store-001) in Model & sync to see its stock.")
                } else if stock.isEmpty {
                    ContentUnavailableCompat(title: "No stock yet", systemImage: "storefront",
                                             message: "The store's stock arrives with the next sync.")
                } else {
                    HStack(spacing: 10) {
                        StatTile(value: "\(out.count)", label: "Out of stock", tint: out.isEmpty ? CDS.ink : CDS.red700)
                        StatTile(value: "\(low.count)", label: "Low", tint: low.isEmpty ? CDS.ink : CDS.amber)
                        StatTile(value: "\(stock.count - out.count - low.count)", label: "In stock")
                    }
                    list("out", title: "Out of stock", rows: out, empty: "Nothing is out of stock.")
                    list("low", title: "Low stock", rows: low, empty: "Nothing is below its reorder level.")
                    list("fastest", title: "Fastest sellers · 30 days", rows: Array(fastest), empty: "No sales recorded.")
                }
            }
            .padding(16)
        }
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func bySales(_ a: StockRecord, _ b: StockRecord) -> Bool {
        a.sales30d != b.sales30d ? a.sales30d > b.sales30d : a.itemName < b.itemName
    }

    private func list(_ key: String, title: String, rows: [StockRecord], empty: String) -> some View {
        let all = expanded.contains(key) || rows.count <= collapsedRows
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "\(title) · \(rows.count)")
            if rows.isEmpty {
                Text(empty).font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
            }
            ForEach(all ? rows : Array(rows.prefix(collapsedRows))) { row($0) }
            if rows.count > collapsedRows {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
                    }
                } label: {
                    Label(all ? "Show fewer" : "Show all \(rows.count)", systemImage: all ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }

    private func row(_ r: StockRecord) -> some View {
        let tint: Color = r.status == .outOfStock ? CDS.red700 : r.status == .lowStock ? CDS.amber : CDS.ink
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(r.itemName).font(CDS.body(14, weight: .semibold)).foregroundStyle(CDS.ink)
                Text("\(r.sku) · \(r.location.chip)").font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
                Text("Reorder at \(r.reorderLevel) · \(r.sales30d) sold in 30 days").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(r.onHand)").font(CDS.mono(18, weight: .semibold)).foregroundStyle(tint)
                Text("on hand").font(CDS.body(11)).foregroundStyle(CDS.inkSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
        .accessibilityElement(children: .combine)
    }
}
