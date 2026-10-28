//  TextCaptureView.swift
//  Labelled multi-line field, "Add to sheet" primary button, preview of parsed rows.

import SwiftUI

struct TextCaptureView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var session: CaptureSession
    @EnvironmentObject private var model: InventoryModel
    @EnvironmentObject private var settings: CaptureSettings

    @State private var notes = ""
    @State private var parsed: ParseResult?
    @State private var rows: [ParsedRow] = []
    @State private var isParsing = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Describe what you see").font(CDS.body(13, weight: .semibold)).foregroundStyle(CDS.ink)
                    TextField("Rack 7, three shelves, 30 blue bins each, two bins cracked",
                              text: $notes, axis: .vertical)
                        .font(CDS.body(16)).foregroundStyle(CDS.ink)
                        .lineLimit(5...12).focused($focused)
                        .padding(14)
                        .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CDS.cardRadius, style: .continuous).strokeBorder(focused ? CDS.ink : CDS.borderSubtle))
                        .accessibilityLabel("Item description")
                    Text("Location: \(session.location.display)").font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
                }
                if parsed == nil {
                    Button {
                        Task { await parse() }
                    } label: {
                        HStack { if isParsing { ProgressView().tint(.white) }; Text(isParsing ? "Parsing…" : "Add to sheet") }
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(isParsing || notes.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error { Text(error).font(CDS.body(13)).foregroundStyle(CDS.red700) }
                if parsed != nil {
                    ParsedRowsPreview(rows: $rows, modelName: parsed?.modelName ?? "",
                                      onSave: save, onDiscard: { parsed = nil; rows = [] })
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func parse() async {
        isParsing = true; error = nil; focused = false
        defer { isParsing = false }
        do {
            let r = try await model.parse(text: notes, imageJPEG: nil,
                                          defaultLocation: session.location, knownLocations: database.locations.map(\.location.display))
            parsed = r; rows = r.rows
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            try RowSaver.save(rows, source: .text, database: database, session: session, settings: settings)
            parsed = nil; rows = []; notes = ""
        } catch { self.error = error.localizedDescription }
    }
}
