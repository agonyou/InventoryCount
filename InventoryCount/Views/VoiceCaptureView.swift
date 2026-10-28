//  VoiceCaptureView.swift
//  Hands-free: live transcript (partial words dimmed), rows heard this session,
//  estimate card, Undo · mic · Next bin. The mic is the only solid-red element.

import SwiftUI

struct VoiceCaptureView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var session: CaptureSession
    @EnvironmentObject private var model: InventoryModel
    @EnvironmentObject private var settings: CaptureSettings
    @StateObject private var speech = SpeechRecognizer()

    @State private var parsed: ParseResult?
    @State private var rows: [ParsedRow] = []
    @State private var isParsing = false
    @State private var error: String?
    /// Dictation since the last voice command (or session start) that has not been parsed yet.
    @State private var pendingText = ""
    @State private var lastCommandNote: String?
    @State private var handsFreeSaves = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                transcriptCard
                if let error { Text(error).font(CDS.body(13)).foregroundStyle(CDS.red700) }
                if parsed != nil {
                    ParsedRowsPreview(rows: $rows, sceneDescription: "", modelName: parsed?.modelName ?? "",
                                      onSave: save, onDiscard: { parsed = nil; rows = []; speech.reset() })
                }
                heardThisSession
                estimateCard
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { controls }
        .onAppear {
            speech.idleTimeout = settings.idleStopSeconds
            speech.onUtteranceFinal = { text in handleUtterance(text) }
        }
        .onChange(of: settings.idleStopSeconds) { _, v in speech.idleTimeout = v }
        .onChange(of: speech.isListening) { _, listening in
            // Idle auto-stop behaves like a mic tap: parse whatever was heard.
            if !listening, speech.stoppedByIdleTimeout { Task { await parseTranscript() } }
        }
        .onDisappear { speech.stop() }
    }

    private var transcriptCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Live transcript")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(speech.isListening ? CDS.red : CDS.inkSecondary.opacity(0.4)).frame(width: 8, height: 8)
                        Text(statusText)
                            .font(CDS.body(12, weight: .semibold)).foregroundStyle(CDS.inkSecondary)
                    }
                }
                if speech.allSegments.isEmpty {
                    Text("Tap the mic and read what you see: “thirty blue bins, rack A, shelf two, two of them cracked”.")
                        .font(CDS.body(15)).foregroundStyle(CDS.inkSecondary)
                } else {
                    transcriptText
                }
                if let e = speech.errorMessage { Text(e).font(CDS.body(12)).foregroundStyle(CDS.red700) }
                if let note = lastCommandNote {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.badge.mic").font(.system(size: 12))
                        Text(note).font(CDS.body(12, weight: .semibold))
                    }
                    .foregroundStyle(CDS.info)
                }
                if speech.isListening {
                    Text("Say “next bin”, “bin 15”, “shelf 2”, “rack B” to move on; “done” to stop.")
                        .font(CDS.body(11)).foregroundStyle(CDS.inkSecondary)
                }
            }
        }
    }

    // MARK: - Voice commands (conversational flow)

    private func handleUtterance(_ text: String) {
        guard let match = VoiceCommands.detect(in: text) else {
            pendingText += (pendingText.isEmpty ? "" : " ") + text
            return
        }
        if !match.itemsText.isEmpty { pendingText += (pendingText.isEmpty ? "" : " ") + match.itemsText }
        switch match.command {
        case .stop:
            speech.stop()                      // onChange(isListening) → preview of the remainder
        case .undo:
            undo()
            lastCommandNote = "Removed last row"
        default:
            let chunk = pendingText
            pendingText = ""
            let locationForChunk = session.location
            VoiceCommands.apply(match.command, to: &session.location)
            lastCommandNote = "Now at \(session.location.chip)"
            if settings.readCountsAloud { speech.speak(session.location.chip.replacingOccurrences(of: " · ", with: ", ")) }
            if !chunk.trimmingCharacters(in: .whitespaces).isEmpty {
                Task { await parseAndSaveHandsFree(chunk, location: locationForChunk) }
            }
        }
    }

    /// Hands-free: rows for a finished bin are parsed and added straight to the sheet
    /// (editable later; low-confidence ones are flagged). Listening continues meanwhile.
    private func parseAndSaveHandsFree(_ text: String, location: ItemLocation) async {
        do {
            let r = try await model.parse(text: text, imageJPEG: nil, defaultLocation: location,
                                          knownLocations: database.locations.map(\.location.display))
            guard !r.rows.isEmpty else { return }
            try RowSaver.save(r.rows, source: .voice, database: database, session: session, settings: settings, speech: speech)
            handsFreeSaves += r.rows.count
            lastCommandNote = "Added \(r.rows.count) row\(r.rows.count == 1 ? "" : "s") for \(location.chip)"
        } catch { self.error = error.localizedDescription }
    }

    private var statusText: String {
        if isParsing { return "Parsing…" }
        guard speech.isListening else { return "Paused" }
        let base = speech.utteranceCount > 0 ? "Listening · \(speech.utteranceCount + 1)" : "Listening"
        if settings.idleStopSeconds > 0, speech.idleSeconds >= 10 {
            return base + " · stops in \(max(0, settings.idleStopSeconds - speech.idleSeconds))s"
        }
        return base
    }

    private var transcriptText: some View {
        var t = Text("")
        for s in speech.allSegments {
            t = t + Text(s.text + " ").foregroundColor(s.isPartial ? CDS.inkSecondary.opacity(0.55) : CDS.ink)
        }
        return t.font(CDS.body(17)).lineSpacing(3)
    }

    private var heardThisSession: some View {
        Group {
            if !session.sessionRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Heard this session")
                    ForEach(session.sessionRows.prefix(12)) { e in
                        HStack(spacing: 10) {
                            Image(systemName: e.source.systemImage).font(.system(size: 13)).foregroundStyle(CDS.inkSecondary).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.itemName).font(CDS.body(14, weight: .semibold)).foregroundStyle(CDS.ink)
                                Text(e.location.chip).font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
                            }
                            Spacer()
                            Text(e.countBadge).font(CDS.mono(15, weight: .medium)).foregroundStyle(e.countIsEstimate ? CDS.amber : CDS.ink)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
                        .onTapGesture { path.append(Route.entry(e)) }
                    }
                }
            }
        }
    }

    private var estimateCard: some View {
        Group {
            let est = session.sessionRows.filter(\.countIsEstimate)
            if !est.isEmpty {
                Card(padding: 12, tint: CDS.amberTint, border: CDS.amberSoft, dashed: true) {
                    HStack(spacing: 10) {
                        Image(systemName: "approxequal").foregroundStyle(CDS.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("≈×\(est.reduce(0) { $0 + $1.count }) estimated across \(est.count) row\(est.count == 1 ? "" : "s")")
                                .font(CDS.body(13, weight: .semibold)).foregroundStyle(CDS.ink)
                            Text("Estimates are flagged for review in the summary.").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                        }
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button { undo() } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 18, weight: .semibold))
                    Text("Undo").font(CDS.body(11, weight: .semibold))
                }
                .foregroundStyle(CDS.ink).frame(width: 64, height: 56)
                .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
            }
            .disabled(session.sessionRows.isEmpty)
            .accessibilityLabel("Undo last row")

            Button { Task { await toggleMic() } } label: {
                ZStack {
                    Circle().fill(CDS.red).frame(width: 76, height: 76)
                    Image(systemName: speech.isListening ? "pause.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .accessibilityLabel(speech.isListening ? "Pause listening" : "Start listening")

            Button { session.nextBin() } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right.to.line").font(.system(size: 18, weight: .semibold))
                    Text("Next bin").font(CDS.body(11, weight: .semibold))
                }
                .foregroundStyle(CDS.ink).frame(width: 64, height: 56)
                .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
            }
            .accessibilityLabel("Advance to next bin")
        }
        .padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(CDS.surfaceSunken)
    }

    // MARK: - Actions

    private func toggleMic() async {
        if speech.isListening {
            speech.stop()
            await parseTranscript()
            return
        }
        guard await speech.requestPermissions() else { speech.errorMessage = "Microphone / speech permission denied."; return }
        parsed = nil; rows = []; speech.reset(); pendingText = ""; lastCommandNote = nil; handsFreeSaves = 0
        speech.start()
    }

    private func parseTranscript() async {
        // Only what has not already been saved hands-free by a voice command.
        let text = pendingText.trimmingCharacters(in: .whitespaces)
        pendingText = ""
        guard !text.isEmpty else { if handsFreeSaves > 0 { speech.reset(); handsFreeSaves = 0 }; return }
        isParsing = true; error = nil
        defer { isParsing = false }
        do {
            let r = try await model.parse(text: text, imageJPEG: nil,
                                          defaultLocation: session.location, knownLocations: database.locations.map(\.location.display))
            parsed = r; rows = r.rows
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            try RowSaver.save(rows, source: .voice, database: database, session: session, settings: settings, speech: speech)
            parsed = nil; rows = []; speech.reset(); pendingText = ""; handsFreeSaves = 0
        } catch { self.error = error.localizedDescription }
    }

    private func undo() {
        guard let last = session.sessionRows.first else { return }
        try? database.delete(last)
        session.sessionRows.removeFirst()
    }
}
