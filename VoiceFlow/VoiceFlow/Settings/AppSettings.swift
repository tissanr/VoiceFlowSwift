import Foundation

// MARK: - Enums (Rückwärtskompatibel mit Python-settings.json — snake_case)

enum EnhancementLevel: String, Codable {
    case none, minimal, soft, medium, high
}

enum EnhancementStyle: String, Codable {
    case standard, developer
}

enum LLMRuntime: String, Codable {
    case ollama, mlx
}

enum TranscriptionProfile: String, Codable {
    case fast, balanced, accurate
}

enum TextOutputMode: String, Codable {
    case automatic
    case typing
    case paste
    case clipboardOnly
}

// MARK: - AppSettings

struct AppSettings: Codable {
    var modelSize: String = "large-turbo"
    var language: String = "auto"
    var hotkey: String = "<ctrl>+<shift>+<space>"
    var soundEnabled: Bool = true
    var autoCapitalize: Bool = true
    var microphone: String = ""
    var transcriptionProfile: TranscriptionProfile = .balanced
    var spokenPunctuationEnabled: Bool = true
    var debugTraceEnabled: Bool = false
    var enhancementLevel: EnhancementLevel = .minimal
    var enhancementStyle: EnhancementStyle = .standard
    var textOutputMode: TextOutputMode = .typing
    var llmRuntime: LLMRuntime = .ollama
    var mlxModelSize: String = "1.5b"
    var ollamaBaseURL: String = "http://localhost:11434"
    var ollamaModel: String = ""

    // Explizite CodingKeys für Python snake_case Kompatibilität
    enum CodingKeys: String, CodingKey {
        case modelSize = "model_size"
        case language, hotkey, microphone
        case soundEnabled = "sound_enabled"
        case autoCapitalize = "auto_capitalize"
        case transcriptionProfile = "transcription_profile"
        case spokenPunctuationEnabled = "spoken_punctuation_enabled"
        case debugTraceEnabled = "debug_trace_enabled"
        case enhancementLevel = "enhancement_level"
        case enhancementStyle = "enhancement_style"
        case textOutputMode = "text_output_mode"
        case llmRuntime = "llm_runtime"
        case mlxModelSize = "mlx_model_size"
        case ollamaBaseURL = "ollama_base_url"
        case ollamaModel = "ollama_model"
    }

    // MARK: - Persistence

    static let settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voiceflow/settings.json")

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else { return AppSettings() }
        let decoder = JSONDecoder()
        return (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func save() {
        let url = Self.settingsURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            print("[AppSettings] Fehler beim Speichern: \(error)")
        }
    }
}
