//  SpeechRecognizer.swift
//  On-device speech-to-text for Voice mode. Exposes segments so the UI can dim the
//  partial (low-confidence) words, and speaks counts back via AVSpeechSynthesizer.

import Foundation
import Speech
import AVFoundation

struct TranscriptSegment: Identifiable, Hashable {
    let id: Int
    let text: String
    let isPartial: Bool
}

@MainActor
final class SpeechRecognizer: ObservableObject {
    /// Finalised text from earlier utterances in this listening session (endpointing restarts).
    @Published private(set) var committedSegments: [TranscriptSegment] = []
    /// The utterance currently being recognised (partial words have isPartial == true).
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var isListening = false
    @Published private(set) var utteranceCount = 0
    @Published var errorMessage: String?
    /// Seconds since speech was last heard while listening (drives the idle auto-stop + hint).
    @Published private(set) var idleSeconds: Int = 0
    /// Set when listening ended because of the idle timeout rather than a tap.
    @Published private(set) var stoppedByIdleTimeout = false
    /// 0 disables the idle auto-stop.
    var idleTimeout: Int = 30
    /// Called on the main actor with each finished utterance (for voice commands).
    var onUtteranceFinal: ((String) -> Void)?

    /// Everything heard so far: committed utterances + the live one.
    var allSegments: [TranscriptSegment] { committedSegments + segments }
    var transcript: String { allSegments.map(\.text).joined(separator: " ") }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let synth = AVSpeechSynthesizer()
    private var userStopped = false
    private var lastSpeechAt = Date()
    private var idleWatcher: Task<Void, Never>?

    func requestPermissions() async -> Bool {
        let speech: Bool = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let mic: Bool = await withCheckedContinuation { c in AVAudioApplication.requestRecordPermission { c.resume(returning: $0) } }
        return speech && mic
    }

    func start() {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available on this device."; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            // The tap feeds whichever request is current, so a restarted task keeps receiving audio.
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            userStopped = false
            stoppedByIdleTimeout = false
            isListening = true
            errorMessage = nil
            lastSpeechAt = Date()
            idleSeconds = 0
            startIdleWatcher()
            beginRecognitionTask()
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    /// One recognition task = one utterance. The recogniser's endpointer ends the task after a
    /// pause (silence timeout is not configurable), so when a final result arrives we commit it
    /// and immediately start a new task on the same audio stream. Listening only ends when the
    /// user taps the mic.
    private func beginRecognitionTask() {
        guard let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let segs = result.bestTranscription.segments
                    if !segs.isEmpty { self.lastSpeechAt = Date(); self.idleSeconds = 0 }
                    self.segments = segs.enumerated().map { i, s in
                        TranscriptSegment(id: self.utteranceCount * 10_000 + i, text: s.substring,
                                          isPartial: !result.isFinal && s.confidence == 0)
                    }
                    if result.isFinal {
                        self.commitCurrentUtterance()
                        if !self.userStopped && self.isListening { self.beginRecognitionTask() }
                    }
                } else if error != nil {
                    // Endpointer / cancellation errors arrive here too; restart unless the user stopped.
                    self.commitCurrentUtterance()
                    if !self.userStopped && self.isListening { self.beginRecognitionTask() }
                }
            }
        }
    }

    /// Voice-activity watchdog: once a second, measure silence since the last recognised word;
    /// past `idleTimeout` seconds, stop as if the mic had been tapped (flagged so the UI parses).
    private func startIdleWatcher() {
        idleWatcher?.cancel()
        idleWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isListening else { return }
                let idle = Int(Date().timeIntervalSince(self.lastSpeechAt))
                self.idleSeconds = idle
                if self.idleTimeout > 0 && idle >= self.idleTimeout {
                    self.stoppedByIdleTimeout = true
                    self.stop()
                    return
                }
            }
        }
    }

    private func commitCurrentUtterance() {
        let finished = segments.map { TranscriptSegment(id: $0.id, text: $0.text, isPartial: false) }
        if !finished.isEmpty {
            committedSegments.append(contentsOf: finished)
            utteranceCount += 1
            onUtteranceFinal?(finished.map(\.text).joined(separator: " "))
        }
        segments = []
    }

    /// User-initiated stop: ends audio, keeps whatever was heard (partials become final text).
    func stop() {
        guard isListening || audioEngine.isRunning else { return }
        userStopped = true
        idleWatcher?.cancel(); idleWatcher = nil
        idleSeconds = 0
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel(); task = nil; request = nil
        isListening = false
        commitCurrentUtterance()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reset() { segments = []; committedSegments = []; utteranceCount = 0 }

    func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }
}
