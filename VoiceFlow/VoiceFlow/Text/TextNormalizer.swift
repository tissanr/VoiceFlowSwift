import Foundation

struct TextNormalizer {
    /// Normalisiert den Text: Gesprochene Satzzeichen -> Symbole, Ellipsis-Fix, etc.
    static func normalize(_ text: String) -> String {
        var normalized = text
        
        // 1. Gesprochene Satzzeichen (Deutsch)
        let punctuationMap: [(String, String)] = [
            (" Punkt", "."),
            (" Komma", ","),
            (" Ausrufezeichen", "!"),
            (" Fragezeichen", "?"),
            (" Doppelpunkt", ":"),
            (" Semikolon", ";"),
            (" Neue Zeile", "\n"),
            (" Neuer Absatz", "\n\n")
        ]
        
        for (spoken, symbol) in punctuationMap {
            normalized = normalized.replacingOccurrences(of: spoken, with: symbol, options: .caseInsensitive)
        }
        
        // 2. Ellipsis-Fix: "(?<!\.)\.(?!\.)" -> ". "
        // In Swift verwenden wir Regex
        if #available(macOS 13.0, *) {
            do {
                // Punkt gefolgt von Leerzeichen, wenn es kein Teil einer Ellipsis ist
                let dotRegex = try Regex("(?<!\\.)\\.(?!\\.)")
                normalized = normalized.replacing(dotRegex, with: ". ")
            } catch {
                print("Regex error: \(error)")
            }
        }
        
        // 3. Mehrfache Leerzeichen korrigieren
        normalized = normalized.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Filtert Wort-Wiederholungen: \b(\w{4,})\b(?:\W+\1\b){2,}
    static func filterRepetitions(_ text: String) -> String {
        if #available(macOS 13.0, *) {
            do {
                let repetitionRegex = try Regex("\\b(\\w{4,})\\b(?:\\W+\\1\\b){2,}")
                var result = text
                // Da Regex.replacing alle Vorkommen ersetzt, aber wir vielleicht nur die Wiederholungen kürzen wollen:
                // Im Python-Original scheint es die Wiederholungen zu erkennen und zu warnen oder zu filtern.
                // Hier ersetzen wir die Kette durch ein einzelnes Wort.
                
                // Swift's Regex API für Ersetzungen mit Capture Groups ist etwas anders.
                // Wir nutzen einen einfacheren Weg für dieses Phase.
                let matches = text.ranges(of: repetitionRegex)
                for range in matches.reversed() {
                    let match = text[range]
                    // Extrahiere das erste Wort der Wiederholung
                    if let firstWordMatch = try? Regex("\\w+").firstMatch(in: match) {
                        let word = match[firstWordMatch.range]
                        result.replaceSubrange(range, with: word)
                    }
                }
                return result
            } catch {
                print("Repetition Regex error: \(error)")
            }
        }
        return text
    }
}
