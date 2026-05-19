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
            You are a speech-to-text transcription correction system.
            Correct ONLY phonetic errors, punctuation, and capitalization.
            NEVER change sentence structure or wording.
            Preserve the spoken style exactly.
            """
        case .soft:
            prompt = """
            You are a speech-to-text transcription correction system.
            Correct grammar, punctuation, and proper nouns.
            Only change sentence structure when it is clearly broken.
            """
        case .medium:
            prompt = """
            You are a writing assistant.
            Improve the text moderately — make it flow better, but preserve the original meaning and style.
            """
        case .high:
            prompt = """
            You are a senior editor.
            Revise the text for maximum clarity and professionalism.
            Use a refined style where appropriate.
            """
        }
        
        if !vocabulary.isEmpty {
            prompt += "\n\nNote the following technical vocabulary/proper nouns:\n"
            prompt += vocabulary.joined(separator: ", ")
        }

        switch style {
        case .concise:
            prompt += "\nReply as briefly as possible."
        case .technical:
            prompt += "\nReturn ONLY the text, no explanations or comments."
        }

        prompt += "\n\nReturn ONLY the corrected text, without comments or preamble."
        
        return prompt
    }
    
    static func userPrompt(text: String, capitalize: Bool?) -> String {
        var instructions = "Text: \"\(text)\""
        
        if let capitalize = capitalize {
            if capitalize {
                instructions += "\nFirst letter MUST be capitalized."
            } else {
                instructions += "\nFirst letter MUST be lowercase (sentence continuation)."
            }
        }
        
        return instructions
    }
}
