import Foundation

// MARK: - LatencyTrace
// JSONL-Format: {"trace_id":"abc123","total_ms":1234.56,"events":[...]}
// Rückwärtskompatibel mit Python perf_trace.jsonl

struct LatencyTrace {
    let traceID: String
    private let start: ContinuousClock.Instant
    private(set) var events: [(name: String, ms: Double, data: [String: String])]

    static let traceURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voiceflow/perf_trace.jsonl")

    init() {
        traceID = String(UUID().uuidString.prefix(10).lowercased())
        start = ContinuousClock.now
        events = []
    }

    mutating func mark(_ name: String, _ data: [String: String] = [:]) {
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000
                 + Double(elapsed.components.attoseconds) / 1e15
        events.append((name: name, ms: round(ms * 100) / 100, data: data))
    }

    mutating func finish(_ data: [String: String] = [:]) {
        mark("trace_finished", data)
        writeJSONL()
    }

    func compactLine() -> String {
        var parts = ["id=\(traceID)"]
        var previous = 0.0
        for e in events {
            let delta = e.ms - previous
            previous = e.ms
            let fields = e.data.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            let suffix = fields.isEmpty ? "" : " \(fields)"
            parts.append("\(e.name)=+\(Int(delta))ms@\(Int(e.ms))ms\(suffix)")
        }
        return "[PerfTrace] " + parts.joined(separator: " | ")
    }

    private func writeJSONL() {
        let elapsed = ContinuousClock.now - start
        let totalMs = Double(elapsed.components.seconds) * 1000
                      + Double(elapsed.components.attoseconds) / 1e15

        guard let data = try? JSONSerialization.data(withJSONObject: [
            "trace_id": traceID,
            "total_ms": round(totalMs * 100) / 100,
            "events": events.map { e -> [String: Any] in
                var entry: [String: Any] = ["name": e.name, "t_ms": e.ms]
                if !e.data.isEmpty { entry["data"] = e.data }
                return entry
            }
        ]),
        let line = String(data: data, encoding: .utf8) else { return }

        let url = Self.traceURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let lineWithNewline = line + "\n"
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            handle.seekToEndOfFile()
            handle.write(Data(lineWithNewline.utf8))
            try? handle.close()
        } else {
            try? lineWithNewline.write(to: url, atomically: false, encoding: .utf8)
        }
    }
}
