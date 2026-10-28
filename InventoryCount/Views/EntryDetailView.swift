//  EntryDetailView.swift
//  Edit one row of the sheet.

import SwiftUI

struct EntryDetailView: View {
    @EnvironmentObject private var database: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var entry: CountEntry
    @State private var photo: UIImage?
    @State private var error: String?

    init(entry: CountEntry) { _entry = State(initialValue: entry) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: entry.itemName.isEmpty ? "Row" : entry.itemName, subtitle: "\(entry.source.label) · \(entry.capturedByName) · \(entry.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: CDS.cardRadius, style: .continuous))
                }
                Card {
                    VStack(spacing: 10) {
                        row("Item") { TextField("Item name", text: $entry.itemName) }
                        row("Count") {
                            HStack {
                                TextField("0", value: $entry.count, format: .number).keyboardType(.numberPad).font(CDS.mono(16))
                                Toggle("Estimate", isOn: $entry.countIsEstimate).font(CDS.body(13)).tint(CDS.amber)
                            }
                        }
                        row("Size") { TextField("Size · shape · color", text: $entry.attributes) }
                        row("Notes") { TextField("Annotation", text: $entry.annotation, axis: .vertical) }
                        row("Site") { TextField("Site", text: $entry.location.site) }
                        row("Rack") { TextField("Rack", text: $entry.location.rack) }
                        row("Shelf") { TextField("Shelf", text: $entry.location.shelf) }
                        row("Bin") { TextField("Bin", text: $entry.location.bin) }
                        row("Review") { Toggle("Needs review", isOn: $entry.needsReview).font(CDS.body(13)).tint(CDS.amber) }
                        if let c = entry.code { row("Code") { Text("\(c.type.rawValue.uppercased()) \(c.value)").font(CDS.mono(13)) } }
                    }
                    .font(CDS.body(15))
                }
                if let error { Text(error).font(CDS.body(13)).foregroundStyle(CDS.red700) }
                HStack(spacing: 10) {
                    Button("Delete row", role: .destructive) { try? database.delete(entry); dismiss() }.buttonStyle(PillButtonStyle())
                    Button("Save") { save() }.buttonStyle(PillButtonStyle(prominent: true)).disabled(entry.itemName.isEmpty)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if entry.hasPhoto, let d = database.photo(for: entry) { photo = UIImage(data: d) } }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top) {
            Text(label).font(CDS.body(12, weight: .semibold)).foregroundStyle(CDS.inkSecondary).frame(width: 56, alignment: .leading).padding(.top, 2)
            content()
        }
    }

    private func save() {
        do { try database.save(entry); dismiss() } catch { self.error = error.localizedDescription }
    }
}
