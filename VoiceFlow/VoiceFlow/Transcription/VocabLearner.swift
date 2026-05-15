import Foundation

// Phase 3 — Automatisches Vokabular-Lernen
actor VocabLearner {
    private static let maxEntries = 100
    private static let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voiceflow/vocab_cache.json")

    private var corrections: [String: String] = [:]
    private var keyOrder: [String] = []

    init() {
        let loaded = Self.loadFromDisk()
        let trimmed = Self.trim(corrections: loaded.corrections, keyOrder: loaded.keyOrder)
        corrections = trimmed.corrections
        keyOrder = trimmed.keyOrder
    }

    func learn(original: String, corrected: String) {
        let originalTerms = tokenize(original)
        let correctedTerms = tokenize(corrected)
        guard originalTerms.count == correctedTerms.count else { return }

        for (source, target) in zip(originalTerms, correctedTerms) {
            let sourceKey = source.lowercased()
            guard sourceKey != target.lowercased(), shouldLearn(target: target) else { continue }
            corrections[sourceKey] = target
            keyOrder.removeAll { $0 == sourceKey }
            keyOrder.append(sourceKey)
        }

        trimToLimit()
        save()
    }

    func applyCorrections(to text: String) -> String {
        var result = text
        for key in keyOrder {
            guard let replacement = corrections[key] else { continue }
            result = replaceWholeWord(key, with: replacement, in: result)
        }
        return result
    }

    var vocabulary: [String] {
        keyOrder.compactMap { corrections[$0] }
    }

    private static func loadFromDisk() -> (corrections: [String: String], keyOrder: [String]) {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return ([:], [])
        }
        return (decoded, decoded.keys.sorted())
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: Self.cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(corrections)
            try data.write(to: Self.cacheURL, options: .atomic)
        } catch {
            print("[VocabLearner] Fehler beim Speichern: \(error)")
        }
    }

    private func trimToLimit() {
        let trimmed = Self.trim(corrections: corrections, keyOrder: keyOrder)
        corrections = trimmed.corrections
        keyOrder = trimmed.keyOrder
    }

    private static func trim(
        corrections: [String: String],
        keyOrder: [String]
    ) -> (corrections: [String: String], keyOrder: [String]) {
        var corrections = corrections
        var keyOrder = keyOrder
        while keyOrder.count > maxEntries {
            let removed = keyOrder.removeFirst()
            corrections.removeValue(forKey: removed)
        }
        return (corrections, keyOrder)
    }

    private func tokenize(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init)
    }

    private func shouldLearn(target: String) -> Bool {
        if target.count < 2 { return false }
        if target.contains(where: { $0.isNumber }) { return true }
        if target.contains(where: { $0.isUppercase }) && target.contains(where: { $0.isLowercase }) { return true }
        if target.count <= 8 && target.allSatisfy({ $0.isUppercase || $0.isNumber }) { return true }
        return false
    }

    private func replaceWholeWord(_ source: String, with replacement: String, in text: String) -> String {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: source) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
