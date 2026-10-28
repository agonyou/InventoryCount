//  InventoryModel.swift
//  The parsing/summary model behind every capture mode.
//    Primary:  Apple Foundation Models (on device, iOS 26+). Typed output via @Generable.
//    Fallback: Claude API (cloud) when the on-device model is unavailable, or for true
//              visual analysis of a photo (image input to Foundation Models needs the iOS 27 SDK).
//  Photos on device: Vision reads barcodes + printed text, and the text model turns that
//  plus the user's notes into rows.

import Foundation
import FoundationModels

struct ParsedRow: Identifiable, Hashable {
    var id = UUID()
    var itemName: String
    var count: Int
    var countIsEstimate: Bool
    var attributes: String
    var annotation: String
    var location: String
    var confidence: Int
}

struct ParseResult {
    var rows: [ParsedRow]
    var sceneDescription: String
    var modelName: String
    var items: [DetectedItem] = []     // item boxes (+ name/colour/material) for the photo overlay
}

@Generable(description: "One row of an inventory sheet")
struct GeneratedRow {
    @Guide(description: "Short product or item name, e.g. 'blue storage bin'")
    var itemName: String
    @Guide(description: "Number of units; 0 if unknown")
    var count: Int
    @Guide(description: "true when the count is an estimate or was only partially visible")
    var countIsEstimate: Bool
    @Guide(description: "Size, shape and color in a few words")
    var attributes: String
    @Guide(description: "Details worth recording: condition, labels, packaging, 'three shelves of 30 bins'")
    var annotation: String
    @Guide(description: "Location as 'site / rack / shelf / bin', using the default location unless the input names another")
    var location: String
    @Guide(description: "Confidence 0 to 100 that this row is correct")
    var confidence: Int
}

@Generable(description: "Rows extracted from a counter's notes")
struct GeneratedRows {
    @Guide(description: "One or two sentences describing the scene if a photo was described; otherwise empty")
    var sceneDescription: String
    var rows: [GeneratedRow]
}

@Generable(description: "Inventory summary")
struct GeneratedSummary {
    @Guide(description: "Two short paragraphs: what was counted, then notable observations")
    var summary: String
}

enum ModelAvailability: Equatable {
    case ready, notReady, notEligible, intelligenceOff, unsupportedOS
    var label: String {
        switch self {
        case .ready: return "Ready"
        case .notReady: return "Downloading"
        case .notEligible: return "Device not eligible"
        case .intelligenceOff: return "Apple Intelligence off"
        case .unsupportedOS: return "Needs iOS 26"
        }
    }
}

struct ModelFailure: LocalizedError { let message: String; var errorDescription: String? { message } }

enum ModelError: LocalizedError {
    case onDeviceUnavailable(ModelAvailability), noModel
    var errorDescription: String? {
        switch self {
        case .onDeviceUnavailable(let a): return "On-device model unavailable: \(a.label). Add a Claude API key in Model & sync to use the cloud fallback."
        case .noModel: return "No model available. Enable Apple Intelligence or add a Claude API key."
        }
    }
}

@MainActor
final class InventoryModel: ObservableObject {
    static let shared = InventoryModel()

    @Published private(set) var availability: ModelAvailability = .unsupportedOS
    @Published var keepLoaded: Bool = UserDefaults.standard.bool(forKey: "tally.keepLoaded") {
        didSet { UserDefaults.standard.set(keepLoaded, forKey: "tally.keepLoaded"); if keepLoaded { prewarm() } }
    }
    @Published var preferCloud: Bool = UserDefaults.standard.bool(forKey: "tally.preferCloud") {
        didSet { UserDefaults.standard.set(preferCloud, forKey: "tally.preferCloud") }
    }
    /// Photos: the on-device model can't see pixels until the iOS 27 SDK, so when a Claude key
    /// exists, send the photo itself to the cloud model (true item detection) unless turned off.
    @Published var photoUsesCloud: Bool = UserDefaults.standard.object(forKey: "tally.photoCloud") as? Bool ?? true {
        didSet { UserDefaults.standard.set(photoUsesCloud, forKey: "tally.photoCloud") }
    }

