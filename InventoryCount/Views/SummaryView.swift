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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Summary", subtitle: modelName.isEmpty ? nil : "Written by \(modelName)")
                HStack(spacing: 10) {
                    StatTile(value: "\(distinct)", label: "Distinct items")
                    StatTile(value: "\(units)", label: "Units counted")
                    StatTile(value: "\(database.flagged.count)", label: "Need review", tint: database.flagged.isEmpty ? CDS.ink : CDS.amber)
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Summary")
                        if isLoading { ProgressView("Writing summary…").font(CDS.body(13)) }
                        else if let error { Text(error).font(CDS.body(13)).foregroundStyle(CDS.red700) }
                        else if summary.isEmpty { Text("Nothing to summarise yet.").font(CDS.body(14)).foregroundStyle(CDS.inkSecondary) }
                        else { Text(summary).font(CDS.body(15)).foregroundStyle(CDS.ink).lineSpacing(3).textSelection(.enabled) }
                    }
                }
                flagged
                HStack(spacing: 10) {
                    Button { Task { await load() } } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                        .buttonStyle(PillButtonStyle()).disabled(isLoading || rows.isEmpty)
                    Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PillButtonStyle(prominent: true)).disabled(summary.isEmpty)
                }
            }
            .padding(16)
        }
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: rows.count) { if summary.isEmpty && !isLoading { await load() } }
        .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
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

    private func load() async {
        guard !rows.isEmpty else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do { let r = try await model.summarize(entries: rows); summary = r.text; modelName = r.model }
        catch { self.error = error.localizedDescription }
    }

    private func share() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tally-summary.txt")
        let body = "Tally summary — \(Date().formatted(date: .abbreviated, time: .shortened))\n\n\(summary)\n\nDistinct items: \(distinct)\nUnits: \(units)\nNeed review: \(database.flagged.count)\n"
        try? body.data(using: .utf8)?.write(to: url)
        shareURL = url
    }
}
