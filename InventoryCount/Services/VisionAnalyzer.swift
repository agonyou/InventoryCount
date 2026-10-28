//  VisionAnalyzer.swift
//  On-device photo pipeline, two stages:
//    1. Item detection — rectangular containers (pans, bins, boxes) via Vision rectangles with
//       overlap suppression. Boxes are normalized, origin bottom-left (Vision convention).
//    2. Per-item sub-detection — OCR of the label under/inside the item (3× upscaled crop),
//       image-classification tags (what it is / material hints), dominant colour.
//  Plus whole-frame OCR, barcodes and scene tags. Everything here runs with no network.

import Foundation
import UIKit
import Vision
import CoreImage

struct DetectedItem: Identifiable, Hashable {
    let id = UUID()
    var box: CGRect              // normalized, origin bottom-left
    var labelText: String        // OCR near/under the item (cleaned product name)
    var kind: String = ""        // category word stripped from the label ("ice cream", "gelato"…)
    var tags: [String]           // classification identifiers, best first
    var color: String            // dominant colour name
    var name: String = ""        // filled by a vision model (cloud) when available
    var material: String = ""    // filled by a vision model (cloud) when available
    var count: Int = 1

    var summaryLine: String {
        var parts: [String] = []
        if !name.isEmpty { parts.append(name) }
        if !labelText.isEmpty { parts.append("name \"\(labelText)\"") }
        if !kind.isEmpty { parts.append("kind \(kind)") }
        if !color.isEmpty { parts.append("colour \(color)") }
        if !material.isEmpty { parts.append("material \(material)") }
        if !tags.isEmpty { parts.append("looks like \(tags.prefix(3).joined(separator: "/"))") }
        if count != 1 { parts.append("count \(count)") }
        return parts.joined(separator: ", ")
    }
}

struct PhotoAnalysis {
    var codes: [ScannedCode] = []
    var text: String = ""                // whole-frame OCR, line per label
    var sceneTags: [String] = []         // whole-frame classification
    var signage: [String] = []           // label cards NOT on the item rail (menu boards, signs)
    var items: [DetectedItem] = []
    var bins: [CGRect] { items.map(\.box) }
}

