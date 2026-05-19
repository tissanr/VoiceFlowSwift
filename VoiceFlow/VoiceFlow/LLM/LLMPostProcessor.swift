import Foundation

/// Phase 4 — LLM Post-Processing (Ollama / mlx-swift)
actor LLMPostProcessor {
    private let ollamaProcessor = OllamaProcessor()
    // TODO: mlxProcessor (Phase 4.4)
    
    func process(
        text: String,
        settings: AppSettings,
        capitalize: Bool?,
        vocabulary: [String]
    ) async -> String {
        guard settings.enhancementLevel != .none else { return text }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        var result = text
        
        do {
            switch settings.llmRuntime {
            case .ollama:
                let model = settings.ollamaModel.isEmpty ? "phi4-mini" : settings.ollamaModel
                let chatURL = URL(string: settings.ollamaBaseURL + "/api/chat")
                    ?? URL(string: "http://localhost:11434/api/chat")!
                result = try await ollamaProcessor.process(
                    text: text,
                    model: model,
                    level: mapLevel(settings.enhancementLevel),
                    style: mapStyle(settings.enhancementStyle),
                    capitalize: capitalize,
                    vocabulary: vocabulary,
                    baseURL: chatURL
                )
            case .mlx:
                // TODO: mlx implementation
                print("[LLMPostProcessor] MLX not yet implemented, using original")
                return text
            }
            
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            print("[LLMPostProcessor] done in \(String(format: "%.2f", duration))s")

            if validateOutput(result, input: text) {
                return result
            } else {
                print("[LLMPostProcessor] validation failed, using original")
                return text
            }
            
        } catch {
            print("[LLMPostProcessor] error: \(error)")
            return text
        }
    }
    
    private func mapLevel(_ level: EnhancementLevel) -> LLMEnhancementLevel {
        switch level {
        case .none, .minimal: return .minimal
        case .soft: return .soft
        case .medium: return .medium
        case .high: return .high
        }
    }

    private func mapStyle(_ style: EnhancementStyle) -> LLMEnhancementStyle {
        switch style {
        case .standard: return .concise
        case .developer: return .technical
        }
    }
    
    private func validateOutput(_ output: String, input: String) -> Bool {
        guard !output.isEmpty else { return false }
        
        // 1. Word count: max ±2 words deviation or 20%
        let inputWords = input.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        let outputWords = output.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        let diff = abs(inputWords - outputWords)
        let allowedDiff = max(2, Int(Double(inputWords) * 0.2))
        
        if diff > allowedDiff {
            print("[LLMPostProcessor] validation: word count deviation too large (\(inputWords) -> \(outputWords))")
            return false
        }
        
        // 2. Character length (ratio)
        let inputLen = input.count
        let outputLen = output.count
        if inputLen > 0 {
            let ratio = Double(outputLen) / Double(inputLen)
            if ratio < 0.6 || ratio > 2.0 {
                print("[LLMPostProcessor] validation: ratio deviation too large (\(ratio))")
                return false
            }
        }
        
        // 3. Check for meta-commentary
        let lowercased = output.lowercased()
        let forbiddenStarts = ["hier ist", "sure,", "as an ai", "der korrigierte text", "bitteschön"]
        for start in forbiddenStarts {
            if lowercased.hasPrefix(start) {
                print("[LLMPostProcessor] validation: meta-commentary detected")
                return false
            }
        }
        
        return true
    }
}
