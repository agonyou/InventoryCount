//  ModelSyncView.swift
//  On-device model card, capture options, peer-to-peer sync + nearby peers,
//  optional Capella cloud sync (sign in).

import SwiftUI

struct ModelSyncView: View {
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var model: InventoryModel
    @EnvironmentObject private var settings: CaptureSettings
    @EnvironmentObject private var multipeer: MultipeerSyncManager
    @EnvironmentObject private var replication: ReplicationManager
    @EnvironmentObject private var authState: AuthState

    @State private var cloudUser = ""
    @State private var cloudPass = ""
    @State private var cloudError: String?
    @State private var showingLogs = false
    @State private var hasLogs = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Model & sync")
                modelCard
                captureOptions
                peerCard
                cloudCard
                Button { showingLogs = true } label: { Label("Share sync logs", systemImage: "doc.text.magnifyingglass") }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!hasLogs)
                Text("Device \(AppConfig.deviceID) · \(AppConfig.deviceName) · \(database.entries.count) rows local")
                    .font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
            }
            .padding(16)
        }
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refreshAvailability(); hasLogs = !SyncLogs.files().isEmpty }
        .sheet(isPresented: $showingLogs) { ShareSheet(items: SyncLogs.files()) }
    }

    private var modelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "On-device model")
                        Text(model.onDeviceModelName).font(CDS.body(15, weight: .semibold)).foregroundStyle(CDS.ink)
                    }
                    Spacer()
                    Badge(text: model.availability.label, color: model.availability == .ready ? CDS.success : CDS.amber, filled: model.availability == .ready)
                }
                Text(model.availability == .ready
                     ? "Parsing and summaries run on this iPhone with Apple's Foundation Models. Photos are read on device (barcodes and printed text)."
                     : "Turn on Apple Intelligence in Settings to parse and summarize on this iPhone.")
                    .font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
                Toggle(isOn: $model.keepLoaded) { Text("Keep model loaded").font(CDS.body(14)) }.tint(CDS.success)
            }
        }
    }

    private var captureOptions: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Capture")
                Toggle(isOn: $settings.readCountsAloud) { Text("Read counts aloud").font(CDS.body(14)) }.tint(CDS.success)
                Toggle(isOn: $settings.flagLowConfidence) { Text("Flag low-confidence counts").font(CDS.body(14)) }.tint(CDS.success)
                Stepper(value: $settings.idleStopSeconds, in: 0...120, step: 5) {
                    HStack {
                        Text("Voice: stop after silence").font(CDS.body(14))
                        Spacer()
                        Text(settings.idleStopSeconds == 0 ? "Never" : "\(settings.idleStopSeconds)s")
                            .font(CDS.mono(13, weight: .medium)).foregroundStyle(CDS.inkSecondary)
                    }
                }
            }
        }
    }

    private var peerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Peer-to-peer sync")
                    Spacer()
                    Toggle("", isOn: Binding(get: { multipeer.isEnabled }, set: { on in
                        UserDefaults.standard.set(on, forKey: "tally.p2p")
                        on ? multipeer.start(database: database) : multipeer.stop()
                    })).labelsHidden().tint(CDS.success)
                }
                Text(multipeer.isEnabled
                     ? "Discovering nearby devices over Wi-Fi (Bonjour) with Bluetooth fallback. Peer group \(AppConfig.peerGroupID)."
                     : "Off. Turn on to sync the sheet directly with nearby devices — no network needed.")
                    .font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
                if let e = multipeer.lastError { Text(e).font(CDS.body(12)).foregroundStyle(CDS.red700) }
                if multipeer.isEnabled {
                    if multipeer.peers.isEmpty {
                        Text("No peers yet").font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
                    }
                    ForEach(multipeer.peers) { p in
                        HStack {
                            Circle().fill(p.online ? CDS.success : CDS.inkSecondary.opacity(0.4)).frame(width: 8, height: 8)
                            Text(String(p.id.prefix(12))).font(CDS.mono(13, weight: .medium)).foregroundStyle(CDS.ink)
                            Text(p.transport).font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                            Spacer()
                            Badge(text: !p.online ? "Offline" : (p.syncing ? "Syncing" : "Synced"), color: !p.online ? CDS.inkSecondary : (p.syncing ? CDS.info : CDS.success))
                        }
                    }
                    Text("This device: \(multipeer.peerID.prefix(12)) · \(multipeer.documentsExchanged) docs exchanged")
                        .font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
                }
            }
        }
    }

    private var cloudCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Cloud sync · Capella App Services")
                    Spacer()
                    if authState.isCloudSignedIn { Badge(text: replication.syncStatus.label, color: replication.syncStatus.isError ? CDS.red700 : CDS.success) }
                }
                if !AppConfig.isEndpointConfigured {
                    Text("Not provisioned. Run setup-capella.sh in the project folder; it writes the endpoint into Info.plist.")
                        .font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
                } else if authState.isCloudSignedIn {
                    Text("Signed in as \(authState.username) · crew \(authState.team)").font(CDS.body(13)).foregroundStyle(CDS.ink)
                    Text(AppConfig.appServicesEndpointURL.absoluteString).font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary).textSelection(.enabled)
                    if let e = replication.lastSyncError { Text(e).font(CDS.body(12)).foregroundStyle(CDS.red700) }
                    Toggle(isOn: Binding(get: { replication.isManuallyPaused }, set: { $0 ? replication.pause() : reconnect() })) {
                        Text(replication.isManuallyPaused ? "Offline (simulated)" : "Online").font(CDS.body(14))
                    }.tint(CDS.success)
                    Button("Sign out of cloud", role: .destructive) { authState.signOutCloud() }.font(CDS.body(14, weight: .semibold))
                } else {
                    TextField("App User (manager or bob)", text: $cloudUser).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $cloudPass)
                    TextField("Crew", text: $authState.team).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if let cloudError { Text(cloudError).font(CDS.body(12)).foregroundStyle(CDS.red700) }
                    Button("Sign in") {
                        do { try authState.signInCloud(username: cloudUser, password: cloudPass); cloudError = nil; cloudPass = "" }
                        catch { cloudError = error.localizedDescription }
                    }
                    .buttonStyle(PillButtonStyle()).disabled(cloudUser.isEmpty || cloudPass.isEmpty)
                }
            }
            .font(CDS.body(14))
        }
    }

    private func reconnect() {
        guard let password = authState.storedPassword, !password.isEmpty else { authState.signOutCloud(); return }
        try? ReplicationManager.shared.start(username: authState.username, password: password, database: database)
    }
}