enum VisionAnalyzer {
    static func analyze(_ image: UIImage) async -> PhotoAnalysis {
        guard let cg = image.cgImage else { return PhotoAnalysis() }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: analyzeSync(cg, orientation: image.cgOrientation))
            }
        }
    }

    /// The iPad build running on a Mac: Vision's GPU paths trip a Metal API validation assertion
    /// under Xcode (managed-vs-shared buffer sync). Keep to CPU-safe requests there.
    static var isRunningOnMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }

    /// Pin every compute stage of a request to a CPU device (replaces the deprecated usesCPUOnly).
    private static func forceCPU(_ request: VNRequest) {
        let stages = (try? request.supportedComputeStageDevices) ?? [:]
        for (stage, devices) in stages {
            if let cpu = devices.first(where: { if case .cpu = $0 { return true } else { return false } }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
    }

    private static func analyzeSync(_ cg: CGImage, orientation: CGImagePropertyOrientation) -> PhotoAnalysis {
        var result = PhotoAnalysis()
        // Normalize orientation once so crops and boxes agree.
        let img = oriented(cg, orientation)
        let W = CGFloat(img.width), H = CGFloat(img.height)

        // Whole-frame: barcodes, OCR (3× upscale for small shelf labels), scene tags
        let barcodes = VNDetectBarcodesRequest()
        barcodes.symbologies = [.qr, .upce, .ean13, .ean8]
        let scene = VNClassifyImageRequest()
        let rects = VNDetectRectanglesRequest()
        if isRunningOnMac { forceCPU(scene); forceCPU(rects); forceCPU(barcodes) }
        rects.maximumObservations = 40
        rects.minimumSize = 0.04
        rects.minimumConfidence = 0.4
        rects.minimumAspectRatio = 0.3
        rects.quadratureTolerance = 40
        try? VNImageRequestHandler(cgImage: img, options: [:]).perform([barcodes, scene, rects])

        for b in barcodes.results ?? [] {
            guard let v = b.payloadStringValue else { continue }
            let kind: ScannedCode.Kind
            switch b.symbology {
            case .qr: kind = .qr
            case .upce: kind = .upc
            default: kind = (v.count == 12 ? .upc : .ean)
            }
            result.codes.append(ScannedCode(type: kind, value: v))
        }
        result.sceneTags = (scene.results ?? []).filter { $0.confidence > 0.25 }.prefix(6).map(\.identifier)

        // Tiled OCR at native resolution: Vision downsamples big frames internally, which loses
        // small shelf labels; ~1400px tiles with 15% overlap keep them readable.
        let frameLines = tiledOCR(img)
        result.text = frameLines.map(\.text).joined(separator: "\n")

        // Stage 1: item detection cascade → candidate boxes (normalized, origin bottom-left)
        //   a) label-anchored: text regions clustered into label cards; each card = one item whose
        //      box extends upward over the product it sits under (shelf / display-case scenes)
        //   b) foreground instances (subject lifting): any shape — tubs, bottles, bags — as masks
        //   c) rectangles: bins, boxes, pans (fallback / supplement)
        // Merged with overlap suppression. `source` is kept for the per-item colour sampling.
        var candidates: [(box: CGRect, source: String, label: String)] = []

        // a) label cards → the label rail (the horizontal band holding the most cards). Other
        //    bands (menu boards, signs) are kept as signage context, not items.
        let cards = labelCards(from: frameLines)
        let rail = labelRail(cards)
        result.signage = cards.filter { c in !rail.contains { $0.box == c.box } }.map(\.text).filter { !$0.isEmpty }
        if rail.count >= 2 {
            // Rails can be staggered: two sub-rows of labels (front pans / back pans). Sub-row 0 is the
            // lowest; each higher sub-row's product sits one pan-row further back (above in the frame).
            let railMinY = rail.map(\.box.midY).min() ?? 0
            let subRow: (LabelCard) -> Int = { c in Int(((c.box.midY - railMinY) / 0.025).rounded()) }
            let panHeight: CGFloat = max(0.12, (rail.map(\.box.height).max() ?? 0.02) * 4)
            let sortedCards = rail.sorted { $0.box.minX < $1.box.minX }
            for (i, c) in sortedCards.enumerated() {
                // Horizontal extent: halfway to the neighbouring cards in the same sub-row
                let sameRow = sortedCards.filter { subRow($0) == subRow(c) }
                let idx = sameRow.firstIndex { $0.box == c.box } ?? 0
                let left = idx > 0 ? (sameRow[idx - 1].box.maxX + c.box.minX) / 2 : max(0, c.box.minX - c.box.width * 0.6)
                let right = idx + 1 < sameRow.count ? (c.box.maxX + sameRow[idx + 1].box.minX) / 2 : min(1, c.box.maxX + c.box.width * 0.6)
                let bottom = c.box.maxY + CGFloat(subRow(c)) * panHeight
                let box = CGRect(x: left, y: bottom, width: max(0.02, right - left), height: min(1 - bottom, panHeight))
                _ = i
                candidates.append((box, "label", c.text))
            }
        }

        // b) foreground instances (GPU-backed; skipped when the iPad build runs on a Mac)
        if !isRunningOnMac {
            for box in foregroundInstanceBoxes(img) where box.width * box.height < 0.5 {
                candidates.append((box, "mask", ""))
            }
        }

        // c) rectangles (only when the first two found little)
        if candidates.count < 2 {
            let rawBoxes: [CGRect] = (rects.results ?? []).map { $0.boundingBox }
            for b in rawBoxes {
                let okWidth = b.width < 0.6 && b.width > 0.04
                let okHeight = b.height < 0.85 && b.height > 0.05
                if okWidth && okHeight { candidates.append((b, "rect", "")) }
            }
        }

        // Overlap suppression: label-anchored first, then masks, then rectangles; larger first within a source
        let priority: [String: Int] = ["label": 0, "mask": 1, "rect": 2]
        candidates.sort { a, b in
            let pa = priority[a.source] ?? 9, pb = priority[b.source] ?? 9
            if pa != pb { return pa < pb }
            let areaA: CGFloat = a.box.width * a.box.height
            let areaB: CGFloat = b.box.width * b.box.height
            return areaA > areaB
        }
        var kept: [(box: CGRect, source: String, label: String)] = []
        for c in candidates {
            var overlaps = false
            for k in kept {
                let i = k.box.intersection(c.box)
                if i.isNull { continue }
                let minA = min(k.box.width * k.box.height, c.box.width * c.box.height)
                if (i.width * i.height) / minA >= 0.4 { overlaps = true; break }
            }
            if !overlaps { kept.append(c) }
        }
        kept.sort { (a, b) -> Bool in
            let dy: CGFloat = abs(a.box.midY - b.box.midY)
            if dy > 0.08 { return a.box.midY > b.box.midY }
            return a.box.minX < b.box.minX
        }

        // Stage 2: per-item sub-detection
        for cand in kept.prefix(24) {
            let k = cand.box
            let px = CGRect(x: k.minX * W, y: (1 - k.maxY) * H, width: k.width * W, height: k.height * H)
            let cleaned = LabelCleaner.clean(cand.label)
            if cand.source == "label" && cleaned.name.isEmpty { continue }   // category-only fragment / garbage → not an item
            var item = DetectedItem(box: k, labelText: cleaned.name, kind: cleaned.kind, tags: [], color: "")
            if cand.source != "label" {
                // Label crop: the item plus 70% of its height below it (shelf labels sit under items)
                let ext = CGRect(x: px.minX - px.width * 0.1, y: px.minY, width: px.width * 1.2, height: px.height * 1.7)
                    .intersection(CGRect(x: 0, y: 0, width: W, height: H))
                if let crop = img.cropping(to: ext) {
                    let lines = ocr(upscale(crop, 3), minHeight: 0.02)
                    item.labelText = lines.joined(separator: " ")
                }
            }
            // Colour/tags from the product area: for label-anchored items skip the card itself (bottom third)
            let productPx = cand.source == "label"
                ? CGRect(x: px.minX, y: px.minY, width: px.width, height: px.height * 0.66)
                : px
            if let itemOnly = img.cropping(to: productPx) {
                item.color = dominantColorName(itemOnly)
                let cls = VNClassifyImageRequest()
                if isRunningOnMac { forceCPU(cls) }
                try? VNImageRequestHandler(cgImage: itemOnly, options: [:]).perform([cls])
                item.tags = (cls.results ?? []).filter { $0.confidence > 0.3 }.prefix(4).map(\.identifier)
            }
            result.items.append(item)
        }
        return result
    }

    // MARK: - stage-1 detectors

    private struct LabelCard { var box: CGRect; var text: String }
    private struct TextLine { var box: CGRect; var text: String }

    /// OCR in overlapping native-resolution tiles; boxes normalized to the frame (origin bottom-left).
    private static func tiledOCR(_ img: CGImage) -> [TextLine] {
        let W = CGFloat(img.width), H = CGFloat(img.height)
        let tile: CGFloat = 1400, overlap: CGFloat = 0.15
        var lines: [TextLine] = []
        var y: CGFloat = 0
        while y < H {
            var x: CGFloat = 0
            while x < W {
                let r = CGRect(x: x, y: y, width: min(tile, W - x), height: min(tile, H - y))
                if let crop = img.cropping(to: r) {
                    let req = VNRecognizeTextRequest()
                    req.recognitionLevel = .accurate
                    req.usesLanguageCorrection = true
                    req.recognitionLanguages = ["en-US"]
                    if isRunningOnMac { forceCPU(req) }
                    try? VNImageRequestHandler(cgImage: crop, options: [:]).perform([req])
                    for o in req.results ?? [] {
                        guard let t = o.topCandidates(1).first?.string, t.count >= 2 else { continue }
                        let b = o.boundingBox
                        let fx = (r.minX + b.minX * r.width) / W
                        let fyTop = r.minY + (1 - b.maxY) * r.height
                        let fb = CGRect(x: fx, y: 1 - (fyTop + b.height * r.height) / H,
                                        width: b.width * r.width / W, height: b.height * r.height / H)
                        lines.append(TextLine(box: fb, text: t))
                    }
                }
                x += tile * (1 - overlap)
            }
            y += tile * (1 - overlap)
        }
        // Drop duplicates produced by the tile overlap
        var uniq: [TextLine] = []
        for l in lines {
            let dup = uniq.contains { u in
                let i = u.box.intersection(l.box)
                if i.isNull { return false }
                let minA = min(u.box.width * u.box.height, l.box.width * l.box.height)
                return (i.width * i.height) / minA > 0.5
            }
            if !dup { uniq.append(l) }
        }
        return uniq
    }

    /// Stack vertically adjacent lines with strong horizontal overlap into one label card
    /// (e.g. "COOKIE DOUGH" over "ICE CREAM"). Horizontal neighbours stay separate cards.
    private static func labelCards(from lines: [TextLine]) -> [LabelCard] {
        var cards: [(box: CGRect, lines: [TextLine])] = []
        for l in lines.sorted(by: { $0.box.minX < $1.box.minX }) {
            var merged = false
            for i in cards.indices {
                let c = cards[i].box
                let xo = min(c.maxX, l.box.maxX) - max(c.minX, l.box.minX)
                let stacked = xo > 0.5 * min(c.width, l.box.width) && abs(c.midY - l.box.midY) < (c.height + l.box.height) * 1.1
                if stacked { cards[i].box = c.union(l.box); cards[i].lines.append(l); merged = true; break }
            }
            if !merged { cards.append((l.box, [l])) }
        }
        return cards.map { c in
            let text = c.lines.sorted { a, b in
                let dy: CGFloat = abs(a.box.midY - b.box.midY)
                if dy > 0.005 { return a.box.midY > b.box.midY }
                return a.box.minX < b.box.minX
            }.map(\.text).joined(separator: " ")
            return LabelCard(box: c.box, text: text)
        }
        .filter { $0.box.width < 0.5 && $0.box.height < 0.3 }
    }

    /// The horizontal band (cards within ±0.035 of each other vertically, allowing a staggered
    /// second sub-row) holding the most cards. Needs ≥ 3 cards to count as a rail.
    private static func labelRail(_ cards: [LabelCard]) -> [LabelCard] {
        var bands: [[LabelCard]] = []
        for c in cards.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let i = bands.lastIndex(where: { abs($0[0].box.midY - c.box.midY) < 0.05 }) { bands[i].append(c) }
            else { bands.append([c]) }
        }
        let best = bands.max { $0.count < $1.count } ?? []
        return best.count >= 3 ? best : []
    }

    /// Subject-lifting instance masks → bounding boxes (any shape). Skips instances that cover most of the frame.
    private static func foregroundInstanceBoxes(_ img: CGImage) -> [CGRect] {
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        try? handler.perform([req])
        guard let obs = req.results?.first else { return [] }
        var boxes: [CGRect] = []
        for inst in obs.allInstances {
            guard let mask = try? obs.generateScaledMaskForImage(forInstances: IndexSet(integer: inst), from: handler) else { continue }
            CVPixelBufferLockBaseAddress(mask, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
            let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
            let stride = CVPixelBufferGetBytesPerRow(mask) / MemoryLayout<Float>.size
            guard let base = CVPixelBufferGetBaseAddress(mask)?.assumingMemoryBound(to: Float.self) else { continue }
            var minX = w, maxX = -1, minY = h, maxY = -1, n = 0
            var y = 0
            while y < h {
                var x = 0
                while x < w {
                    if base[y * stride + x] > 0.5 {
                        n += 1
                        if x < minX { minX = x }; if x > maxX { maxX = x }
                        if y < minY { minY = y }; if y > maxY { maxY = y }
                    }
                    x += 4
                }
                y += 4
            }
            guard maxX >= 0, n * 16 > w * h / 400 else { continue }   // ≥0.25% of the frame
            let box = CGRect(x: CGFloat(minX) / CGFloat(w), y: 1 - CGFloat(maxY) / CGFloat(h),
                             width: CGFloat(maxX - minX) / CGFloat(w), height: CGFloat(maxY - minY) / CGFloat(h))
            if box.width * box.height < 0.6 { boxes.append(box) }
        }
        return boxes
    }

    // MARK: - helpers

    private static func ocr(_ img: CGImage, minHeight: Float) -> [String] {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.minimumTextHeight = minHeight
        text.recognitionLanguages = ["en-US"]
        if isRunningOnMac { forceCPU(text) }
        try? VNImageRequestHandler(cgImage: img, options: [:]).perform([text])
        return (text.results ?? [])
            .sorted { (a: VNRecognizedTextObservation, b: VNRecognizedTextObservation) -> Bool in
                let dy: CGFloat = abs(a.boundingBox.midY - b.boundingBox.midY)
                if dy > 0.02 { return a.boundingBox.midY > b.boundingBox.midY }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { $0.trimmingCharacters(in: .whitespaces).count >= 2 }
    }

    private static func upscale(_ img: CGImage, _ f: Int) -> CGImage {
        guard f > 1 else { return img }
        let w = img.width * f, h = img.height * f
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return img }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? img
    }

    private static func oriented(_ cg: CGImage, _ o: CGImagePropertyOrientation) -> CGImage {
        guard o != .up else { return cg }
        let ci = CIImage(cgImage: cg).oriented(o)
        return ciContext.createCGImage(ci, from: ci.extent) ?? cg
    }

    // Software renderer: the 1×1 average needs no GPU, and avoids a Metal validation assertion
    // (managed-vs-shared buffer sync) seen when the iPad build runs on a Mac with API validation on.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: true])
    private static func dominantColorName(_ img: CGImage) -> String {
        let c = CIImage(cgImage: img)
        guard let f = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: c, kCIInputExtentKey: CIVector(cgRect: c.extent)]),
              let out = f.outputImage else { return "" }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let col = UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        col.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        if s < 0.12 { return v > 0.8 ? "white" : v > 0.45 ? "grey/silver" : "black" }
        let names = ["red", "orange", "yellow", "yellow-green", "green", "teal", "cyan", "blue", "violet", "magenta", "pink", "red"]
        let base = names[min(11, Int(h * 11))]
        return (v > 0.75 && s < 0.4 ? "pale " : "") + base
    }
}

extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up; case .down: return .down; case .left: return .left; case .right: return .right
        case .upMirrored: return .upMirrored; case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored; case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
    /// Downscale to max 1280px on the long edge and JPEG-encode (model input + CBL blob).
    func inventoryJPEG(maxEdge: CGFloat = 1280, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let img = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return img.jpegData(compressionQuality: quality)
    }
}

/// Deterministic clean-up of OCR'd shelf labels so the text model gets a product name, not noise.
enum LabelCleaner {
    static let categories = ["ICE CREAM", "GELATO", "SORBETTO", "SORBET", "FROZEN YOGURT", "YOGURT"]
    static let debris: Set<String> = ["LEE", "NCE", "CREAS", "CE"]          // never real words — always dropped
    static let categoryFragments: Set<String> = ["ICE", "CREAM"]             // dropped only when the label is just a fragment

    static func clean(_ raw: String) -> (name: String, kind: String) {
        var text = raw.uppercased()
        text = String(text.map { ch -> Character in
            (ch.isLetter && ch.isASCII) || ch.isNumber || ch == "&" || ch == " " ? ch : " "
        })
        var kind = ""
        for c in categories where text.contains(c) {
            kind = c.lowercased()
            text = text.replacingOccurrences(of: c, with: " ")
        }
        var words = text.split(separator: " ").map(String.init).filter { w in
            w == "&" || (!debris.contains(w) && w.filter(\.isLetter).count >= 2)
        }
        if words.count <= 2 { words = words.filter { !categoryFragments.contains($0) } }
        // Drop OCR debris: ≥4-letter words with no vowel
        let kept = words.filter { w in w == "&" || w.count < 4 || w.rangeOfCharacter(from: CharacterSet(charactersIn: "AEIOUY")) != nil }
        let letters = kept.joined().filter(\.isLetter).count
        guard letters >= 3 else { return ("", kind) }
        let name = kept.map { w in w == "&" ? "&" : w.prefix(1) + w.dropFirst().lowercased() }.joined(separator: " ")
        return (name, kind)
    }
}
