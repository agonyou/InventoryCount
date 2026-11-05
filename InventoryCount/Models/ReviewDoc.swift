//  ReviewDoc.swift
//  A review Nomad saved in inventory.reviews (type "review"): a reconciliation proposal or a digest.

import Foundation

struct ReviewDoc: Identifiable, Hashable {
    static let docType = "review"

    struct Resolution: Hashable {
        var itemName: String
        var location: ItemLocation
        var proposedCount: Int
        var confidence: String
        var reason: String
        var keepKey: String
        var supersedeKeys: [String]

        init?(dictionary d: [String: Any]) {
            guard let itemName = d["item_name"] as? String,
                  let proposed = (d["proposed_count"] as? NSNumber)?.intValue else { return nil }
            self.itemName = itemName
            location = ItemLocation(site: d["site"] as? String ?? "", rack: d["rack"] as? String ?? "",
                                    shelf: d["shelf"] as? String ?? "", bin: d["bin"] as? String ?? "")
            proposedCount = proposed
            confidence = d["confidence"] as? String ?? ""
            reason = d["reason"] as? String ?? ""
            keepKey = d["keep_key"] as? String ?? ""
            supersedeKeys = d["supersede_keys"] as? [String] ?? []
        }
    }

    var id: String
    var kind: String          // "reconciliation" | "digest"
    var team: String
    var site: String
    var day: String
    var status: String
    var summary: String
    var digest: String
    var resolutions: [Resolution]

    init?(id: String, dictionary d: [String: Any]) {
        guard (d["type"] as? String) == ReviewDoc.docType, let kind = d["kind"] as? String else { return nil }
        self.id = id
        self.kind = kind
        team = d["team"] as? String ?? ""
        site = d["site"] as? String ?? ""
        day = d["day"] as? String ?? ""
        status = d["status"] as? String ?? ""
        summary = d["summary"] as? String ?? ""
        digest = d["digest"] as? String ?? ""
        resolutions = (d["resolutions"] as? [Any] ?? []).compactMap { item in
            (item as? [String: Any]).flatMap { Resolution(dictionary: $0) }
        }
    }
}
