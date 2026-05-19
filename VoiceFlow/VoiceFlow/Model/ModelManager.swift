import Foundation

// Phase 3 — Modell-Download und Cache-Verwaltung
enum ModelManager {
    static let defaultWhisperVariant = "large-v3-turbo"
    static let whisperRepoID = "argmaxinc/whisperkit-coreml"

    static var huggingFaceCacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    }

    /// Gibt den vollständigen HuggingFace-Modellnamen zurück, den WhisperKit erwartet.
    /// Kurz-Aliase (z. B. "large-v3-turbo") werden auf den kanonischen Ordnernamen
    /// im argmaxinc/whisperkit-coreml-Repo abgebildet.
    static func whisperVariant(for modelName: String) -> String {
        switch modelName.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "", "large-turbo", "large-v3-turbo":
            return "openai_whisper-large-v3-turbo"
        case "large-v3":
            return "openai_whisper-large-v3"
        case "medium":
            return "openai_whisper-medium"
        case "small":
            return "openai_whisper-small"
        case "base":
            return "openai_whisper-base"
        case "tiny":
            return "openai_whisper-tiny"
        default:
            // Bereits vollständiger Name oder unbekannter Alias — best-effort Passthrough
            if modelName.hasPrefix("openai_whisper-") { return modelName }
            return "openai_whisper-\(modelName)"
        }
    }

    /// Prüft ob das Modell lokal gecacht ist.
    /// Als Nachweis genügt ein *.mlmodelc-Verzeichnis oder eine *.bin-Datei > 1 MB
    /// im Repo-Cache-Ordner des Whisper-Repos.
    static func isCached(modelName: String) -> Bool {
        let root = whisperRepoCacheRoot
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true, url.pathExtension == "mlmodelc" {
                return true
            }
            if url.pathExtension == "bin", (values?.fileSize ?? 0) > 1_000_000 {
                return true
            }
        }
        return false
    }

    /// Wurzel des lokalen HuggingFace-Cache-Ordners für das Whisper-Repo.
    static var whisperRepoCacheRoot: URL {
        let repoFolder = "models--" + whisperRepoID.replacingOccurrences(of: "/", with: "--")
        return huggingFaceCacheRoot.appendingPathComponent(repoFolder)
    }
}
