//  ProposalDoc.swift
//  What Nomad saved to inventory.proposals after a person approved it (type "proposal").
//  Read-only on the phone. The access rules send each one to the stores it is about:
//  purchase_order and count_check to one store, replenishment to every store a transfer goes
//  to, cold_chain_alert to everyone.

import Foundation

struct ProposalDoc: Identifiable, Hashable {
    static let docType = "proposal"

    enum Kind: String {
        case purchaseOrder = "purchase_order", replenishment, coldChainAlert = "cold_chain_alert", countCheck = "count_check"
        case shiftSummary = "shift_summary"
    }

    struct OrderLine: Hashable { var sku, itemName, reason: String; var onHand, orderQuantity: Int }
    struct Transfer: Hashable { var sku, itemName, priority, reason: String; var toStoreIDs: [String]; var unitsPerStore, dcReserveUnits: Int }
    struct TruckAlert: Hashable { var truckID, severity, action: String; var driftF: Double }
    struct Finding: Hashable { var sku, itemName, action, priority, reason: String; var counted, systemOnHand, difference, orderQuantity: Int }

    var id: String
    var kind: Kind
    var day: String
    var storeID: String
    var summary: String
    var status: String
    var toleranceF: Double?
    var lines: [OrderLine] = []
    var transfers: [Transfer] = []
    var needsSupplierOrder: [String] = []
    var alerts: [TruckAlert] = []
    var findings: [Finding] = []
    var highlights: [String] = []   // shift summary: things to act on

    init?(id: String, dictionary d: [String: Any]) {
        guard (d["type"] as? String) == ProposalDoc.docType,
              let kind = Kind(rawValue: d["kind"] as? String ?? "") else { return nil }
        self.id = id; self.kind = kind
        day = d["day"] as? String ?? ""
        storeID = d["store_id"] as? String ?? ""
        summary = d["summary"] as? String ?? ""
        status = d["status"] as? String ?? ""
        toleranceF = Self.number(d["tolerance_f"])
        lines = Self.list(d["lines"]).map {
            OrderLine(sku: Self.text($0["sku"]), itemName: Self.text($0["item_name"]), reason: Self.text($0["reason"]),
                      onHand: Self.int($0["on_hand"]), orderQuantity: Self.int($0["order_quantity"]))
        }
        transfers = Self.list(d["transfers"]).map {
            Transfer(sku: Self.text($0["sku"]), itemName: Self.text($0["item_name"]), priority: Self.text($0["priority"]),
                     reason: Self.text($0["reason"]), toStoreIDs: ($0["to_store_ids"] as? [Any] ?? []).compactMap { $0 as? String },
                     unitsPerStore: Self.int($0["units_per_store"]), dcReserveUnits: Self.int($0["dc_reserve_units"]))
        }
        needsSupplierOrder = (Self.value(d["needs_supplier_order"]) as? [Any] ?? []).compactMap { $0 as? String }
        alerts = Self.list(d["alerts"]).map {
            TruckAlert(truckID: Self.text($0["truck_id"]), severity: Self.text($0["severity"]), action: Self.text($0["action"]),
                       driftF: Self.number($0["drift_f"]) ?? 0)
        }
        highlights = (Self.value(d["highlights"]) as? [Any] ?? []).compactMap { $0 as? String }
        findings = Self.list(d["findings"]).map {
            Finding(sku: Self.text($0["sku"]), itemName: Self.text($0["item_name"]), action: Self.text($0["action"]),
                    priority: Self.text($0["priority"]), reason: Self.text($0["reason"]), counted: Self.int($0["counted"]),
                    systemOnHand: Self.int($0["system_on_hand"]), difference: Self.int($0["difference"]),
                    orderQuantity: Self.int($0["order_quantity"]))
        }
    }

    /// Whether a crew at `store` should see this. The access rules already route it; this also
    /// keeps a proposal that reached the phone some other way (peer-to-peer) off the wrong store.
    func isFor(store: String?) -> Bool {
        switch kind {
        case .coldChainAlert: return true
        case .purchaseOrder, .countCheck, .shiftSummary: return store != nil && storeID == store
        case .replenishment: return store.map { s in transfers.contains { $0.toStoreIDs.contains(s) } } ?? false
        }
    }

    func transfers(to store: String) -> [Transfer] { transfers.filter { $0.toStoreIDs.contains(store) } }

    var title: String {
        switch kind {
        case .purchaseOrder: return "Purchase order"
        case .replenishment: return "Transfers from the DC"
        case .coldChainAlert: return "Cold-chain alert"
        case .countCheck: return "Count check"
        case .shiftSummary: return "Shift summary"
        }
    }

    var systemImage: String {
        switch kind {
        case .purchaseOrder: return "cart"
        case .replenishment: return "shippingbox"
        case .coldChainAlert: return "thermometer.snowflake"
        case .countCheck: return "checklist"
        case .shiftSummary: return "text.alignleft"
        }
    }

    // MARK: - Reading what Nomad wrote

    /// A list field. Nomad keeps a whole-value reference as JSON (a real list), but a list that
    /// arrives as JSON text is read too.
    private static func list(_ raw: Any?) -> [[String: Any]] {
        (value(raw) as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }
    private static func value(_ raw: Any?) -> Any? {
        if let s = raw as? String, let data = s.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: data) {
            return parsed
        }
        return raw
    }
    private static func text(_ raw: Any?) -> String { raw as? String ?? "" }
    private static func number(_ raw: Any?) -> Double? {
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s) }
        return nil
    }
    private static func int(_ raw: Any?) -> Int { Int(number(raw) ?? 0) }
}
