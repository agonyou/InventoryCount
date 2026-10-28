//  CSVExporter.swift
//  Writes the sheet (one row per count entry) to CSV for the system share sheet.

import Foundation

enum CSVExporter {
    static let header = ["Item name", "Count", "Estimate", "Size · shape · color", "Annotation", "Site", "Rack", "Shelf", "Bin",
                         "Source", "Code type", "Code", "Confidence", "Needs review", "Captured at", "Captured by"]

    static func csv(for entries: [CountEntry]) -> String {
        let f = ISO8601DateFormatter.cbl
        var lines = [header.map(escape).joined(separator: ",")]
        for e in entries where e.kind == .entry {
            lines.append([e.itemName, String(e.count), e.countIsEstimate ? "yes" : "", e.attributes, e.annotation,
                          e.location.site, e.location.rack, e.location.shelf, e.location.bin,
                          e.source.rawValue, e.code?.type.rawValue ?? "", e.code?.value ?? "",
                          String(e.confidence), e.needsReview ? "yes" : "", f.string(from: e.capturedAt), e.capturedByName]
                .map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func writeTemporaryFile(for entries: [CountEntry], name: String = "tally-sheet") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).csv")
        try csv(for: entries).data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private static func escape(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
}
