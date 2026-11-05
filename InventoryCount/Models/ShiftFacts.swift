//  ShiftFacts.swift
//  The store facts behind the end-of-shift summary, worked out on the phone so the on-device model
//  only narrates them: the crew's counts against the store system, what is out or low, and what
//  Nomad approved for the store. Pure: no database, so it can be checked on its own.

import Foundation

struct ShiftFacts {
    struct Gap: Hashable {
        var itemName: String      // the store item, as the store system names it
        var counted: Int
        var system: Int
        var estimate: Bool
        var byClosestName: Bool   // matched by the closest name, not by barcode or exact name
        var gap: Int { counted - system }
    }

    var compared = 0              // store items counted (latest count of each)
    var matching = 0
    var gaps: [Gap] = []          // differences, largest first
    var notInSystem = 0           // counted rows that are not store items
    var out = 0
    var low = 0
    var decisions: [String] = []  // one plain line per approved Nomad decision

    /// The latest count of each store item is compared with its record; rows that are not store
    /// items are left out of the comparison.
    static func make(entries: [CountEntry], store: String, stock: [StockRecord], decisions: [ProposalDoc],
                     match: (CountEntry) -> StockMatch) -> ShiftFacts {
        var facts = ShiftFacts()
        var latest: [String: (CountEntry, StockRecord, Bool)] = [:]
        for e in entries where e.kind == .entry {
            let m = match(e)
            guard let record = m.record else { facts.notInSystem += 1; continue }
            var closest = false
            if case .closest = m { closest = true }
            if let seen = latest[record.sku], seen.0.capturedAt >= e.capturedAt { continue }
            latest[record.sku] = (e, record, closest)
        }
        for (e, record, closest) in latest.values {
            facts.compared += 1
            if e.count == record.onHand { facts.matching += 1; continue }
            facts.gaps.append(Gap(itemName: record.itemName, counted: e.count, system: record.onHand,
                                  estimate: e.countIsEstimate, byClosestName: closest))
        }
        facts.gaps.sort { abs($0.gap) != abs($1.gap) ? abs($0.gap) > abs($1.gap) : $0.itemName < $1.itemName }
        let mine = stock.filter { $0.storeID == store }
        facts.out = mine.filter { $0.status == .outOfStock }.count
        facts.low = mine.filter { $0.status == .lowStock }.count
        facts.decisions = decisions.filter { $0.kind != .shiftSummary }.map { line(for: $0, store: store) }
        return facts
    }

    static func line(for p: ProposalDoc, store: String) -> String {
        switch p.kind {
        case .purchaseOrder:
            let units = p.lines.reduce(0) { $0 + $1.orderQuantity }
            let out = p.lines.filter { $0.onHand == 0 }.count
            return "purchase order of \(p.lines.count) lines, \(units) units (\(out) out of stock)"
        case .replenishment:
            let mine = p.transfers(to: store)
            return "\(mine.count) transfers from the DC, \(mine.reduce(0) { $0 + $1.unitsPerStore }) units"
        case .countCheck:
            let recounts = p.findings.filter { $0.action == "recount" }.count
            return "count check: \(recounts) to recount, \(p.findings.count - recounts) to restock"
        case .shiftSummary:
            return "shift summary"
        case .coldChainAlert:
            let trucks = p.alerts.map { "\($0.truckID) \(String(format: "%+.0f", $0.driftF)) F (\($0.severity))" }
            return "cold-chain alert: " + trucks.joined(separator: ", ")
        }
    }

    /// The lines added to the summary prompt's facts.
    var promptLines: [String] {
        var lines = ["- Counted against the store system: \(compared) store item(s), \(matching) match the system, \(gaps.count) differ."]
        if !gaps.isEmpty {
            let top = gaps.prefix(5).map { g in
                "\(g.itemName): counted \(g.estimate ? "about " : "")\(g.counted), system \(g.system) (\(g.gap > 0 ? "+" : "")\(g.gap))"
                    + (g.byClosestName ? ", matched by name" : "")
            }
            lines.append("- Largest differences: " + top.joined(separator: "; ") + ".")
        }
        lines.append("- The store system shows \(out) item(s) out of stock and \(low) low.")
        lines.append("- Approved by Nomad for this store: " + (decisions.isEmpty ? "nothing yet" : decisions.joined(separator: "; ")) + ".")
        return lines
    }
}
