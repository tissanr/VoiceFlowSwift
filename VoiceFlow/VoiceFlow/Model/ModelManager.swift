import Foundation

// Phase 3 — Model download and cache management
enum ModelManager {
    static let defaultWhisperVariant = "large-v3-turbo"
    static let whisperRepoID = "argmaxinc/whisperkit-coreml"

    static var huggingFaceCacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    }

    /// Returns the short model name expected by WhisperKit.
    /// WhisperKit adds the `openai_whisper-` prefix itself during repo lookup.
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

    /// Returns true if the model is cached locally.
    /// WhisperKit stores models at {downloadBase}/models/{org}/{repo}/openai_whisper-{variant}/.
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

    /// Path to the model directory as laid out by WhisperKit.
    /// Structure: {downloadBase}/models/{org}/{repo}/openai_whisper-{variant}/
    static func whisperModelDir(variant: String) -> URL {
        var url = huggingFaceCacheRoot.appendingPathComponent("models")
        for component in whisperRepoID.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        return url.appendingPathComponent("openai_whisper-" + variant)
    }
}
