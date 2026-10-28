//  SheetView.swift
//  The inventory sheet: sticky-header table, horizontally scrollable, badges for
//  location and sync state, Filter and Summarise, Export in the header.

import SwiftUI

struct SheetView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var session: CaptureSession
    @State private var filterLocation: String? = nil
    @State private var filterReview = false
    @State private var exportURL: URL?

    private var rows: [CountEntry] {
        database.entries.filter { e in
            e.kind == .entry
                && (filterLocation == nil || e.location.display == filterLocation)
                && (!filterReview || e.needsReview || e.countIsEstimate)
        }
    }
    private var locationsInSheet: [String] { Array(Set(database.entries.filter { $0.kind == .entry }.map(\.location.display))).sorted() }

    private let columns: [(String, CGFloat)] = [("Item name", 170), ("Count", 72), ("Size · shape · color", 160), ("Annotation", 220), ("Location", 170)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ScreenHeader(title: "Sheet", subtitle: "\(rows.count) rows · \(rows.reduce(0) { $0 + $1.count }) units")
                Spacer()
                Button { exportURL = try? CSVExporter.writeTemporaryFile(for: rows) } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Export CSV")
            }
            HStack(spacing: 8) {
                Badge(text: session.location.chip, color: CDS.ink, mono: true)
                SyncBadge()
                Spacer(minLength: 4)
                Menu {
                    Button("All locations") { filterLocation = nil }
                    ForEach(locationsInSheet, id: \.self) { l in Button(l) { filterLocation = l } }
                    Divider()
                    Toggle("Needs review only", isOn: $filterReview)
                } label: {
                    Label(filterLocation == nil ? "Filter" : "Filtered", systemImage: "line.3.horizontal.decrease").font(CDS.body(13, weight: .semibold)).foregroundStyle(CDS.ink).fixedSize()
                }
                Button { path.append(Route.summary) } label: {
                    Label("Summarise", systemImage: "text.badge.star").font(CDS.body(13, weight: .semibold)).fixedSize()
                }
                .buttonStyle(.borderedProminent).tint(CDS.red).disabled(rows.isEmpty)
            }
            if rows.isEmpty {
                ContentUnavailableCompat(title: "No rows yet", systemImage: "tablecells", message: "Count something by voice, text or photo and it lands here.")
            } else {
                table
            }
        }
        .padding(.horizontal, 16).padding(.top, 4)
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportURL) { ShareSheet(items: [$0]) }
    }

    private var table: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(rows) { e in
                                Button { path.append(Route.entry(e)) } label: { row(e) }.buttonStyle(.plain)
                                Divider().overlay(CDS.borderSubtle)
                            }
                        } header: { headerRow }
                    }
                }
            }
            .frame(width: columns.reduce(0) { $0 + $1.1 + 16 })
            .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CDS.cardRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.0) { c in
                Text(c.0.uppercased()).font(CDS.body(11, weight: .semibold)).tracking(1.2).foregroundStyle(CDS.inkSecondary)
                    .frame(width: c.1, alignment: c.0 == "Count" ? .trailing : .leading).padding(.horizontal, 8)
            }
        }
        .frame(height: 40).background(Color(hex: 0xFBF6EC))
        .overlay(Divider().overlay(CDS.borderSubtle), alignment: .bottom)
    }

    private func row(_ e: CountEntry) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: e.source.systemImage).font(.system(size: 11)).foregroundStyle(CDS.inkSecondary)
                Text(e.itemName).font(CDS.body(14, weight: .semibold)).foregroundStyle(CDS.ink).lineLimit(2)
            }
            .frame(width: columns[0].1, alignment: .leading).padding(.horizontal, 8)
            Text("\(e.countDisplay)").font(CDS.mono(15, weight: .medium)).foregroundStyle(e.countIsEstimate ? CDS.amber : CDS.ink)
                .frame(width: columns[1].1, alignment: .trailing).padding(.horizontal, 8)
            Text(e.attributes).font(CDS.body(13)).foregroundStyle(CDS.ink).lineLimit(2)
                .frame(width: columns[2].1, alignment: .leading).padding(.horizontal, 8)
            HStack(spacing: 6) {
                Text(e.annotation).font(CDS.body(13)).foregroundStyle(CDS.inkSecondary).lineLimit(2)
                if e.needsReview { Badge(text: "Review", color: CDS.amber) }
            }
            .frame(width: columns[3].1, alignment: .leading).padding(.horizontal, 8)
            Text(e.location.display).font(CDS.mono(12)).foregroundStyle(CDS.ink).lineLimit(2)
                .frame(width: columns[4].1, alignment: .leading).padding(.horizontal, 8)
        }
        .padding(.vertical, 10)
        .background(e.needsReview || e.countIsEstimate ? CDS.amberTint.opacity(0.6) : .clear)
        .contentShape(Rectangle())
    }
}
