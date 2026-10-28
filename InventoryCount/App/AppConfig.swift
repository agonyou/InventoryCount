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
    static let cataloguesCollection = "catalogue"   // UPC/EAN → product name (team-shared)
    static let locationsCollection = "locations"    // reference list (shared read-only)

    // Capella (opt-in cloud sync)
    static let adminChannel        = "admin"
    static let managerUsername     = "manager"
    static let defaultTeam         = "crew-a"

    // Peer-to-peer
    static let peerGroupID         = "com.couchbase.tally"
    static let p2pIdentityLabel    = "com.couchbase.tally.identity"

    // Cloud fallback model (optional; on-device Foundation Models is primary)
    static let claudeModel         = "claude-opus-5-5"

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
