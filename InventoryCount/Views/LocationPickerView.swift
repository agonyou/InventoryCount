//  LocationPickerView.swift
//  Site / Rack / Shelf / Bin fields, known locations, QR to set. Manager can add reference locations.

import SwiftUI

struct LocationPickerView: View {
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var session: CaptureSession
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ItemLocation()
    @State private var showingScanner = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Location", subtitle: draft.display)
                Card {
                    VStack(spacing: 10) {
                        field("Site", $draft.site); field("Rack", $draft.rack); field("Shelf", $draft.shelf); field("Bin", $draft.bin)
                    }
                }
                HStack(spacing: 10) {
                    if BarcodeScannerView.isSupported {
                        Button { showingScanner = true } label: { Label("Scan QR", systemImage: "qrcode.viewfinder") }.buttonStyle(PillButtonStyle())
                    }
                    Button("Use this location") { session.location = draft; dismiss() }.buttonStyle(PillButtonStyle(prominent: true))
                }
                if !database.locations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Known locations")
                        ForEach(database.locations) { l in
                            Button { draft = l.location } label: {
                                HStack {
                                    Text(l.location.display).font(CDS.mono(13, weight: .medium)).foregroundStyle(CDS.ink)
                                    Spacer()
                                    if !l.qr.isEmpty { Image(systemName: "qrcode").foregroundStyle(CDS.inkSecondary) }
                                }
                                .padding(12)
                                .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
                            }
                        }
                    }
                }
                if authState.isAdmin {
                    Button("Save as reference location (manager)") { try? database.save(LocationRef(location: draft)) }
                        .font(CDS.body(13, weight: .semibold)).foregroundStyle(CDS.info)
                }
            }
            .padding(16)
        }
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = session.location }
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                BarcodeScannerView { code in
                    showingScanner = false
                    if let ref = database.location(forQR: code.value) { draft = ref.location } else { draft = ItemLocation(parsing: code.value) }
                }
                .ignoresSafeArea()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingScanner = false } }
                           ToolbarItem(placement: .confirmationAction) { Button("Done") { showingScanner = false } } }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).font(CDS.body(13, weight: .semibold)).foregroundStyle(CDS.inkSecondary).frame(width: 56, alignment: .leading)
            TextField(label, text: text).font(CDS.mono(15)).textInputAutocapitalization(.characters).autocorrectionDisabled()
        }
    }
}
