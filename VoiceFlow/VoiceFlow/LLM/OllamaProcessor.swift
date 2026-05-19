import Foundation

struct OllamaMessage: Codable {
    let role: String
    let content: String
}

struct OllamaOptions: Codable {
    let num_ctx: Int
    let num_predict: Int
    let repeat_penalty: Double
    let repeat_last_n: Int
    let temperature: Double
}

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let options: OllamaOptions
    let keep_alive: String
}

struct OllamaChatResponse: Codable {
    let message: OllamaMessage
    let done: Bool
}

actor OllamaProcessor {
    private let baseURL = URL(string: "http://localhost:11434/api/chat")!
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    func warmup(model: String) async throws {
        // Ein leerer Prompt zum Warmup
        let _ = try await process(text: "", model: model, level: .minimal, style: .concise, capitalize: nil, vocabulary: [])
    }
    
    func process(
        text: String,
        model: String,
        level: LLMEnhancementLevel,
        style: LLMEnhancementStyle,
        capitalize: Bool?,
        vocabulary: [String]
    ) async throws -> String {
        guard !text.isEmpty else { return "" }
        
        let systemPrompt = Prompts.systemPrompt(level: level, style: style, vocabulary: vocabulary)
        let userPrompt = Prompts.userPrompt(text: text, capitalize: capitalize)
        
        let wordCount = text.split(separator: " ").count
        let numPredict = calculateNumPredict(inputWords: wordCount, level: level)
        
        let options = OllamaOptions(
            num_ctx: 768,
            num_predict: numPredict,
            repeat_penalty: 1.15,
            repeat_last_n: 64,
            temperature: 0.0 // Greedy decoding for consistency
        )
        
        let requestBody = OllamaChatRequest(
            model: model,
            messages: [
                OllamaMessage(role: "system", content: systemPrompt),
                OllamaMessage(role: "user", content: userPrompt)
            ],
            stream: false,
            options: options,
            keep_alive: "30m"
        )
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "OllamaProcessor", code: 0, userInfo: [NSLocalizedDescriptionKey: "HTTP Error"])
        }
        
        let ollamaResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return ollamaResponse.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func calculateNumPredict(inputWords: Int, level: LLMEnhancementLevel) -> Int {
        switch level {
        case .minimal:
            return max(40, inputWords + 12)
        case .soft:
            return max(50, Int(Double(inputWords) * 1.3))
        case .medium:
            return max(60, Int(Double(inputWords) * 1.8))
        case .high:
            return max(80, Int(Double(inputWords) * 2.0))
        }
    }
}
