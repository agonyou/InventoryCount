//  ReplicationManager.swift
//  Background cloud ↔ edge sync with Capella App Services.
//  pause() = user-simulated offline (keeps isManuallyPaused); stop() = logout/cleanup.

import Foundation
import CouchbaseLiteSwift

enum SyncStatus: Equatable {
    case idle, connecting, syncing, offline, error(String)

    var label: String {
        switch self {
        case .idle:       return "Up to date"
        case .connecting: return "Connecting…"
        case .syncing:    return "Syncing…"
        case .offline:    return "Offline"
        case .error:      return "Sync error"
        }
    }
    var systemImage: String {
        switch self {
        case .idle:       return "checkmark.icloud"
        case .connecting: return "icloud"
        case .syncing:    return "arrow.triangle.2.circlepath.icloud"
        case .offline:    return "icloud.slash"
        case .error:      return "exclamationmark.icloud"
        }
    }
    var isError: Bool { if case .error = self { return true } else { return false } }
}

@MainActor
final class ReplicationManager: ObservableObject {
    static let shared = ReplicationManager()

    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var lastSyncError: String?
    @Published private(set) var isManuallyPaused: Bool = false
    @Published private(set) var lastActivityAt: Date?

    private var replicator: Replicator?
    private var statusToken: ListenerToken?

    private init() {}

    func start(username: String, password: String, database: DatabaseManager) throws {
        isManuallyPaused = false
        stop()
        guard let counts = database.counts, let catalog = database.catalogColl,
              let locations = database.locationsColl, let reviews = database.reviewsColl,
              let proposals = database.proposalsColl, let trucks = database.trucksColl,
              let shipments = database.shipmentsColl else {
            throw DBError.notOpen
        }
        let target = URLEndpoint(url: AppConfig.appServicesEndpointURL)
        var collections = [counts, catalog, locations, reviews]
        if AppConfig.syncsStoreData { collections += [proposals, trucks, shipments] }
        // Never push what the access rules refuse, such as a document this phone received from a
        // peer: reviews, proposals, trucks and shipments come only from Nomad and the store
        // system, only a manager writes locations, stock records (no captured_by) and store
        // products (no team) come only from the store system.
        let isManager = username == AppConfig.managerUsername
        let pullOnly: Set<String> = [AppConfig.reviewsCollection, AppConfig.proposalsCollection,
                                     AppConfig.trucksCollection, AppConfig.shipmentsCollection]
        let collConfigs = collections.map { coll -> CollectionConfiguration in
            var c = CollectionConfiguration(collection: coll)
            if pullOnly.contains(coll.name) || (coll.name == AppConfig.locationsCollection && !isManager) {
                c.pushFilter = { _, _ in false }
            } else if coll.name == AppConfig.countsCollection {
                c.pushFilter = { doc, flags in flags.contains(.deleted) || doc.string(forKey: "captured_by") != nil }
            } else if coll.name == AppConfig.catalogCollection {
                c.pushFilter = { doc, flags in flags.contains(.deleted) || doc.string(forKey: "team") != nil }
            }
            return c
        }
        var config = ReplicatorConfiguration(collections: collConfigs, target: target)
        config.replicatorType = .pushAndPull
        config.continuous = true
        config.authenticator = BasicAuthenticator(username: username, password: password)

        let r = Replicator(config: config)
        statusToken = r.addChangeListener { [weak self] change in
            guard let self else { return }
            let status = change.status
            Task { @MainActor in self.handle(status: status) }
        }
        replicator = r
        syncStatus = .connecting
        lastSyncError = nil
        r.start()
    }

    /// User-initiated offline simulation (Always-On demo toggle).
    func pause() {
        isManuallyPaused = true
        statusToken = nil
        replicator?.stop()
        replicator = nil
        syncStatus = .offline
    }

    /// Logout / cleanup only.
    func stop() {
        isManuallyPaused = false
        statusToken = nil
        replicator?.stop()
        replicator = nil
        syncStatus = .idle
        lastSyncError = nil
    }

    private func handle(status: Replicator.Status) {
        lastActivityAt = Date()
        if let error = status.error {
            let msg = (error as NSError).localizedDescription
            lastSyncError = msg
            syncStatus = .error(msg)
            return
        }
        switch status.activity {
        case .connecting: syncStatus = .connecting
        case .busy:       syncStatus = .syncing
        case .idle:       syncStatus = .idle; lastSyncError = nil
        case .offline:    syncStatus = .offline
        case .stopped:    syncStatus = isManuallyPaused ? .offline : .idle
        @unknown default: break
        }
    }
}
