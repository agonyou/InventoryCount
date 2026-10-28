//  CaptureSettings.swift
//  Capture options from the Model & sync screen.

import Foundation

@MainActor
final class CaptureSettings: ObservableObject {
    static let shared = CaptureSettings()
    @Published var readCountsAloud: Bool = UserDefaults.standard.bool(forKey: "tally.readAloud") {
        didSet { UserDefaults.standard.set(readCountsAloud, forKey: "tally.readAloud") }
    }
    @Published var flagLowConfidence: Bool = UserDefaults.standard.object(forKey: "tally.flagLow") as? Bool ?? true {
        didSet { UserDefaults.standard.set(flagLowConfidence, forKey: "tally.flagLow") }
    }
    @Published var confidenceThreshold: Int = 60
    /// Seconds of silence after which Voice mode stops listening and parses (0 = never).
    @Published var idleStopSeconds: Int = UserDefaults.standard.object(forKey: "tally.idleStop") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(idleStopSeconds, forKey: "tally.idleStop") }
    }
    private init() {}
}
