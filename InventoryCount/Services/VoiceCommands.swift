//  VoiceCommands.swift
//  Spoken commands that split dictation into bins/shelves/racks without touching the phone.
//  Recognised at the END of a finished utterance (the words before it are the items for the
//  current location):
//    "next bin" / "next shelf" / "next rack"        → advance that part
//    "bin 15" / "bin fifteen", "shelf 2", "rack B",
//    "site Location X" / "location Location X"      → set that part
//    "done" / "stop listening" / "that's all"       → stop
//    "scratch that" / "undo that"                   → undo last saved row

import Foundation

enum VoiceCommand: Equatable {
    case nextBin, nextShelf, nextRack
    case setBin(String), setShelf(String), setRack(String), setSite(String)
    case stop, undo
}

struct VoiceCommandMatch {
    let command: VoiceCommand
    let itemsText: String      // what was said before the command
}

enum VoiceCommands {
    private static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
    ]

    /// Normalise "twenty one" → "21", "b" → "B"; keep letters/digits.
    private static func value(_ raw: String) -> String {
        let words = raw.lowercased().split(separator: " ").map(String.init)
        var total = 0, sawNumber = false
        for w in words {
            if let n = Int(w) { total += n; sawNumber = true }
            else if let n = numberWords[w] { total += n; sawNumber = true }
        }
        if sawNumber { return String(total) }
        return raw.trimmingCharacters(in: .whitespaces).uppercased()
    }

    static func detect(in utterance: String) -> VoiceCommandMatch? {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        // Terminal commands (whole utterance or trailing)
        let stops = ["stop listening", "that's all", "that is all", "all done", "done"]
        for s in stops where lower == s || lower.hasSuffix(" " + s) {
            return VoiceCommandMatch(command: .stop, itemsText: String(text.dropLast(s.count)).trimmingCharacters(in: .whitespaces))
        }
        for s in ["scratch that", "undo that", "undo"] where lower == s || lower.hasSuffix(" " + s) {
            return VoiceCommandMatch(command: .undo, itemsText: String(text.dropLast(s.count)).trimmingCharacters(in: .whitespaces))
        }
        // "next bin|shelf|rack" at the end
        let nextPattern = try! NSRegularExpression(pattern: #"(?:^|\s)next\s+(bin|shelf|rack)\s*[.!]?$"#, options: [.caseInsensitive])
        if let m = nextPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range, in: text), let part = Range(m.range(at: 1), in: text) {
            let items = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            switch text[part].lowercased() {
            case "bin": return VoiceCommandMatch(command: .nextBin, itemsText: items)
            case "shelf": return VoiceCommandMatch(command: .nextShelf, itemsText: items)
            default: return VoiceCommandMatch(command: .nextRack, itemsText: items)
            }
        }
        // "bin 15" / "shelf two" / "rack B" / "site X" / "location X" at the end (value = 1–3 tokens)
        let setPattern = try! NSRegularExpression(
            pattern: #"(?:^|\s)(bin|shelf|rack|site|location)\s+((?:[a-z0-9]+\s?){1,3})[.!]?$"#, options: [.caseInsensitive])
        if let m = setPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range, in: text), let part = Range(m.range(at: 1), in: text), let val = Range(m.range(at: 2), in: text) {
            let items = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let v = value(String(text[val]))
            switch text[part].lowercased() {
            case "bin": return VoiceCommandMatch(command: .setBin(v), itemsText: items)
            case "shelf": return VoiceCommandMatch(command: .setShelf(v), itemsText: items)
            case "rack": return VoiceCommandMatch(command: .setRack(v), itemsText: items)
            default: return VoiceCommandMatch(command: .setSite(String(text[val]).trimmingCharacters(in: .whitespaces)), itemsText: items)
            }
        }
        return nil
    }

    /// Apply a location command. "next" increments the trailing number of that part (B15 → B16).
    static func apply(_ command: VoiceCommand, to location: inout ItemLocation) {
        func bump(_ s: String, fallback: String) -> String {
            let digits = s.filter(\.isNumber)
            if let n = Int(digits) { return s.prefix { !$0.isNumber } + String(n + 1) }
            return s.isEmpty ? fallback : s + "+"
        }
        switch command {
        case .nextBin: location.bin = bump(location.bin, fallback: "B1")
        case .nextShelf: location.shelf = bump(location.shelf, fallback: "S1"); location.bin = location.bin.isEmpty ? "" : "B1"
        case .nextRack: location.rack = bump(location.rack, fallback: "A"); location.shelf = location.shelf.isEmpty ? "" : "S1"; location.bin = location.bin.isEmpty ? "" : "B1"
        case .setBin(let v): location.bin = v.first?.isNumber == true ? "B" + v : v
        case .setShelf(let v): location.shelf = v.first?.isNumber == true ? "S" + v : v
        case .setRack(let v): location.rack = v
        case .setSite(let v): location.site = v
        case .stop, .undo: break
        }
    }
}
