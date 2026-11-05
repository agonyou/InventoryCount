//  StockRecord.swift
//  A store's stock record from the store system, in inventory.counts (key count::<store>::<sku>):
//  on-hand, reorder level, status and 30-day sales. Written by the store system, synced to that
//  store's crew, read-only on the phone. Told apart from a phone count by stock_quantity and the
//  absence of captured_by, as the counts access rule does.

import Foundation

struct StockRecord: Identifiable, Hashable {
    enum Status: String { case outOfStock = "out_of_stock", lowStock = "low_stock", inStock = "in_stock", overstocked }

    var id: String
    var storeID: String
    var storeName: String
    var sku: String
    var itemName: String
    var onHand: Int
    var reorderLevel: Int
    var reorderQuantity: Int
    var sales30d: Int
    var status: Status
    var location: ItemLocation

    /// The store system's record, not a phone count: it has stock_quantity and no captured_by
    /// (missing or null). The same test as the counts access rule and the app's queries.
    static func isStockRecord(_ d: [String: Any]) -> Bool {
        (d["captured_by"] == nil || d["captured_by"] is NSNull) && d["stock_quantity"] is NSNumber
    }

    init?(id: String, dictionary d: [String: Any]) {
        guard Self.isStockRecord(d), let onHand = (d["stock_quantity"] as? NSNumber)?.intValue,
              let storeID = d["store_id"] as? String, !storeID.isEmpty,
              let sku = d["sku"] as? String, !sku.isEmpty else { return nil }
        self.id = id; self.storeID = storeID; self.sku = sku; self.onHand = onHand
        storeName = d["store_name"] as? String ?? ""
        itemName = d["item_name"] as? String ?? sku
        reorderLevel = (d["reorder_level"] as? NSNumber)?.intValue ?? 0
        reorderQuantity = (d["reorder_quantity"] as? NSNumber)?.intValue ?? 0
        sales30d = (d["sales_volume_30d"] as? NSNumber)?.intValue ?? 0
        location = ItemLocation(dictionary: d["location"] as? [String: Any])
        // The store system's own status; worked out from the numbers when it is missing.
        status = Status(rawValue: d["stock_status"] as? String ?? "")
            ?? (onHand == 0 ? .outOfStock : onHand <= reorderLevel ? .lowStock : .inStock)
    }
}

/// What a count is of, for comparing it with the store system.
enum StockMatch {
    case exact(StockRecord)       // by sku or exact name
    case closest(StockRecord)     // the one store item whose name fits best
    case several(Int)             // more than one fits equally (pack sizes)
    case none

    var record: StockRecord? {
        switch self { case .exact(let r), .closest(let r): return r; default: return nil }
    }
}
