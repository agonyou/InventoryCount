//  AppConfig.swift
//  Domain parameters. Keep in sync with provision.env (COLLECTIONS, CB_ENDPOINT_NAME)
//  and the sync-functions/*.js files.

import Foundation
import UIKit

enum AppConfig {
    static let appDisplayName      = "Tally"          // working name — owner decides branding
    static let databaseName        = "InventoryCountDB"

    // Named scope — NEVER "_default". Matches COLLECTIONS='inventory/...'
    static let scopeName           = "inventory"
    static let countsCollection    = "counts"       // sheet rows (team-shared)
    static let catalogCollection = "catalog"   // UPC/EAN → product name (team-shared)
    static let locationsCollection = "locations"    // reference list (shared read-only)
    static let reviewsCollection   = "reviews"      // Nomad reviews (team-shared, read-only on device)
    static let proposalsCollection = "proposals"    // what Nomad saved after approval (read-only on device)
    static let trucksCollection    = "trucks"       // the fleet (read-only on device)
    static let shipmentsCollection = "shipments"    // deliveries to the store (read-only on device)

    /// Cloud sync includes proposals, trucks and shipments only when the App Services endpoint
    /// links them (Info.plist `TallyStoreDataSync`): an endpoint missing a collection the phone
    /// asks for refuses the whole replication. Peer-to-peer sync always carries them.
    static var syncsStoreData: Bool { Bundle.main.object(forInfoDictionaryKey: "TallyStoreDataSync") as? Bool ?? false }

    // Capella (opt-in cloud sync)
    static let adminChannel        = "admin"
    static let managerUsername     = "manager"
    static let defaultTeam         = "crew-a"
    static var currentTeam: String { UserDefaults.standard.string(forKey: "tally.team") ?? defaultTeam }
    /// A team named like a store ("store-001") counts that store: its counts carry store_id, which
    /// the counts rule requires to equal the team.
    static var currentStoreID: String? { currentTeam.hasPrefix("store-") ? currentTeam : nil }

    // Peer-to-peer
    static let peerGroupID         = "com.couchbase.tally"
    static let p2pIdentityLabel    = "com.couchbase.tally.identity"

    /// Stable per-install device id (captured_by).
    static var deviceID: String {
        let key = "tally.deviceID"
        if let s = UserDefaults.standard.string(forKey: key) { return s }
        let s = String((UIDevice.current.identifierForVendor ?? UUID()).uuidString.prefix(8)).lowercased()
        UserDefaults.standard.set(s, forKey: key)
        return s
    }
    static var deviceName: String { UIDevice.current.name }

    static var appServicesEndpointURL: URL {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "AppServicesEndpointURL") as? String,
            !urlString.hasPrefix("wss://PLACEHOLDER"),
            let url = URL(string: urlString)
        else {
            fatalError("AppServicesEndpointURL not set in Info.plist. Run setup-capella.sh.")
        }
        return url
    }
    static var isEndpointConfigured: Bool {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "AppServicesEndpointURL") as? String else { return false }
        return !s.hasPrefix("wss://PLACEHOLDER")
    }
}
