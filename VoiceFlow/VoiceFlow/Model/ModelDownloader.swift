import Foundation
import WhisperKit

actor ModelDownloader {
    typealias ProgressHandler = @Sendable (Double) -> Void

    func downloadWhisperModel(
        variant: String,
        progress: ProgressHandler? = nil
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: ModelManager.whisperVariant(for: variant),
            downloadBase: ModelManager.huggingFaceCacheRoot,
            from: ModelManager.whisperRepoID
        ) { downloadProgress in
            progress?(downloadProgress.fractionCompleted)
        }
    }

    func downloadMLXModel(
        repoID: String,
        progress: ProgressHandler? = nil
    ) async throws {
        let files = try await modelFiles(repoID: repoID)
        let downloadable = files.filter { !$0.rfilename.hasSuffix("/") }
        guard !downloadable.isEmpty else { return }

        let destinationRoot = mlxCachePath(for: repoID)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let totalBytes = downloadable.reduce(Int64(0)) { $0 + max($1.size ?? 0, 0) }
        let counter = DownloadCounter(totalBytes: max(totalBytes, 1), progress: progress)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for file in downloadable {
                group.addTask {
                    try await self.downloadFile(
                        repoID: repoID,
                        filename: file.rfilename,
                        destinationRoot: destinationRoot,
                        counter: counter
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    private func modelFiles(repoID: String) async throws -> [HuggingFaceFile] {
        let url = URL(string: "https://huggingface.co/api/models/\(repoID)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response)
        return try JSONDecoder().decode(HuggingFaceModel.self, from: data).siblings
    }

    private func downloadFile(
        repoID: String,
        filename: String,
        destinationRoot: URL,
        counter: DownloadCounter
    ) async throws {
        let encodedFilename = filename
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(encodedFilename)")!
        let destination = destinationRoot.appendingPathComponent(filename)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        try validate(response: response)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        if let fileSize = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            await counter.add(Int64(fileSize))
        }
    }

    private func mlxCachePath(for repoID: String) -> URL {
        let repoFolder = "models--" + repoID.replacingOccurrences(of: "/", with: "--")
        return ModelManager.huggingFaceCacheRoot.appendingPathComponent(repoFolder)
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModelDownloaderError.badResponse
        }
    }
}

private actor DownloadCounter {
    private let totalBytes: Int64
    private let progress: ModelDownloader.ProgressHandler?
    private var downloadedBytes: Int64 = 0

    init(totalBytes: Int64, progress: ModelDownloader.ProgressHandler?) {
        self.totalBytes = totalBytes
        self.progress = progress
    }

    func add(_ byteCount: Int64) {
        downloadedBytes += byteCount
        progress?(min(1.0, Double(downloadedBytes) / Double(totalBytes)))
    }
}

private struct HuggingFaceModel: Decodable {
    let siblings: [HuggingFaceFile]
}

private struct HuggingFaceFile: Decodable {
    let rfilename: String
    let size: Int64?
}

enum ModelDownloaderError: Error {
    case badResponse
}
