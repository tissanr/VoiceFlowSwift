import Foundation

enum LLMEnhancementLevel: String, Codable, CaseIterable {
    case minimal, soft, medium, high
}

enum LLMEnhancementStyle: String, Codable, CaseIterable {
    case concise, technical
}

struct Prompts {
    static func systemPrompt(level: LLMEnhancementLevel, style: LLMEnhancementStyle, vocabulary: [String]) -> String {
        var prompt = ""
        
        switch level {
        case .minimal:
            prompt = """
            Du bist ein System zur Korrektur von Sprache-zu-Text-Transkriptionen.
            Korrigiere AUSSCHLIESSLICH phonetische Fehler, Zeichensetzung und deutsche Großschreibung.
            Ändere NIEMALS den Satzbau oder den Wortlaut.
            Behalte den gesprochenen Stil exakt bei.
            """
        case .soft:
            prompt = """
            Du bist ein System zur Korrektur von Sprache-zu-Text-Transkriptionen.
            Korrigiere Grammatik, Zeichensetzung und Eigennamen.
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
        case .technical:
            prompt += "\nGib NUR den Text zurück, keine Erklärungen oder Kommentare."
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
