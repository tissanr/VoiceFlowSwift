import Foundation

// MARK: - LogEntry
// JSONL-Format: {"ts":"2026-05-15T10:30:00","words":5,"text":"...","duration_s":2.5,"accuracy":0.95}
// Rückwärtskompatibel mit Python word_log.jsonl

struct LogEntry: Codable {
    let ts: String          // ISO8601: "2026-05-15T10:30:00"
    let words: Int
    let text: String
    let durationS: Double?
    let accuracy: Double?

    enum CodingKeys: String, CodingKey {
        case ts, words, text
        case durationS = "duration_s"
        case accuracy
    }

    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                                   .withColonSeparatorInTime, .withColonSeparatorInTimeZone]
        if let d = formatter.date(from: ts) { return d }
        // Python schreibt ohne Zeitzone: "2026-05-15T10:30:00"
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return fallback.date(from: ts)
    }
}

// MARK: - WordLogger

actor WordLogger {
    static let shared = WordLogger()

    private let logURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voiceflow/word_log.jsonl")

    private var statsCache = WordStats(today: 0, week: 0, total: 0)

    private init() {
        Task { await self.hydrateStats() }
    }

    // MARK: - Public

    func log(text: String, durationS: Double? = nil, correctionRatio: Double? = nil) {
        let words = text.split(separator: " ").count
        guard words > 0 else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let entry = LogEntry(
            ts: formatter.string(from: Date()),
            words: words,
            text: text,
            durationS: durationS.map { round($0 * 100) / 100 },
            accuracy: correctionRatio.map { round($0 * 10000) / 10000 }
        )
        updateStatsCache(words: words, date: Date())
        append(entry)
    }

    func readEntries(limit: Int = 500) -> [LogEntry] {
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return content
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .suffix(limit)
            .compactMap { try? decoder.decode(LogEntry.self, from: Data($0.utf8)) }
    }

    func stats() -> WordStats { statsCache }

    // MARK: - Private

    private func append(_ entry: LogEntry) {
        guard let data = try? JSONEncoder().encode(entry),
              let line = String(data: data, encoding: .utf8) else { return }
        let logDir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let lineWithNewline = line + "\n"
        if FileManager.default.fileExists(atPath: logURL.path) {
            guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
            handle.seekToEndOfFile()
            handle.write(Data(lineWithNewline.utf8))
            try? handle.close()
        } else {
            try? lineWithNewline.write(to: logURL, atomically: false, encoding: .utf8)
        }
    }

    private func hydrateStats() {
        let entries = readEntries(limit: Int.max)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekAgo = cal.date(byAdding: .day, value: -6, to: today)!
        var result = WordStats(today: 0, week: 0, total: 0)
        for e in entries {
            guard let d = e.date else { continue }
            let day = cal.startOfDay(for: d)
            result.total += e.words
            if day >= weekAgo { result.week += e.words }
            if day == today   { result.today += e.words }
        }
        statsCache = result
    }

    private func updateStatsCache(words: Int, date: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekAgo = cal.date(byAdding: .day, value: -6, to: today)!
        let entryDay = cal.startOfDay(for: date)
        statsCache.total += words
        if entryDay >= weekAgo { statsCache.week += words }
        if entryDay == today   { statsCache.today += words }
    }
}

// MARK: - WordStats

struct WordStats {
    var today: Int
    var week: Int
    var total: Int
}
