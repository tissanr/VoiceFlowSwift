import Foundation

enum LLMEnhancementLevel: String, Codable, CaseIterable {
    case minimal, soft, medium, high
}

enum LLMEnhancementStyle: String, Codable, CaseIterable {
    case concise, explanatory, formal, casual
}

struct Prompts {
    static func systemPrompt(level: LLMEnhancementLevel, style: LLMEnhancementStyle, vocabulary: [String]) -> String {
        var prompt = ""
        
        switch level {
        case .minimal:
            prompt = """
            Du bist ein System zur Korrektur von Sprache-zu-Text-Transkriptionen.
            Korragiere AUSSCHLIESSLICH phonetische Fehler, Zeichensetzung und deutsche Großschreibung.
            Ändere NIEMALS den Satzbau oder den Wortlaut.
            Behalte den gesprochenen Stil exakt bei.
            """
        case .soft:
            prompt = """
            Du bist ein System zur Korrektur von Sprache-zu-Text-Transkriptionen.
            Korragiere Grammatik, Zeichensetzung und Eigennamen.
            Ändere den Satzbau nur, wenn er offensichtlich fehlerhaft ist.
            """
        case .medium:
            prompt = """
            Du bist ein Schreib-Assistent.
            Verbessere den Text moderat, mache ihn flüssiger, aber behalte die ursprüngliche Bedeutung und den Stil bei.
            """
        case .high:
            prompt = """
            Du bist ein Senior Editor.
            Überarbeite den Text für maximale Klarheit und Professionalität.
            Verwende einen gehobenen Stil, falls angemessen.
            """
        }
        
        if !vocabulary.isEmpty {
            prompt += "\n\nBeachte folgendes Fachvokabular/Eigennamen:\n"
            prompt += vocabulary.joined(separator: ", ")
        }
        
        switch style {
        case .concise:
            prompt += "\nAntworte so kurz wie möglich."
        case .explanatory:
            prompt += "\nErkläre deine Änderungen nicht, gib nur den Text zurück."
        case .formal:
            prompt += "\nVerwende eine formelle Ausdrucksweise."
        case .casual:
            prompt += "\nVerwende eine lockere, umgangssprachliche Ausdrucksweise."
        }
        
        prompt += "\n\nGib NUR den korrigierten Text zurück, ohne Kommentare oder Einleitungen."
        
        return prompt
    }
    
    static func userPrompt(text: String, capitalize: Bool?) -> String {
        var instructions = "Text: \"\(text)\""
        
        if let capitalize = capitalize {
            if capitalize {
                instructions += "\nErster Buchstabe MUSS großgeschrieben werden."
            } else {
                instructions += "\nErster Buchstabe MUSS kleingeschrieben werden (Satzfortführung)."
            }
        }
        
        return instructions
    }
}
