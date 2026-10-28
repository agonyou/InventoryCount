//  ClaudeService.swift
//  Optional cloud fallback (raw HTTP; no official Swift SDK). Key lives in the Keychain.

import Foundation

struct ExtractedEntry: Codable {
    var itemName: String
    var count: Int
    var countIsEstimate: Bool
    var sizeShapeColor: String
    var annotation: String
    var location: String
    var confidence: Int
}
struct ExtractedItem: Codable {
    var name: String; var labelText: String; var color: String; var material: String; var count: Int
    var x: Double; var y: Double; var w: Double; var h: Double     // fractions of the image, origin top-left
}
struct ExtractionResult: Codable { var entries: [ExtractedEntry]; var photoDescription: String; var items: [ExtractedItem] }

enum ClaudeError: LocalizedError {
    case missingAPIKey, http(Int, String), refusal(String), badResponse
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:      return "No Claude API key. Add one in Model & sync."
        case .http(let c, let m): return "Claude API error \(c): \(m)"
        case .refusal(let r):     return "Claude declined the request: \(r)"
        case .badResponse:        return "Unexpected response from Claude."
        }
    }
}

enum ClaudeService {
    static let keychainAccount = "anthropic-api-key"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static var apiKey: String? { KeychainHelper.load(for: keychainAccount) }
    static func saveAPIKey(_ key: String) { KeychainHelper.save(password: key, for: keychainAccount) }
    static func clearAPIKey() { KeychainHelper.delete(for: keychainAccount) }
    static var hasAPIKey: Bool { !(apiKey ?? "").isEmpty }

    static func extractEntries(text: String, imageJPEG: Data?, defaultLocation: String,
                               knownLocations: [String]) async throws -> ExtractionResult {
        var content: [[String: Any]] = []
        if let imageJPEG {
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                                         "data": imageJPEG.base64EncodedString()]])
        }
        var prompt = """
        You are helping a warehouse counter build an inventory sheet. Produce one row per distinct set \
        of items. Fields: itemName, count (integer, 0 if unknown), countIsEstimate (true for 'about', \
        partially visible, or inferred counts), sizeShapeColor, annotation (condition, labels, packaging, \
        notes like '3 shelves of 30 bins'), location ('site / rack / shelf / bin'; default \
        "\(defaultLocation)"), confidence 0-100.
        """
        if imageJPEG != nil {
            prompt += """

            A photo is attached. First DETECT every distinct physical item or container (pan, bin, box, \
            bottle, pack…) visible, and for each give its bounding box as fractions of the image \
            (x, y = top-left corner, w, h; origin top-left), its name, the label text you can read on or \
            under it, its dominant colour, its material (steel, plastic, cardboard, glass, fabric, \
            unknown…), and how many identical units it holds (1 for a single container). Then produce the \
            inventory rows: one row per item, or one row per distinct product when several items are the \
            same product (count = how many). Describe the scene in photoDescription in one or two \
            sentences. If the notes and the photo disagree, trust the notes for counts.
            """
        } else { prompt += "\nNo photo: set photoDescription to an empty string and items to an empty array." }
        prompt += "\n\n" + text
        content.append(["type": "text", "text": prompt])

        let rowSchema: [String: Any] = [
            "type": "object",
            "properties": ["itemName": ["type": "string"], "count": ["type": "integer"],
                           "countIsEstimate": ["type": "boolean"], "sizeShapeColor": ["type": "string"],
                           "annotation": ["type": "string"], "location": ["type": "string"],
                           "confidence": ["type": "integer"]],
            "required": ["itemName", "count", "countIsEstimate", "sizeShapeColor", "annotation", "location", "confidence"],
            "additionalProperties": false]
        let itemSchema: [String: Any] = [
            "type": "object",
            "properties": ["name": ["type": "string"], "labelText": ["type": "string"], "color": ["type": "string"],
                           "material": ["type": "string"], "count": ["type": "integer"],
                           "x": ["type": "number"], "y": ["type": "number"], "w": ["type": "number"], "h": ["type": "number"]],
            "required": ["name", "labelText", "color", "material", "count", "x", "y", "w", "h"],
            "additionalProperties": false]
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["entries": ["type": "array", "items": rowSchema], "photoDescription": ["type": "string"],
                           "items": ["type": "array", "items": itemSchema]],
            "required": ["entries", "photoDescription", "items"], "additionalProperties": false]
        let body: [String: Any] = [
            "model": AppConfig.claudeModel, "max_tokens": 4096, "fallbacks": "default",
            "output_config": ["effort": "medium", "format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": content]]]
        let text = try await send(body)
        guard let data = text.data(using: .utf8) else { throw ClaudeError.badResponse }
        return try JSONDecoder().decode(ExtractionResult.self, from: data)
    }

    static func summarize(prompt: String) async throws -> String {
        try await send(["model": AppConfig.claudeModel, "max_tokens": 2048, "fallbacks": "default",
                        "output_config": ["effort": "low"],
                        "messages": [["role": "user", "content": prompt]]])
    }

    private static func send(_ body: [String: Any]) async throws -> String {
        guard let key = apiKey, !key.isEmpty else { throw ClaudeError.missingAPIKey }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"; req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }.flatMap { $0["message"] as? String }
                ?? String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.http(http.statusCode, msg)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeError.badResponse }
        if (json["stop_reason"] as? String) == "refusal" {
            throw ClaudeError.refusal((json["stop_details"] as? [String: Any])?["explanation"] as? String ?? "refused")
        }
        guard let blocks = json["content"] as? [[String: Any]],
              let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        else { throw ClaudeError.badResponse }
        return text
    }
}
