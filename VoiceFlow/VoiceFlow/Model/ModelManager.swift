import Foundation

// Phase 3 — Modell-Download und Cache-Verwaltung
enum ModelManager {
    static let defaultWhisperVariant = "large-v3-turbo"
    static let whisperRepoID = "argmaxinc/whisperkit-coreml"

    static var huggingFaceCacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    }

    /// Gibt den kurzen Modellnamen zurück, den WhisperKit erwartet.
    /// WhisperKit ergänzt den `openai_whisper-` Prefix bei der Repo-Suche selbst.
    static func whisperVariant(for modelName: String) -> String {
        let normalized = modelName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "openai_whisper-", with: "")

        switch normalized {
        case "", "large-turbo", "large-v3-turbo":
            return "large-v3-v20240930_turbo_632MB"
        case "large-v3":
            return "large-v3-v20240930_626MB"
        case "medium", "small", "base", "tiny":
            return normalized
        default:
            return normalized
        }
    }

    /// Prüft ob das Modell lokal gecacht ist.
    /// WhisperKit legt Modelle unter {downloadBase}/models/{org}/{repo}/openai_whisper-{variant}/ ab.
    static func isCached(modelName: String) -> Bool {
        let variant = whisperVariant(for: modelName)
        let modelDir = whisperModelDir(variant: variant)
        guard let enumerator = FileManager.default.enumerator(
            at: modelDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               url.pathExtension == "mlmodelc" {
                return true
            }
        }
        return false
    }

    /// Pfad zum Modell-Verzeichnis, so wie WhisperKit es anlegt.
    /// Struktur: {downloadBase}/models/{org}/{repo}/openai_whisper-{variant}/
    static func whisperModelDir(variant: String) -> URL {
        var url = huggingFaceCacheRoot.appendingPathComponent("models")
        for component in whisperRepoID.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        return url.appendingPathComponent("openai_whisper-" + variant)
    }
}
