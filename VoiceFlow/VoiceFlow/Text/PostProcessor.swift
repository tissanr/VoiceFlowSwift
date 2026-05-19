import Foundation

struct PostProcessor {
    /// Erkennt Aufzählungen und formatiert sie als Liste
    static func process(_ text: String) -> String {
        var processed = text
        
        // Liste von Triggern für Aufzählungen
        let listTriggers: [(String, String)] = [
            ("erstens", "1."),
            ("zweitens", "2."),
            ("drittens", "3."),
            ("viertens", "4."),
            ("fünftens", "5."),
            ("punkt eins", "1."),
            ("punkt zwei", "2."),
            ("punkt drei", "3."),
            ("firstly", "1."),
            ("secondly", "2."),
            ("thirdly", "3.")
        ]
        
        for (trigger, replacement) in listTriggers {
            // Wir suchen nach dem Trigger am Satzanfang oder nach einem Punkt/Zeilenumbruch
            let pattern = "(?i)(^|[.\\n])\\s*\(trigger)\\s+"
            processed = processed.replacingOccurrences(of: pattern, with: "$1\n\(replacement) ", options: .regularExpression)
        }
        
        return processed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
