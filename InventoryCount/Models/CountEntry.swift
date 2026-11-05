//  CountEntry.swift
//  One row of the inventory sheet — a document of type "count" in inventory.counts.
//  Document IDs embed the capturing device, so two devices never write the same doc:
//  "same bin counted twice" shows up as two rows (flagged in Summary), never a doc conflict.

import Foundation

enum CaptureSource: String, Codable, CaseIterable, Identifiable {
    case voice, text, photo, code
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .voice: return "mic"
        case .text:  return "text.cursor"
        case .photo: return "camera"
        case .code:  return "barcode.viewfinder"
        }
    }
}

enum EntryKind: String, Codable { case entry, summary }

struct ItemLocation: Codable, Hashable {
    var site = ""
    var rack = ""
    var shelf = ""
    var bin = ""

    var isEmpty: Bool { site.isEmpty && rack.isEmpty && shelf.isEmpty && bin.isEmpty }
    /// "Location X / A / S2 / B15"
    var display: String {
        let parts = [site, rack, shelf, bin].filter { !$0.isEmpty }
        return parts.isEmpty ? "Unspecified" : parts.joined(separator: " / ")
    }
    /// "Rack · Shelf · Bin" chip text
    var chip: String {
        let parts = [rack, shelf, bin].filter { !$0.isEmpty }
        return parts.isEmpty ? (site.isEmpty ? "Set location" : site) : parts.joined(separator: " · ")
    }
    var dictionary: [String: Any] { ["site": site, "rack": rack, "shelf": shelf, "bin": bin] }
    init(site: String = "", rack: String = "", shelf: String = "", bin: String = "") {
        self.site = site; self.rack = rack; self.shelf = shelf; self.bin = bin
    }
    init(dictionary d: [String: Any]?) {
        site = d?["site"] as? String ?? ""; rack = d?["rack"] as? String ?? ""
        shelf = d?["shelf"] as? String ?? ""; bin = d?["bin"] as? String ?? ""
    }
    /// Parse "Location X / A / S2 / B15" or free text back into parts.
    init(parsing text: String) {
        let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        self.init(site: parts.count > 0 ? parts[0] : "", rack: parts.count > 1 ? parts[1] : "",
                  shelf: parts.count > 2 ? parts[2] : "", bin: parts.count > 3 ? parts[3] : "")
    }
}

struct ScannedCode: Codable, Hashable {
    enum Kind: String, Codable { case qr, upc, ean }
    var type: Kind
    var value: String
    var dictionary: [String: Any] { ["type": type.rawValue, "value": value] }
    init(type: Kind, value: String) { self.type = type; self.value = value }
    init?(dictionary d: [String: Any]?) {
        guard let d, let t = d["type"] as? String, let k = Kind(rawValue: t), let v = d["value"] as? String else { return nil }
        type = k; value = v
    }
}

struct CountEntry: Identifiable, Hashable {
    static let docType = "count"

    var id: String
    var kind: EntryKind
    var team: String
    var itemName: String
    var count: Int
    var countIsEstimate: Bool
    var attributes: String        // size / shape / color
    var annotation: String
    var location: ItemLocation
    var source: CaptureSource
    var code: ScannedCode?
    var storeID: String?          // the store counted, for a store team (equals team)
    var sku: String?              // the store product this row is, when it matched one
    var confidence: Int           // 0–100 from the model; < 60 → needs review
    var needsReview: Bool
    var capturedAt: Date
    /// captured_at exactly as stored, written back unchanged: the counts rule refuses any change.
    var capturedAtText: String? = nil
    var capturedBy: String        // device id
    var capturedByName: String
    var hasPhoto: Bool

    static func newID() -> String { "count::\(AppConfig.deviceID)::\(UUID().uuidString.lowercased())" }

    init(id: String = CountEntry.newID(),
         kind: EntryKind = .entry,
         team: String = AppConfig.currentTeam,
         itemName: String,
         count: Int,
         countIsEstimate: Bool = false,
         attributes: String = "",
         annotation: String = "",
         location: ItemLocation,
         source: CaptureSource,
         code: ScannedCode? = nil,
         storeID: String? = nil,
         sku: String? = nil,
         confidence: Int = 100,
         needsReview: Bool = false,
         capturedAt: Date = Date(),
         capturedBy: String = AppConfig.deviceID,
         capturedByName: String = AppConfig.deviceName,
         hasPhoto: Bool = false) {
        self.id = id; self.kind = kind; self.team = team; self.itemName = itemName; self.count = count
        self.countIsEstimate = countIsEstimate; self.attributes = attributes; self.annotation = annotation
        self.location = location; self.source = source; self.code = code; self.confidence = confidence
        self.storeID = storeID; self.sku = sku
        self.needsReview = needsReview; self.capturedAt = capturedAt; self.capturedBy = capturedBy
        self.capturedByName = capturedByName; self.hasPhoto = hasPhoto
    }

    init?(id: String, dictionary d: [String: Any]) {
        guard (d["type"] as? String) == CountEntry.docType,
              let itemName = d["item_name"] as? String else { return nil }
        self.id = id
        kind = EntryKind(rawValue: d["kind"] as? String ?? "entry") ?? .entry
        team = d["team"] as? String ?? AppConfig.defaultTeam
        self.itemName = itemName
        count = (d["count"] as? NSNumber)?.intValue ?? 0
        countIsEstimate = d["count_is_estimate"] as? Bool ?? false
        attributes = d["attributes"] as? String ?? ""
        annotation = d["annotation"] as? String ?? ""
        location = ItemLocation(dictionary: d["location"] as? [String: Any])
        source = CaptureSource(rawValue: d["source"] as? String ?? "text") ?? .text
        code = ScannedCode(dictionary: d["code"] as? [String: Any])
        storeID = d["store_id"] as? String
        sku = d["sku"] as? String
        confidence = (d["confidence"] as? NSNumber)?.intValue ?? 100
        needsReview = d["needs_review"] as? Bool ?? false
        let capturedText = d["captured_at"] as? String
        capturedAt = capturedText.flatMap(ISO8601DateFormatter.cblDate) ?? Date()
        capturedAtText = capturedText
        capturedBy = d["captured_by"] as? String ?? ""
        capturedByName = d["captured_by_name"] as? String ?? ""
        hasPhoto = d["photo"] != nil
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": CountEntry.docType,
            "kind": kind.rawValue,
            "team": team,
            "item_name": itemName,
            "count": count,
            "count_is_estimate": countIsEstimate,
            "attributes": attributes,
            "annotation": annotation,
            "location": location.dictionary,
            "source": source.rawValue,
            "confidence": confidence,
            "needs_review": needsReview,
            "captured_at": capturedAtText ?? ISO8601DateFormatter.cbl.string(from: capturedAt),
            "captured_by": capturedBy,
            "captured_by_name": capturedByName,
        ]
        if let code { dict["code"] = code.dictionary }
        if let storeID { dict["store_id"] = storeID }
        if let sku { dict["sku"] = sku }
        return dict
    }

    var countDisplay: String { (countIsEstimate ? "≈" : "") + "\(count)" }
    /// "≈×12" / "×30" for row trailers.
    var countBadge: String { (countIsEstimate ? "≈×" : "×") + "\(count)" }
}

extension ISO8601DateFormatter {
    static let cbl: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    /// The same without fractional seconds, as other writers (the Query Workbench, scripts) store it.
    static let cblWholeSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    /// A stored timestamp, with or without fractional seconds.
    static func cblDate(_ text: String) -> Date? {
        cbl.date(from: text) ?? cblWholeSeconds.date(from: text)
    }
}
