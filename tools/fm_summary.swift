import Foundation
import FoundationModels

@Generable(description: "Inventory summary")
struct GeneratedSummary {
    @Guide(description: "Two short paragraphs: what was counted, then notable observations")
    var summary: String
}
let sem = DispatchSemaphore(value: 0)
Task {
    let rows = """
    - Blue storage bin | 30 | Medium · rectangular · blue | Three shelves of 30 bins; two bins cracked | @ Location X / A / S2 / B15
    - Cardboard carton | ≈12 | Large · brown | Top shelf, partly hidden | @ Location X / A / S2 / B15 | NEEDS REVIEW
    - Blue storage bin | 28 | Medium · rectangular · blue |  | @ Location X / A / S2 / B15
    """
    let prompt = """
    Summarize this inventory count in two short paragraphs: first what was counted (distinct item \
    types, total units, locations covered), then notable observations (damage, low stock, estimates, \
    anomalies, items to re-check). Under 150 words.

    Rows:
    \(rows)
    """
    for (label, useSchema) in [("typed", true), ("plain", false)] {
        let s = LanguageModelSession(instructions: "You summarise warehouse inventory counts for a manager.")
        do {
            let t0 = Date()
            if useSchema {
                let r = try await s.respond(to: prompt, generating: GeneratedSummary.self)
                print("[\(label)] ok \(String(format: "%.1fs", Date().timeIntervalSince(t0)))\n\(r.content.summary)\n")
            } else {
                let r = try await s.respond(to: prompt)
                print("[\(label)] ok \(String(format: "%.1fs", Date().timeIntervalSince(t0)))\n\(r.content)\n")
            }
        } catch let e as LanguageModelSession.GenerationError {
            print("[\(label)] GenerationError:", e, "|", e.errorDescription ?? "", "|", e.failureReason ?? "", "|", e.recoverySuggestion ?? "")
        } catch { print("[\(label)] other error:", error) }
    }
    sem.signal()
}
sem.wait()
