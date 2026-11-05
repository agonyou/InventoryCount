//  CatalogItem.swift
//  On-device UPC/EAN → product name catalog (type "catalog_item"), team-shared and synced.
//  First scan of an unknown code asks for a name; later scans reuse it.

import Foundation

struct CatalogItem: Identifiable, Hashable {
    static let docType = "catalog_item"
    var id: String            // "catalog::<type>::<value>"
    var team: String
    var code: ScannedCode
    var name: String
    var attributes: String
    var capturedBy: String
    var capturedAt: Date

    static func id(for code: ScannedCode) -> String { "catalog::\(code.type.rawValue)::\(code.value)" }

    init(code: ScannedCode, name: String, attributes: String = "", team: String = AppConfig.currentTeam) {
        id = CatalogItem.id(for: code); self.team = team; self.code = code; self.name = name
        self.attributes = attributes; capturedBy = AppConfig.deviceID; capturedAt = Date()
    }
    init?(id: String, dictionary d: [String: Any]) {
        guard (d["type"] as? String) == CatalogItem.docType,
              let code = ScannedCode(dictionary: d["code"] as? [String: Any]),
              let name = d["name"] as? String else { return nil }
        self.id = id; self.code = code; self.name = name
        team = d["team"] as? String ?? AppConfig.defaultTeam
        attributes = d["attributes"] as? String ?? ""
        capturedBy = d["captured_by"] as? String ?? ""
        capturedAt = ISO8601DateFormatter.cblDate(d["captured_at"] as? String ?? "") ?? Date()
    }
    func toDictionary() -> [String: Any] {
        ["type": CatalogItem.docType, "team": team, "code": code.dictionary, "name": name,
         "attributes": attributes, "captured_by": capturedBy,
         "captured_at": ISO8601DateFormatter.cbl.string(from: capturedAt)]
    }
}
