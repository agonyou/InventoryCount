//  MultipeerSyncManager.swift
//  Peer-to-peer sync with Couchbase Lite 4.1's MultipeerReplicator: DNS-SD over Wi-Fi,
//  BLE fallback, TLS with a self-signed per-device identity. Any device in the peer group
//  can join; the authenticator accepts every certificate (same-crew trust model — tighten
//  with MultipeerCertificateAuthenticator(rootCerts:) for production).

import Foundation
import CouchbaseLiteSwift
import CoreBluetooth

struct Peer: Identifiable, Hashable {
    let id: String
    var online: Bool
    var transport: String
    var syncing: Bool
    var lastError: String?
}

@MainActor
final class MultipeerSyncManager: ObservableObject {
    static let shared = MultipeerSyncManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var isActive = false
    @Published private(set) var peers: [Peer] = []
    @Published private(set) var lastError: String?
    @Published private(set) var peerID: String = ""
    @Published private(set) var documentsExchanged = 0

    private var replicator: MultipeerReplicator?
    private var tokens: [ListenerToken] = []

    private init() {}

    /// What phones share directly: the crew's own team's counts and catalog items, and locations.
    /// Never the store system's stock records or products, and not proposals, trucks or shipments,
    /// which reach each phone only through App Services, routed to its store. Any phone in the
    /// peer group is accepted, so nothing store-scoped travels this way.
    static func peerCollections(_ database: DatabaseManager) -> [MultipeerCollectionConfiguration] {
        let team: (Document) -> Bool = { $0.string(forKey: "team") == AppConfig.currentTeam }
        let shared = [database.counts, database.catalogColl, database.locationsColl].compactMap { $0 }
        return shared.map { coll in
            var c = MultipeerCollectionConfiguration(collection: coll)
            if coll.name == AppConfig.countsCollection {
                let crewCount: MultipeerReplicationFilter = { _, doc, flags in
                    flags.contains(.deleted) || (doc.string(forKey: "captured_by") != nil && team(doc))
                }
                c.pushFilter = crewCount; c.pullFilter = crewCount
            } else if coll.name == AppConfig.catalogCollection {
                let teamItem: MultipeerReplicationFilter = { _, doc, flags in flags.contains(.deleted) || team(doc) }
                c.pushFilter = teamItem; c.pullFilter = teamItem
            }
            return c
        }
    }

    func start(database: DatabaseManager) {
        guard replicator == nil else { return }
        do {
            let identity = try Self.loadOrCreateIdentity()
            let authenticator = MultipeerCertificateAuthenticator { _, _ in true }
            var config = MultipeerReplicatorConfiguration(
                peerGroupID: AppConfig.peerGroupID,
                identity: identity,
                authenticator: authenticator,
                collections: Self.peerCollections(database))
            config.transports = [.wifi, .bluetooth]
            let r = try MultipeerReplicator(config: config)

            tokens.append(r.addStatusListener { [weak self] status in
                guard let self else { return }
                self.isActive = status.active
                self.lastError = status.error.map { ($0 as NSError).localizedDescription }
            })
            tokens.append(r.addPeerDiscoveryStatusListener { [weak self] s in
                self?.upsert(id: s.peerID.description, online: s.online, transport: s.transport == .wifi ? "Wi-Fi" : "Bluetooth")
            })
            tokens.append(r.addPeerReplicatorStatusListener { [weak self] s in
                let busy = s.status.activity == .busy || s.status.activity == .connecting
                let err = s.status.error.map { ($0 as NSError).localizedDescription }
                self?.upsert(id: s.peerID.description, syncing: busy, error: err)
            })
            tokens.append(r.addPeerDocumentReplicationListener { [weak self] _ in
                self?.documentsExchanged += 1
            })
            replicator = r
            peerID = r.peerID.description
            r.start()
            isEnabled = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isEnabled = false
        }
    }

    func stop() {
        tokens = []
        replicator?.stop()
        replicator = nil
        isEnabled = false
        isActive = false
        peers = []
    }

    private func upsert(id: String, online: Bool? = nil, transport: String? = nil, syncing: Bool? = nil, error: String? = nil) {
        if let i = peers.firstIndex(where: { $0.id == id }) {
            if let online { peers[i].online = online }
            if let transport { peers[i].transport = transport }
            if let syncing { peers[i].syncing = syncing }
            peers[i].lastError = error
        } else {
            peers.append(Peer(id: id, online: online ?? true, transport: transport ?? "", syncing: syncing ?? false, lastError: error))
        }
        peers.sort { $0.online && !$1.online }
    }

    private static func loadOrCreateIdentity() throws -> TLSIdentity {
        let label = AppConfig.p2pIdentityLabel
        if let existing = try TLSIdentity.identity(withLabel: label) {
            if existing.expiration > Date() { return existing }
            try TLSIdentity.deleteIdentity(withLabel: label)
        }
        let attrs: [String: String] = [certAttrCommonName: "Tally \(AppConfig.deviceID)"]
        let expiration = Calendar.current.date(byAdding: .year, value: 2, to: Date())!
        return try TLSIdentity.createIdentity(for: [.clientAuth, .serverAuth], attributes: attrs,
                                              expiration: expiration, label: label)
    }
}
