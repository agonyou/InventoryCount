//  AuthState.swift
//  Capella (cloud) credentials — optional. The app works without signing in;
//  the Model & sync screen turns cloud sync on by signing in as an App User.

import Foundation

@MainActor
final class AuthState: ObservableObject {
    @Published private(set) var isCloudSignedIn = false
    @Published private(set) var username = ""
    @Published var team: String = UserDefaults.standard.string(forKey: "tally.team") ?? AppConfig.defaultTeam {
        didSet { UserDefaults.standard.set(team, forKey: "tally.team") }
    }
    var isAdmin: Bool { username == AppConfig.managerUsername }
    var storedPassword: String? { KeychainHelper.load(for: username) }

    func signInCloud(username: String, password: String) throws {
        let user = username.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !password.isEmpty else { throw LoginError.missingCredentials }
        guard AppConfig.isEndpointConfigured else { throw LoginError.noEndpoint }
        KeychainHelper.save(password: password, for: user)
        self.username = user
        try ReplicationManager.shared.start(username: user, password: password, database: DatabaseManager.shared)
        isCloudSignedIn = true
    }

    func signOutCloud() {
        ReplicationManager.shared.stop()
        KeychainHelper.delete(for: username)
        username = ""
        isCloudSignedIn = false
    }
}

enum LoginError: LocalizedError {
    case missingCredentials, noEndpoint
    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Enter a username and password."
        case .noEndpoint: return "No App Services endpoint in Info.plist — run setup-capella.sh first."
        }
    }
}
