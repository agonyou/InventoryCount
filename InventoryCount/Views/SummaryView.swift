//  SummaryView.swift
//  Stat tiles, model-written two-paragraph summary, Flagged list, Regenerate / Share.

import SwiftUI

struct SummaryView: View {
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var model: InventoryModel
    @State private var summary = ""
    @State private var modelName = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var shareURL: URL?

    private var rows: [CountEntry] { database.entries.filter { $0.kind == .entry } }
    private var distinct: Int { Set(rows.map { $0.itemName.lowercased() }).count }
    private var units: Int { rows.reduce(0) { $0 + $1.count } }
    /// For a store team: counts against the store system, out/low and Nomad's decisions.
    /// This store's counts of today only: not other crews' rows from peers, not earlier shifts.
    private var storeFacts: ShiftFacts? {
        guard let store = AppConfig.currentStoreID else { return nil }
        let today = rows.filter { ($0.storeID ?? $0.team) == store && Calendar.current.isDateInToday($0.capturedAt) }
        return ShiftFacts.make(entries: today, store: store, stock: database.stock(store: store),
                               decisions: database.nomadDecisions(store: store), match: database.stockMatch(for:))
    }

    var body: some View {
        let facts = storeFacts   // worked out once per render
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Summary", subtitle: modelName.isEmpty ? nil : "Written by \(modelName)")
                HStack(spacing: 10) {
                    StatTile(value: "\(distinct)", label: "Distinct items")
                    StatTile(value: "\(units)", label: "Units counted")
                    StatTile(value: "\(database.flagged.count)", label: "Need review", tint: database.flagged.isEmpty ? CDS.ink : CDS.amber)
                }
                if let facts { againstTheSystem(facts) }
                if let store = AppConfig.currentStoreID {
                    nomadSummary(store)
                } else {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Summary")
                        if isLoading { ProgressView("Writing summary…").font(CDS.body(13)) }
                        else if let error { Text(error).font(CDS.body(13)).foregroundStyle(CDS.red700) }
                        else if summary.isEmpty { Text("Nothing to summarize yet.").font(CDS.body(14)).foregroundStyle(CDS.inkSecondary) }
                        else { Text(summary).font(CDS.body(15)).foregroundStyle(CDS.ink).lineSpacing(3).textSelection(.enabled) }
                    }
                }
                }
                flagged
                nomadReviews
                HStack(spacing: 10) {
                    if AppConfig.currentStoreID == nil {
                        Button { Task { await load() } } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                            .buttonStyle(PillButtonStyle()).disabled(isLoading || rows.isEmpty)
                    }
                    Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PillButtonStyle(prominent: true)).disabled(summary.isEmpty && facts == nil)
                }
            }
            .padding(16)
        }
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // A store's summary comes from Nomad; the phone writes one only for a crew that is not a store.
        .task(id: rows.count) { if AppConfig.currentStoreID == nil && summary.isEmpty && !isLoading { await load() } }
        .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
    }

    /// The store's newest approved Shift summary, written by Nomad from every phone's counts.
    private func shiftSummary(_ store: String) -> ProposalDoc? {
        database.proposals.filter { $0.kind == .shiftSummary && $0.storeID == store }.max { $0.day < $1.day }
    }

    private func nomadSummary(_ store: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                if let s = shiftSummary(store) {
                    HStack {
                        Eyebrow(text: "Summary · Nomad · \(s.day)")
                        Spacer()
                        Badge(text: "Approved", color: CDS.success)
                    }
                    Text(s.summary).font(CDS.body(15)).foregroundStyle(CDS.ink).lineSpacing(3).textSelection(.enabled)
                    ForEach(s.highlights, id: \.self) { h in
                        Label(h, systemImage: "arrow.right.circle").font(CDS.body(13, weight: .semibold)).foregroundStyle(CDS.ink)
                    }
                } else {
                    Eyebrow(text: "Summary · Nomad")
                    Text("Nomad writes the end-of-shift summary from every phone's counts at \(store). It appears here once a manager runs Shift summary in Nomad and approves it.")
                        .font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
                }
            }
        }
    }

    private func againstTheSystem(_ facts: ShiftFacts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                StatTile(value: "\(facts.matching)", label: "Match the system", tint: CDS.success)
                StatTile(value: "\(facts.gaps.count)", label: "Differ", tint: facts.gaps.isEmpty ? CDS.ink : CDS.amber)
                StatTile(value: "\(facts.out) · \(facts.low)", label: "Out · low in store", tint: facts.out == 0 ? CDS.ink : CDS.red700)
            }
            if !facts.gaps.isEmpty {
                Eyebrow(text: "Against the system")
                ForEach(facts.gaps.prefix(5), id: \.self) { g in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.itemName).font(CDS.body(14, weight: .semibold)).foregroundStyle(CDS.ink)
                            Text("Counted \(g.estimate ? "≈" : "")\(g.counted) · system \(g.system)\(g.byClosestName ? " · matched by name" : "")")
                                .font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                        }
                        Spacer()
                        Text("\(g.gap > 0 ? "+" : "−")\(abs(g.gap))").font(CDS.mono(15, weight: .medium)).foregroundStyle(CDS.amber)
                    }
                    .padding(12)
                    .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
                }
            }
            if !facts.decisions.isEmpty {
                Text("Nomad approved: " + facts.decisions.joined(separator: "; ") + ".")
                    .font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
            }
        }
    }

    private var flagged: some View {
        Group {
            let f = database.flagged
            let dupIDs = Set(database.duplicateGroups().flatMap { $0 }.map(\.id))
            if !f.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Flagged")
                    ForEach(f) { e in
                        HStack(spacing: 10) {
                            Image(systemName: dupIDs.contains(e.id) ? "doc.on.doc" : (e.countIsEstimate ? "approxequal" : "exclamationmark.triangle"))
                                .foregroundStyle(CDS.amber).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.itemName).font(CDS.body(14, weight: .semibold)).foregroundStyle(CDS.ink)
                                Text(dupIDs.contains(e.id) ? "Also counted by another device at \(e.location.chip)"
                                     : e.countIsEstimate ? "Estimated count" : "Low confidence (\(e.confidence)%)")
                                    .font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                            }
                            Spacer()
                            Text(e.countBadge).font(CDS.mono(14, weight: .medium)).foregroundStyle(CDS.amber)
                        }
                        .padding(12)
                        .background(CDS.amberTint, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.amberSoft))
                    }
                }
            }
        }
    }

    private var nomadReviews: some View {
        Group {
            let mine = database.reviews.filter { $0.team == AppConfig.currentTeam }
            let proposed = mine.filter { $0.kind == "reconciliation" && $0.status == "proposed" }
            // One card per site: the newest proposal for each (reviews arrive newest day first).
            let perSite = proposed.filter { r in proposed.first(where: { $0.site == r.site })?.id == r.id }
            ForEach(perSite) { review in
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Nomad flagged \(review.resolutions.count) group\(review.resolutions.count == 1 ? "" : "s") · \(review.site.isEmpty ? "" : "\(review.site) · ")\(review.day)")
                    if !review.summary.isEmpty {
                        Text(review.summary).font(CDS.body(13)).foregroundStyle(CDS.ink)
                    }
                    ForEach(review.resolutions, id: \.self) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.itemName) · \(r.location.chip)").font(CDS.body(14, weight: .semibold)).foregroundStyle(CDS.ink)
                            Text("Proposed \(r.proposedCount) (\(r.confidence)) — \(r.reason)").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
                    }
                }
            }
            if let digest = mine.first(where: { $0.kind == "digest" }), !digest.digest.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Nomad digest · \(digest.day)")
                        Text(digest.digest).font(CDS.body(13)).foregroundStyle(CDS.ink)
                    }
                }
            }
        }
    }

    private func load() async {
        guard !rows.isEmpty else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do { let r = try await model.summarize(entries: rows); summary = r.text; modelName = r.model }
        catch { self.error = error.localizedDescription }
    }

    private func share() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tally-summary.txt")
        let text = AppConfig.currentStoreID.flatMap { shiftSummary($0)?.summary } ?? summary
        // No empty paragraph when there is no written summary yet (a store before Nomad's is approved).
        var body = "Tally summary — \(Date().formatted(date: .abbreviated, time: .shortened))\n\n" + (text.isEmpty ? "" : "\(text)\n\n")
            + "Distinct items: \(distinct)\nUnits: \(units)\nNeed review: \(database.flagged.count)\n"
        if let store = AppConfig.currentStoreID, let facts = storeFacts {
            body += "\nStore \(store)\n" + facts.promptLines.map { String($0.dropFirst(2)) }.joined(separator: "\n") + "\n"
        }
        try? body.data(using: .utf8)?.write(to: url)
        shareURL = url
    }
}
