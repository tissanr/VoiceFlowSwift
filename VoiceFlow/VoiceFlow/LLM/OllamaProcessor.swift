import Foundation

struct OllamaMessage: Codable {
    let role: String
    let content: String
}

struct OllamaOptions: Codable {
    let numCtx: Int
    let numPredict: Int
    let repeatPenalty: Double
    let repeatLastN: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case numCtx = "num_ctx"
        case numPredict = "num_predict"
        case repeatPenalty = "repeat_penalty"
        case repeatLastN = "repeat_last_n"
        case temperature
    }
}

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let options: OllamaOptions
    let keepAlive: String

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, options
        case keepAlive = "keep_alive"
    }
}

struct OllamaChatResponse: Codable {
    let message: OllamaMessage
    let done: Bool
}

actor OllamaProcessor {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    func warmup(model: String, baseURL: URL) async throws {
        _ = try await process(text: " ", model: model, level: .minimal, style: .concise,
                              capitalize: nil, vocabulary: [], baseURL: baseURL)
    }

    func process(
        text: String,
        model: String,
        level: LLMEnhancementLevel,
        style: LLMEnhancementStyle,
        capitalize: Bool?,
        vocabulary: [String],
        baseURL: URL
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }

        let systemPrompt = Prompts.systemPrompt(level: level, style: style, vocabulary: vocabulary)
        let userPrompt = Prompts.userPrompt(text: text, capitalize: capitalize)

        let wordCount = text.split(separator: " ").count
        let numPredict = calculateNumPredict(inputWords: wordCount, level: level)

        let options = OllamaOptions(
            numCtx: 768,
            numPredict: numPredict,
            repeatPenalty: 1.15,
            repeatLastN: 64,
            temperature: 0.0
        )

        let requestBody = OllamaChatRequest(
            model: model,
            messages: [
                OllamaMessage(role: "system", content: systemPrompt),
                OllamaMessage(role: "user", content: userPrompt)
            ],
            stream: false,
            options: options,
            keepAlive: "30m"
        )

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "OllamaProcessor", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
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
