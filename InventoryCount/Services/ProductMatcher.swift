//  ProductMatcher.swift
//  Closest-name matching of a spoken or typed item ("eight orange juice five pack") against the
//  store's own items ("Coca-Cola 100% Orange Juice with Calcium (Pack 5)"). Word-based: filler
//  words, plurals and number words are normalized, and "(Pack 5)" becomes a pack token. It picks
//  one item only when one clearly fits best; when several fit equally (pack sizes of the same
//  product) it says how many, and the counter scans or says the pack size.

import Foundation

enum ProductMatcher {
    enum Result<Item> {
        case one(Item)
        case several(Int)
        case none
    }

    static func match<Item>(_ spoken: String, in items: [Item], name: (Item) -> String) -> Result<Item> {
        match(spoken, in: items.map { ($0, tokens(name($0))) })
    }

    /// The same, against names already split into words (cache them: this runs on every render).
    static func match<Item>(_ spoken: String, in candidates: [(item: Item, words: Set<String>)]) -> Result<Item> {
        let said = tokens(spoken)
        guard !said.isEmpty else { return .none }
        let scored: [(item: Item, score: Double)] = candidates.compactMap { candidate in
            let item = candidate.item
            let product = candidate.words
            guard !product.isEmpty else { return nil }
            let matched = said.filter { product.contains($0) }.count
            let coverage = Double(matched) / Double(said.count)
            // Every word said must be in the name, or nearly every one for a long phrase.
            guard said.count <= 2 ? coverage == 1 : coverage >= 0.75 else { return nil }
            let precision = Double(matched) / Double(product.count)
            return (item, coverage + 0.5 * precision)
        }
        .sorted { $0.score > $1.score }
        guard let best = scored.first else { return .none }
        let tied = scored.filter { best.score - $0.score < 0.15 }
        return tied.count == 1 ? .one(best.item) : .several(tied.count)
    }

    // MARK: - Normalizing

    private static let filler: Set<String> = [
        "a", "an", "the", "of", "with", "and", "for", "in", "on", "ct", "count", "oz", "lb", "lbs", "pk",
        "bottle", "bottles", "box", "boxes", "can", "cans", "jar", "jars", "unit", "units", "item", "items",
    ]
    private static let numbers: [String: String] = [
        "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8",
        "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "fifteen": "15", "sixteen": "16",
        "seventeen": "17", "eighteen": "18", "twenty": "20", "twentyfour": "24", "thirty": "30",
    ]

    /// The words that tell items apart. "pack 5", "5 pack", "five pack" and "(Pack 5)" all give "pack5".
    static func tokens(_ text: String) -> Set<String> {
        let words = text.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "twenty four", with: "twentyfour")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { numbers[$0] ?? $0 }
        var out: Set<String> = []
        var i = 0
        while i < words.count {
            let w = words[i]
            if w == "pack", i + 1 < words.count, Int(words[i + 1]) != nil {
                out.insert("pack" + words[i + 1]); i += 2; continue
            }
            if Int(w) != nil, i + 1 < words.count, words[i + 1] == "pack" {
                out.insert("pack" + w); i += 2; continue
            }
            // A bare number is the count itself ("eight orange juice"), not part of the name.
            if Int(w) == nil, !filler.contains(w), w != "pack" { out.insert(singular(w)) }
            i += 1
        }
        return out
    }

    private static func singular(_ w: String) -> String {
        if w.count > 4, w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.count > 4, w.hasSuffix("es"), ["s", "x", "z", "ch", "sh"].contains(where: { w.dropLast(2).hasSuffix($0) }) {
            return String(w.dropLast(2))
        }
        if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") { return String(w.dropLast()) }
        return w
    }
}
