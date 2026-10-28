//  LocationRef.swift
//  Shared read-only reference document (type "location") in inventory.locations.

import Foundation

struct LocationRef: Identifiable, Hashable {
    static let docType = "location"
    var id: String
    var location: ItemLocation
    var qr: String          // optional QR payload that selects this location
    var notes: String

    init(id: String = "location::" + UUID().uuidString.lowercased(), location: ItemLocation, qr: String = "", notes: String = "") {
        self.id = id; self.location = location; self.qr = qr; self.notes = notes
    }
    init?(id: String, dictionary d: [String: Any]) {
        guard (d["type"] as? String) == LocationRef.docType else { return nil }
        self.id = id
        location = ItemLocation(dictionary: d["location"] as? [String: Any])
        if location.isEmpty, let name = d["name"] as? String { location = ItemLocation(parsing: name) }
        qr = d["qr"] as? String ?? ""
        notes = d["notes"] as? String ?? ""
    }
    func toDictionary() -> [String: Any] {
        ["type": LocationRef.docType, "name": location.display, "location": location.dictionary, "qr": qr, "notes": notes]
    }
}
