//  InventoryCountApp.swift

import SwiftUI
import CouchbaseLiteSwift

@main
struct InventoryCountApp: App {
    @StateObject private var database = DatabaseManager.shared
    @StateObject private var replication = ReplicationManager.shared
    @StateObject private var multipeer = MultipeerSyncManager.shared
    @StateObject private var model = InventoryModel.shared
    @StateObject private var settings = CaptureSettings.shared
    @StateObject private var authState = AuthState()
    @StateObject private var session = CaptureSession()

    init() {
        #if DEBUG
        LogSinks.console = ConsoleLogSink(level: .warning, domains: .all)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(database)
                .environmentObject(replication)
                .environmentObject(multipeer)
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(authState)
                .environmentObject(session)
                .tint(CDS.red)
                .onAppear {
                    try? database.open()
                    if UserDefaults.standard.bool(forKey: "tally.p2p") { multipeer.start(database: database) }
                }
        }
    }
}

/// Shared capture state: the current location and the rows heard/parsed this session.
@MainActor
final class CaptureSession: ObservableObject {
    @Published var location: ItemLocation = {
        if let d = UserDefaults.standard.dictionary(forKey: "tally.location") { return ItemLocation(dictionary: d) }
        return ItemLocation(site: "Location X", rack: "A", shelf: "S1", bin: "B1")
    }() {
        didSet { UserDefaults.standard.set(location.dictionary, forKey: "tally.location") }
    }
    @Published var sessionRows: [CountEntry] = []     // rows saved during this session (undo-able)

    func nextBin() {
        var l = location
        if let n = Int(l.bin.filter(\.isNumber)) {
            let prefix = l.bin.prefix { !$0.isNumber }
            l.bin = "\(prefix)\(n + 1)"
        } else { l.bin = l.bin.isEmpty ? "B1" : l.bin + "+" }
        location = l
    }
}
