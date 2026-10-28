//  CatalogueItem.swift
//  On-device UPC/EAN → product name catalogue (type "catalogue_item"), team-shared and synced.
//  First scan of an unknown code asks for a name; later scans reuse it.

import Foundation

struct CatalogueItem: Identifiable, Hashable {
    static let docType = "catalogue_item"
    var id: String            // "catalogue::<type>::<value>"
    var team: String
    var code: ScannedCode
    var name: String
    var attributes: String
    var capturedBy: String
    var capturedAt: Date

    static func id(for code: ScannedCode) -> String { "catalogue::\(code.type.rawValue)::\(code.value)" }

    init(code: ScannedCode, name: String, attributes: String = "", team: String = AppConfig.defaultTeam) {
        id = CatalogueItem.id(for: code); self.team = team; self.code = code; self.name = name
        self.attributes = attributes; capturedBy = AppConfig.deviceID; capturedAt = Date()
    }
    init?(id: String, dictionary d: [String: Any]) {
        guard (d["type"] as? String) == CatalogueItem.docType,
              let code = ScannedCode(dictionary: d["code"] as? [String: Any]),
              let name = d["name"] as? String else { return nil }
        self.id = id; self.code = code; self.name = name
        team = d["team"] as? String ?? AppConfig.defaultTeam
        attributes = d["attributes"] as? String ?? ""
        capturedBy = d["captured_by"] as? String ?? ""
        capturedAt = ISO8601DateFormatter.cbl.date(from: d["captured_at"] as? String ?? "") ?? Date()
    }
    func toDictionary() -> [String: Any] {
        ["type": CatalogueItem.docType, "team": team, "code": code.dictionary, "name": name,
         "attributes": attributes, "captured_by": capturedBy,
         "captured_at": ISO8601DateFormatter.cbl.string(from: capturedAt)]
    }
}
