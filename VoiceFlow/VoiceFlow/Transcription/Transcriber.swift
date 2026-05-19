import Accelerate
import Foundation
import WhisperKit

// Phase 3 — WhisperKit-Integration
actor Transcriber {
    private var whisperKit: WhisperKit?
    private let modelVariant: String

    init(modelName: String = ModelManager.defaultWhisperVariant) {
        self.modelVariant = ModelManager.whisperVariant(for: modelName)
    }

    @discardableResult
    func warmup() async throws -> Bool {
        let kit = try await loadWhisperKit()
        let silence = [Float](repeating: 0, count: WhisperKit.sampleRate)
        _ = try await kit.transcribe(
            audioArray: silence,
            decodeOptions: DecodingOptions(
                temperatureFallbackCount: 0,
                sampleLength: 1,
                usePrefillPrompt: false,
                skipSpecialTokens: true
            )
        )
        return true
    }

    func transcribe(
        audio: [Float],
        language: String? = nil,
        vocabulary: [String] = [],
        profile: TranscriptionProfile = .balanced
    ) async throws -> VoiceFlowTranscriptionResult {
        let inputRMS = Self.rms(audio)
        if inputRMS < Self.silenceThreshold {
            return VoiceFlowTranscriptionResult(
                text: "",
                language: normalizedLanguage(language) ?? "unknown",
                inputRMS: inputRMS,
                wasFiltered: true,
                avgLogprob: nil
            )
        }

        let kit = try await loadWhisperKit()
        let initialOptions = decodingOptions(
            for: profile,
            language: normalizedLanguage(language),
            vocabulary: vocabulary,
            whisperKit: kit,
            temperature: 0.0
        )
        let firstPass = try await runTranscription(audio: audio, options: initialOptions, inputRMS: inputRMS)

        guard !firstPass.wasFiltered,
              let avgLogprob = firstPass.avgLogprob,
              avgLogprob < -0.60 else {
            return firstPass
        }

        let retryOptions = decodingOptions(
            for: profile,
            language: normalizedLanguage(language),
            vocabulary: vocabulary,
            whisperKit: kit,
            temperature: 0.2
        )
        return try await runTranscription(audio: audio, options: retryOptions, inputRMS: inputRMS)
    }

    private func loadWhisperKit() async throws -> WhisperKit {
        if let whisperKit { return whisperKit }
        let config = WhisperKitConfig(
            model: modelVariant,
            downloadBase: ModelManager.huggingFaceCacheRoot,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )
        let loaded = try await WhisperKit(config)
        whisperKit = loaded
        return loaded
    }

    private func runTranscription(
        audio: [Float],
        options: DecodingOptions,
        inputRMS: Float
    ) async throws -> VoiceFlowTranscriptionResult {
        let kit = try await loadWhisperKit()
        let results = try await kit.transcribe(audioArray: audio, decodeOptions: options)
        let rawText = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Phase 4: Textnormalisierung & Repetitionsfilter
        let normalizedText = TextNormalizer.normalize(rawText)
        let text = TextNormalizer.filterRepetitions(normalizedText)
        
        let language = results.first?.language ?? options.language ?? "unknown"
        let avgLogprob = Self.averageLogprob(results)
        let wasFiltered = Self.shouldFilter(text: text, inputRMS: inputRMS, avgLogprob: avgLogprob)

        return VoiceFlowTranscriptionResult(
            text: wasFiltered ? "" : text,
            language: language,
            inputRMS: inputRMS,
            wasFiltered: wasFiltered,
            avgLogprob: avgLogprob
        )
    }

    private func decodingOptions(
        for profile: TranscriptionProfile,
        language: String?,
        vocabulary: [String],
        whisperKit: WhisperKit,
        temperature: Float
    ) -> DecodingOptions {
        var options = DecodingOptions(
            language: language,
            temperature: temperature,
            temperatureFallbackCount: 0,
            sampleLength: sampleLength(for: profile),
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            logProbThreshold: nil,
            noSpeechThreshold: nil
        )

        if let tokenizer = whisperKit.tokenizer {
            let prompt = vocabulary
                .prefix(100)
                .joined(separator: ", ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !prompt.isEmpty {
                options.promptTokens = tokenizer
                    .encode(text: " " + prompt)
                    .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            }
        }
        return options
    }

    private func sampleLength(for profile: TranscriptionProfile) -> Int {
        switch profile {
        case .fast:
            return 224
        case .balanced:
            return 448
        case .accurate:
            return 768
        }
    }

    private func normalizedLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        let value = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == "auto" ? nil : value
    }
}

struct VoiceFlowTranscriptionResult {
    let text: String
    let language: String
    let inputRMS: Float
    let wasFiltered: Bool
    let avgLogprob: Double?
}

private extension Transcriber {
    static let silenceThreshold: Float = 0.006

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var value: Float = 0
        vDSP_rmsqv(samples, 1, &value, vDSP_Length(samples.count))
        return value
    }

    static func averageLogprob(_ results: [TranscriptionResult]) -> Double? {
        let segments = results.flatMap(\.segments)
        guard !segments.isEmpty else { return nil }
        let total = segments.reduce(Float(0)) { $0 + $1.avgLogprob }
        return Double(total / Float(segments.count))
    }

    static func shouldFilter(text: String, inputRMS: Float, avgLogprob: Double?) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inputRMS < silenceThreshold { return true }
        if normalized.rangeOfCharacter(from: .alphanumerics) == nil { return true }
        if isBlacklisted(normalized) { return true }
        if hasTooManyNonLatinLetters(normalized) { return true }
        if hasWordRepetition(normalized) { return true }
        if let avgLogprob, avgLogprob < -1.1, normalized.split(whereSeparator: \.isWhitespace).count <= 3 {
            return true
        }
        return false
    }

    static func isBlacklisted(_ text: String) -> Bool {
        let lowered = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        let phrases: Set<String> = [
            // Englische Whisper-Halluzinationen
            "thank you",
            "thanks",
            "thanks for watching",
            "thank you for watching",
            "subscribe",
            "like and subscribe",
            // Deutsche Whisper-Halluzinationen
            "danke",
            "danke schon",
            "danke schön",
            "vielen dank",
            "vielen dank fur ihre aufmerksamkeit",
            "vielen dank für ihre aufmerksamkeit",
            "danke furs zuschauen",
            "danke fürs zuschauen",
            "untertitel von stephanie wolf",
            "untertitel von der deutschen hörfilm gmbh",
            "untertitelung im auftrag des zdf"
        ]
        return phrases.contains(lowered)
    }

    // Filtert Texte, bei denen mehr als 50 % der Buchstaben außerhalb des
    // Latin-Extended-Bereichs (U+0000–U+024F) liegen.  Das deckt alle
    // europäischen Diakritika (ä, ö, ü, ß …) ab und schließt trotzdem
    // CJK-, Arabisch- und andere Nicht-Latein-Schriften aus.
    static func hasTooManyNonLatinLetters(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let nonLatin = letters.filter { $0.value > 0x024F }
        return Double(nonLatin.count) / Double(letters.count) > 0.5
    }

    static func hasWordRepetition(_ text: String) -> Bool {
        let words = text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        guard words.count >= 3 else { return false }

        var repeatedWord: String?
        var runLength = 0
        for word in words where word.count >= 4 {
            if word == repeatedWord {
                runLength += 1
            } else {
                repeatedWord = word
                runLength = 1
            }
            if runLength >= 3 { return true }
        }
        return false
    }
}
