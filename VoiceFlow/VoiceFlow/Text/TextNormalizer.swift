import Foundation

struct TextNormalizer {
    /// Normalizes text: spoken punctuation → symbols, multiple spaces, etc.
    static func normalize(_ text: String) -> String {
        var normalized = text

        // 1. Spoken punctuation (German)
        // Heuristic: replace keyword only if NOT followed by a lowercase letter
        // (= normal noun in sentence). "das Komma fehlt" stays unchanged,
        // "fertig Komma weiter" becomes "fertig, weiter".
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

        // 2. Dot spacing: sentence-ending dot before uppercase without space → insert space
        // Only before uppercase letters so decimal numbers (3.14) and URLs (foo.bar) are unaffected.
        do {
            let dotRegex = try Regex("(?<!\\.)\\.(?![. ])(?=[A-ZÄÖÜ])")
            normalized = normalized.replacing(dotRegex, with: ". ")
        } catch {
            print("[TextNormalizer] regex error: \(error)")
        }

        // 3. Multiple spaces
        normalized = normalized.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Collapses word repetition chains (≥3×) to a single occurrence.
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
            print("[TextNormalizer] repetition regex error: \(error)")
            return text
        }
    }
}
