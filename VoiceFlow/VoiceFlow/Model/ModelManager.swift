import Foundation

// Phase 3 — Modell-Download und Cache-Verwaltung
enum ModelManager {
    static let defaultWhisperVariant = "large-v3-turbo"
    static let whisperRepoID = "argmaxinc/whisperkit-coreml"

    static var huggingFaceCacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    }

    static func whisperVariant(for modelName: String) -> String {
        switch modelName.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "", "large-turbo":
            return defaultWhisperVariant
        case "tiny", "base", "small", "medium", "large-v3", "large-v3-turbo":
            return modelName
        default:
            return modelName
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
