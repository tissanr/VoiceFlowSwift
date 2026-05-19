import Foundation

struct TextNormalizer {
    /// Normalisiert den Text: Gesprochene Satzzeichen -> Symbole, Mehrfach-Leerzeichen, etc.
    static func normalize(_ text: String) -> String {
        var normalized = text

        // 1. Gesprochene Satzzeichen (Deutsch)
        // Heuristik: Schlüsselwort nur ersetzen, wenn es NICHT vor einem Kleinbuchstaben steht
        // (= normales Substantiv im Satz). "das Komma fehlt" bleibt unverändert,
        // "fertig Komma weiter" wird zu "fertig, weiter".
        let punctuationPatterns: [(String, String)] = [
            (" Punkt(?! [a-zäöüß])", "."),
            (" Komma(?! [a-zäöüß])", ","),
            (" Ausrufezeichen", "!"),
            (" Fragezeichen", "?"),
            (" Doppelpunkt", ":"),
            (" Semikolon", ";"),
            (" Neue Zeile", "\n"),
            (" Neuer Absatz", "\n\n")
        ]
        for (pattern, symbol) in punctuationPatterns {
            normalized = normalized.replacingOccurrences(
                of: pattern, with: symbol, options: [.caseInsensitive, .regularExpression])
        }

        // 2. Punkt-Abstand: Satzendepunkt vor Großbuchstaben ohne Leerzeichen → Leerzeichen einfügen
        // Nur vor Großbuchstaben, damit Dezimalzahlen (3.14) und URLs (foo.bar) unberührt bleiben.
        do {
            let dotRegex = try Regex("(?<!\\.)\\.(?![. ])(?=[A-ZÄÖÜ])")
            normalized = normalized.replacing(dotRegex, with: ". ")
        } catch {
            print("[TextNormalizer] Regex-Fehler: \(error)")
        }

        // 3. Mehrfache Leerzeichen
        normalized = normalized.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Kürzt Wort-Wiederholungsketten (≥3×) auf ein einzelnes Vorkommen.
    static func filterRepetitions(_ text: String) -> String {
        do {
            let repetitionRegex = try Regex("\\b(\\w{4,})\\b(?:\\W+\\1\\b){2,}")
            var result = text
            let matches = text.ranges(of: repetitionRegex)
            for range in matches.reversed() {
                let match = text[range]
                if let firstWordMatch = try? Regex("\\w+").firstMatch(in: match) {
                    result.replaceSubrange(range, with: match[firstWordMatch.range])
                }
            }
            return result
        } catch {
            print("[TextNormalizer] Repetitions-Regex-Fehler: \(error)")
            return text
        }
    }
}