    private var parseSession: LanguageModelSession?
    private var summarySession: LanguageModelSession?
    let onDeviceModelName = "Apple on-device model"

    private init() { refreshAvailability() }

    func refreshAvailability() {
        switch SystemLanguageModel.default.availability {
        case .available: availability = .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: availability = .notEligible
            case .appleIntelligenceNotEnabled: availability = .intelligenceOff
            case .modelNotReady: availability = .notReady
            @unknown default: availability = .notReady
            }
        }
        if keepLoaded && availability == .ready { prewarm() }
    }

    var usesOnDevice: Bool { availability == .ready && !(preferCloud && ClaudeService.hasAPIKey) }

    private func makeSession() -> LanguageModelSession {
        if let parseSession { return parseSession }
        let s = LanguageModelSession(instructions: """
            You turn a warehouse counter's notes into inventory sheet rows: one row per distinct kind \
            of item. Rules:
            - count is the TOTAL number of units of that item. When the notes give a structure \
              (e.g. "three shelves with thirty bins each"), multiply carefully: 3 × 30 = 90.
            - countIsEstimate is true ONLY when the counter says about/roughly/approximately, or says \
              they could not see everything. A plain number is NOT an estimate.
            - itemName: two to four words, singular ("blue storage bin").
            - attributes: size, shape, colour only, a few words.
            - annotation: short facts the counter actually stated (condition, damage, packaging, \
              shelf layout), under 15 words. Leave it EMPTY when nothing was stated. Never copy \
              wording from these instructions.
            - location: the default location unless the note names another.
            - confidence: 90–100 when the note is explicit, lower when you inferred or guessed.
            Never invent items the counter did not mention.
            """)
        parseSession = s
        return s
    }

    private func makeSummarySession() -> LanguageModelSession {
        if let summarySession { return summarySession }
        let s = LanguageModelSession(instructions: "You summarise warehouse inventory counts for a manager in plain prose. Two short paragraphs, under 150 words, no headings.")
        summarySession = s
        return s
    }

    /// A session rejects overlapping requests; wait briefly for the previous one to finish.
    private func awaitIdle(_ s: LanguageModelSession) async {
        var tries = 0
        while s.isResponding && tries < 50 { try? await Task.sleep(for: .milliseconds(100)); tries += 1 }
    }

    /// Readable text for Foundation Models failures.
    static func describe(_ error: Error) -> String {
        if let g = error as? LanguageModelSession.GenerationError {
            switch g {
            case .exceededContextWindowSize: return "Too much text for the on-device model in one go. Summarise fewer rows."
            case .assetsUnavailable: return "The on-device model assets are not available yet. Check Apple Intelligence in Settings."
            case .guardrailViolation: return "The on-device model declined this content (guardrail)."
            case .unsupportedGuide: return "Internal: unsupported generation guide."
            case .unsupportedLanguageOrLocale: return "The on-device model does not support this language."
            case .decodingFailure: return "The on-device model returned something unreadable. Try again."
            case .rateLimited: return "The on-device model is busy. Try again in a moment."
            case .concurrentRequests: return "The on-device model is still working on the previous request."
            case .refusal: return "The on-device model refused this request."
            @unknown default: return "On-device model error: \(g.localizedDescription)"
            }
        }
        let text = error.localizedDescription
        if text.contains("GenerationError") {
            return "The on-device model could not run here. On the iOS Simulator this is a known runtime/host mismatch (the model itself works on this Mac); run on an iPhone with Apple Intelligence, or add a Claude API key in Model & sync for the cloud fallback."
        }
        return text
    }

    func prewarm() {
        guard availability == .ready else { return }
        makeSession().prewarm()
        makeSummarySession().prewarm()
    }

    // MARK: - Parse

    func parse(text: String, photo: PhotoAnalysis? = nil, imageJPEG: Data?,
               defaultLocation: ItemLocation, knownLocations: [String]) async throws -> ParseResult {
        let notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let codes = photo?.codes ?? []

        // Photo + Claude key → send the picture itself (real item detection, colours, materials).
        if imageJPEG != nil, photoUsesCloud, ClaudeService.hasAPIKey {
            let r = try await ClaudeService.extractEntries(
                text: contextBlock(notes: notes, photo: photo, codes: codes, defaultLocation: defaultLocation, knownLocations: knownLocations),
                imageJPEG: imageJPEG, defaultLocation: defaultLocation.display, knownLocations: knownLocations)
            return ParseResult(rows: r.entries.map(Self.row(from:)), sceneDescription: r.photoDescription,
                               modelName: AppConfig.claudeModel, items: r.items.map(Self.item(from:)))
        }

        var prompt = contextBlock(notes: notes, photo: photo, codes: codes, defaultLocation: defaultLocation, knownLocations: knownLocations)
        if let photo {
            prompt += """


            This came from a PHOTO analysed on device (you cannot see pixels — only the detections above).
            Rules for photos:
            - Each DETECTED ITEM is one physical container/product. Make ONE row per item, or one row per
              distinct label when several items share a label (then count = how many share it).
            - Use the item's given name verbatim as itemName (it is already cleaned); only fix an
              obvious OCR typo. Put its kind (if given) and colour in attributes.
            - If one name clearly contains TWO product names, make two rows.
            - Signage/menu text is context only — never a row.
            - annotation stays empty unless the counter's notes say something about that item.
            - If no items were detected, make one row per whole-frame label line instead.
            - count = 1 per container unless the notes say otherwise. Do not invent items.
            - sceneDescription: one sentence from the scene tags and labels (e.g. "Display case of gelato pans").
            """
            _ = photo.sceneTags
        }
        if !notes.isEmpty { prompt += "\n\nCounter's notes:\n\(notes)" }

        if usesOnDevice {
            let s = makeSession()
            await awaitIdle(s)
            let r: LanguageModelSession.Response<GeneratedRows>
            do {
                r = try await s.respond(to: prompt, generating: GeneratedRows.self,
                                        options: GenerationOptions(sampling: .greedy))
            } catch {
                parseSession = nil
                throw ModelFailure(message: InventoryModel.describe(error))
            }
            return ParseResult(
                rows: r.content.rows.map { ParsedRow(itemName: $0.itemName, count: max(0, $0.count), countIsEstimate: $0.countIsEstimate,
                                                     attributes: $0.attributes, annotation: $0.annotation,
                                                     location: $0.location.isEmpty ? defaultLocation.display : $0.location,
                                                     confidence: min(100, max(0, $0.confidence))) },
                sceneDescription: r.content.sceneDescription, modelName: onDeviceModelName, items: photo?.items ?? [])
        }
        if ClaudeService.hasAPIKey {
            let r = try await ClaudeService.extractEntries(text: prompt, imageJPEG: imageJPEG,
                                                           defaultLocation: defaultLocation.display, knownLocations: knownLocations)
            return ParseResult(rows: r.entries.map(Self.row(from:)), sceneDescription: r.photoDescription,
                               modelName: AppConfig.claudeModel, items: r.items.isEmpty ? (photo?.items ?? []) : r.items.map(Self.item(from:)))
        }
        throw availability == .ready ? ModelError.noModel : ModelError.onDeviceUnavailable(availability)
    }

    /// Shared context: location, known locations, barcodes, and the structured photo detections.
    private func contextBlock(notes: String, photo: PhotoAnalysis?, codes: [ScannedCode],
                              defaultLocation: ItemLocation, knownLocations: [String]) -> String {
        var c = "Default location: \(defaultLocation.display)."
        if !knownLocations.isEmpty { c += " Known locations: \(knownLocations.joined(separator: "; "))." }
        if !codes.isEmpty { c += " Barcodes seen: " + codes.map { "\($0.type.rawValue.uppercased()) \($0.value)" }.joined(separator: ", ") + "." }
        guard let photo else { return c }
        if !photo.sceneTags.isEmpty { c += "\nScene tags (on-device classifier): \(photo.sceneTags.joined(separator: ", "))." }
        if !photo.items.isEmpty {
            c += "\nDETECTED ITEMS (\(photo.items.count), reading order top-left → bottom-right):"
            for (i, it) in photo.items.enumerated() {
                c += "\n  \(i + 1). \(it.summaryLine.isEmpty ? "container, no readable label" : it.summaryLine)"
            }
        }
        if !photo.signage.isEmpty { c += "\nSignage / menu text NOT on the item rail (context only, not items): " + photo.signage.joined(separator: " | ") }
        if photo.items.isEmpty, !photo.text.isEmpty { c += "\nWhole-frame label text (one line per label, may contain OCR errors):\n\(photo.text)" }
        return c
    }

    private static func row(from e: ExtractedEntry) -> ParsedRow {
        ParsedRow(itemName: e.itemName, count: e.count, countIsEstimate: e.countIsEstimate, attributes: e.sizeShapeColor,
                  annotation: e.annotation, location: e.location, confidence: e.confidence)
    }
    private static func item(from i: ExtractedItem) -> DetectedItem {
        // Claude reports boxes as fractions with origin top-left; Vision uses origin bottom-left.
        let box = CGRect(x: i.x, y: 1 - i.y - i.h, width: i.w, height: i.h)
        return DetectedItem(box: box, labelText: i.labelText, tags: [], color: i.color, name: i.name, material: i.material, count: i.count)
    }

    // MARK: - Summary

    func summarize(entries: [CountEntry]) async throws -> (text: String, model: String) {
        let items = entries.filter { $0.kind == .entry }
        // Precompute the arithmetic — the on-device model narrates, it does not add.
        let distinct = Set(items.map { $0.itemName.lowercased() }).count
        let units = items.reduce(0) { $0 + $1.count }
        let estimates = items.filter(\.countIsEstimate)
        let byLocation = Dictionary(grouping: items, by: { $0.location.display })
            .map { "\($0.key): \($0.value.reduce(0) { $0 + $1.count }) units in \($0.value.count) rows" }
            .sorted().joined(separator: "; ")
        let byItem = Dictionary(grouping: items, by: { $0.itemName })
            .map { "\($0.key): \($0.value.reduce(0) { $0 + $1.count })\($0.value.contains { $0.countIsEstimate } ? " (includes an estimate)" : "")" }
            .sorted().joined(separator: "; ")
        let notes = items.filter { !$0.annotation.isEmpty }.map { "\($0.itemName) — \($0.annotation)" }.joined(separator: "; ")
        let prompt = """
        Facts (already computed, use them exactly as given, do not recompute):
        - Distinct item types: \(distinct). Total units: \(units).
        - Totals per item: \(byItem).
        - Totals per location: \(byLocation).
        - Estimated counts: \(estimates.isEmpty ? "none" : estimates.map { "\($0.itemName) ≈\($0.count)" }.joined(separator: ", ")).
        - Rows flagged for review: \(items.filter(\.needsReview).count).
        - Counter's notes: \(notes.isEmpty ? "none" : notes).

        Write two short paragraphs for the manager: first what was counted, then notable observations \
        (damage, estimates, anything to re-check). Under 120 words. Plain prose, no headings, no lists.
        """
        if usesOnDevice {
            let s = makeSummarySession()
            await awaitIdle(s)
            do {
                let r = try await s.respond(to: prompt)
                return (r.content.trimmingCharacters(in: .whitespacesAndNewlines), onDeviceModelName)
            } catch {
                summarySession = nil   // a failed session can be left unusable; start fresh next time
                throw ModelFailure(message: InventoryModel.describe(error))
            }
        }
        if ClaudeService.hasAPIKey {
            return (try await ClaudeService.summarize(prompt: prompt), AppConfig.claudeModel)
        }
        throw availability == .ready ? ModelError.noModel : ModelError.onDeviceUnavailable(availability)
    }
}
