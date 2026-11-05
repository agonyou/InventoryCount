//  StoreProduct.swift
//  Store-system products in inventory.catalog (sku, name, code; no team), written by the store
//  system's data load and read-only on the phone. A count that matches one carries its sku, and
//  on a store team (team "store-…") the store_id, so Nomad's Count check can compare it with the
//  store's stock record.

import Foundation

struct StoreProduct: Identifiable, Hashable {
    var id: String            // "catalogue::upc::<UPC>"
    var sku: String
    var name: String
    var brand: String
    var department: String
    var category: String
    var unitPrice: Double?
    var code: ScannedCode?

    init?(id: String, dictionary d: [String: Any]) {
        guard d["team"] == nil, let sku = d["sku"] as? String, !sku.isEmpty,
              let name = d["name"] as? String, !name.isEmpty else { return nil }
        self.id = id; self.sku = sku; self.name = name
        brand = d["brand"] as? String ?? ""
        department = d["department"] as? String ?? ""
        category = d["category"] as? String ?? ""
        unitPrice = (d["unit_price"] as? NSNumber)?.doubleValue
        code = ScannedCode(dictionary: d["code"] as? [String: Any])
    }
}

// MARK: - GTIN

/// Item identity across the scanner, the team catalog and the store system: GTIN-13 digits.
/// UPC-A gains a leading 0, UPC-E is expanded to UPC-A first, EAN-8 and GTIN-14 are padded or
/// trimmed. Anything that is not digits of a known length has no GTIN.
enum GTIN {
    static func normalize(_ code: ScannedCode) -> String? {
        guard code.type != .qr else { return nil }
        if code.type == .upc, (6...8).contains(code.value.count), let upcA = expandUPCE(code.value) {
            return "0" + upcA
        }
        return normalize(code.value)
    }

    /// A code as the store system sends it (no symbology): 8, 12, 13 or 14 digits.
    static func normalize(_ text: String) -> String? {
        let v = text.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, v.allSatisfy(\.isASCIIDigit) else { return nil }
        switch v.count {
        case 8, 12: return String(repeating: "0", count: 13 - v.count) + v
        case 13: return v
        case 14: return v.hasPrefix("0") ? String(v.dropFirst()) : nil
        default: return nil
        }
    }

    /// UPC-E (6 digits, 7 with the number system, 8 with the check digit) → 12-digit UPC-A.
    static func expandUPCE(_ text: String) -> String? {
        guard text.allSatisfy(\.isASCIIDigit) else { return nil }
        let digits = text.map { String($0) }
        let numberSystem: String
        let body: [String]
        switch digits.count {
        case 6: numberSystem = "0"; body = digits
        case 7, 8: numberSystem = digits[0]; body = Array(digits[1...6])
        default: return nil
        }
        guard numberSystem == "0" || numberSystem == "1" else { return nil }
        let d = body
        let manufacturer: String, product: String
        switch d[5] {
        case "0", "1", "2": manufacturer = d[0] + d[1] + d[5] + "00"; product = "00" + d[2] + d[3] + d[4]
        case "3":           manufacturer = d[0] + d[1] + d[2] + "00"; product = "000" + d[3] + d[4]
        case "4":           manufacturer = d[0] + d[1] + d[2] + d[3] + "0"; product = "0000" + d[4]
        default:            manufacturer = d[0...4].joined(); product = "0000" + d[5]
        }
        let eleven = numberSystem + manufacturer + product
        let check = checkDigit(eleven)
        if digits.count == 8, digits[7] != check { return nil }
        return eleven + check
    }

    /// GS1 check digit for the digits before it.
    static func checkDigit(_ digits: String) -> String {
        let sum = digits.reversed().enumerated().reduce(0) { total, pair in
            total + (Int(String(pair.element)) ?? 0) * (pair.offset % 2 == 0 ? 3 : 1)
        }
        return String((10 - sum % 10) % 10)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

