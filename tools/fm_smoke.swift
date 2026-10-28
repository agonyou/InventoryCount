import Foundation
import FoundationModels

@Generable(description: "One row of an inventory sheet")
struct GeneratedRow {
    @Guide(description: "Short product or item name") var itemName: String
    @Guide(description: "Number of units; 0 if unknown") var count: Int
    @Guide(description: "true when the count is an estimate") var countIsEstimate: Bool
    @Guide(description: "Size, shape and color in a few words") var attributes: String
    @Guide(description: "Details worth recording") var annotation: String
    @Guide(description: "Location as 'site / rack / shelf / bin'") var location: String
    @Guide(description: "Confidence 0 to 100") var confidence: Int
}
@Generable(description: "Rows extracted from a counter's notes")
struct GeneratedRows { var sceneDescription: String; var rows: [GeneratedRow] }

let sem = DispatchSemaphore(value: 0)
Task {
    print("availability:", SystemLanguageModel.default.availability)
    let s = LanguageModelSession(instructions: """
            You turn a warehouse counter's notes into inventory sheet rows: one row per distinct kind \
            of item. Rules:
            - count is the TOTAL number of units of that item. When the notes give a structure \
              (e.g. "three shelves with thirty bins each"), multiply carefully: 3 × 30 = 90.
            - countIsEstimate is true ONLY when the counter says about/roughly/approximately, or says \
              they could not see everything. A plain number is NOT an estimate.
            - itemName: two to four words, singular ("blue storage bin").
            - attributes: size, shape, colour only, a few words.
            - annotation: short facts worth recording (condition, damage, packaging, layout such as \
              "3 shelves × 30"), under 15 words. Do not repeat the whole note.
            - location: the default location unless the note names another.
            - confidence: 90–100 when the note is explicit, lower when you inferred or guessed.
            Never invent items the counter did not mention.
            """)
    let prompt = "Default location: Location X / A / S2 / B15.\n\nCounter's notes:\nrack seven has three shelves with thirty blue bins each, about a dozen brown cartons on top I can't fully see, two of the bins are cracked"
    do {
        let t0 = Date()
        let r = try await s.respond(to: prompt, generating: GeneratedRows.self, options: GenerationOptions(sampling: .greedy))
        print(String(format: "took %.1fs", Date().timeIntervalSince(t0)))
        for row in r.content.rows { print("-", row.itemName, "|", row.countIsEstimate ? "≈" : "", row.count, "|", row.attributes, "|", row.annotation, "|", row.location, "|", row.confidence) }
    } catch { print("ERROR:", error) }
    sem.signal()
}
sem.wait()
