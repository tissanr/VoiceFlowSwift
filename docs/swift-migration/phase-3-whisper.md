# Phase 3 — WhisperKit-Integration

> **Dauer:** 3–4 Wochen | **Vorgänger:** Phase 2 | **Nachfolger:** Phase 4 + 5 (parallel)

## Ziel

Sprache zu Text transkribieren mit WhisperKit — gleiche Modelle, gleiche Qualität, kein Python.

## Warum jetzt

WhisperKit ist der einzige vollwertige Ersatz für mlx-whisper in Swift. Alle Downstream-Phasen
(LLM, Text Delivery, UI) brauchen fertige Transkriptions-Ergebnisse. Diese Phase ist der
kritische Pfad der gesamten Migration.

---

## Komponenten

### 3.1 ModelManager

**Python-Quelle:** `core/model_manager.py` (~60 Zeilen)

```swift
// Sources/VoiceFlow/Model/ModelManager.swift
struct ModelManager {
    /// Prüft ob das Modell lokal gecacht ist (mind. eine *.mlmodelc oder *.bin-Datei > 1 MB)
    static func isCached(modelName: String) -> Bool

    /// Gibt den lokalen Cache-Pfad zurück
    static func cachePath(for modelName: String) -> URL
}
```

- Cache-Verzeichnis: `~/.cache/huggingface/hub/models--argmaxinc--whisperkit-coreml-*/`
  (WhisperKit nutzt denselben HF-Hub-Cache wie mlx-whisper)
- Prüfung: `FileManager` Directory-Traversal, mind. eine Datei > 1 MB

---

### 3.2 ModelDownloader

**Python-Quelle:** `core/model_downloader.py` (~100 Zeilen)

WhisperKit hat einen eingebauten Download-Mechanismus via `WhisperKit.download(variant:)`.
Eigener Downloader nur für Fortschritts-Callbacks nötig.

```swift
// Sources/VoiceFlow/Model/ModelDownloader.swift
actor ModelDownloader {
    typealias ProgressHandler = (Double) -> Void

    func downloadWhisperModel(
        variant: String,
        progress: @escaping ProgressHandler
    ) async throws

    func downloadMLXModel(
        repoID: String,
        progress: @escaping ProgressHandler
    ) async throws
}
```

- WhisperKit-Modelle: `WhisperKit.download(variant: "large-v3-turbo", downloadBase: cacheURL)`
- MLX-Modelle (für Phase 4): HuggingFace REST API direkt via `URLSession`
  - `GET https://huggingface.co/api/models/{repo_id}` → Dateiliste
  - Parallele Downloads mit `withThrowingTaskGroup`
  - `URLSession.bytes(for:)` für Fortschritt pro Datei

---

### 3.3 Transcriber

**Python-Quelle:** `core/transcriber.py` (~300 Zeilen)

```swift
// Sources/VoiceFlow/Transcription/Transcriber.swift
import WhisperKit

actor Transcriber {
    func warmup() async throws -> Bool
    func transcribe(
        audio: [Float],
        language: String?,          // nil = auto-detect
        vocabulary: [String],       // initial_prompt Begriffe
        profile: TranscriptionProfile
    ) async throws -> TranscriptionResult
}

struct TranscriptionResult {
    let text: String
    let language: String
    let inputRMS: Float
    let wasFiltered: Bool
    let avgLogprob: Double?
}
```

**WhisperKit API-Mapping:**

```swift
// Python:                              // Swift (WhisperKit):
mlx_whisper.transcribe(audio, ...)  →  whisperKit.transcribe(audioArray: audio, decodeOptions: opts)
result["text"]                      →  result.text
result["language"]                  →  result.language
result["segments"][n]["avg_logprob"]→  result.segments[n].avgLogprob
```

**Halluzinations-Filter** (direkt portiert):

```swift
private func filterResult(_ result: inout TranscriptionResult, inputRMS: Float) -> Bool {
    // 1. Stille: inputRMS < 0.006 → verwerfen
    // 2. Blacklist: "thank you", "thanks for watching", etc.
    // 3. Non-Latin: >50% der Buchstaben sind non-ASCII → verwerfen
    // 4. Wort-Repetition: \b(\w{4,})\b(?:\W+\1\b){2,} → verwerfen
    // 5. Nur-Satzzeichen: kein Buchstabe/Ziffer nach Bereinigung → verwerfen
    // 6. Niedrige Konfidenz: avgLogprob < -1.1 bei ≤3 Wörtern → verwerfen
}
```

**Retry-Logik:**

```swift
// Bei avgLogprob < -0.60: zweiter Versuch mit temperature=0.2
// Bei wasFiltered=true: kein Retry (verhindert doppelten Whisper-Call bei Stille)
```

**Modell-Laden:**

```swift
// WhisperKit initialisieren (einmalig beim Start):
let config = WhisperKitConfig(model: "large-v3-turbo", verbose: false)
whisperKit = try await WhisperKit(config)

// Warmup (kurze Stille transkribieren um Modell in RAM zu laden):
let silence = [Float](repeating: 0, count: 16000)
_ = try await whisperKit.transcribe(audioArray: silence, decodeOptions: .init())
```

**Risiken:**

- WhisperKit-Segment-Struktur weicht von mlx-whisper ab — API-Diff vor Implementierung prüfen
- `avgLogprob` ist in WhisperKit als `Float` nicht `Double` — Thresholds ggf. anpassen
- WhisperKit 0.9+ erfordert macOS 14 für volle CoreML-Beschleunigung; auf macOS 13 Fallback?
- Modell-Varianten-Namen unterscheiden sich: `large-turbo` (mlx) vs `large-v3-turbo` (WhisperKit)
  → Mapping-Tabelle in `ModelManager` anlegen

---

### 3.4 VocabLearner

**Python-Quelle:** `core/vocab_learner.py` (~200 Zeilen)

```swift
// Sources/VoiceFlow/Transcription/VocabLearner.swift
actor VocabLearner {
    /// Vergleicht Whisper-Output mit LLM-Korrektur, lernt neue Begriffe
    func learn(original: String, corrected: String) async

    /// Wendet gecachte Korrekturen auf Text an (LLM deaktiviert)
    func applyCorrections(to text: String) -> String

    /// Gibt gelernte Begriffe als initial_prompt-Array zurück
    var vocabulary: [String] { get }
}
```

- Persistenz: `~/.voiceflow/vocab_cache.json` (gleicher Pfad wie Python)
- LRU-Cache: max 100 Einträge, `[String: String]` Dictionary + `[String]` Schlüssel-Order-Array
- String-Diff: `CollectionDifference` (stdlib) als Ersatz für `difflib.SequenceMatcher`
- Schutzregel beibehalten: nur CamelCase/Abkürzungen/alphanumerische Begriffe lernen

---

## Swift-Frameworks & Bibliotheken

| Framework               | Zweck                            |
| ----------------------- | -------------------------------- |
| WhisperKit (SPM)        | Whisper-Transkription via CoreML |
| Foundation              | URLSession, FileManager, Codable |
| Swift Concurrency       | actor, async/await, TaskGroup    |
| Swift Regex (macOS 13+) | Halluzinations-Filter            |

---

## Done-Kriterium

- [ ] `Transcriber.transcribe()` gibt für 5-Sekunden-Sprachaufnahme korrekten deutschen Text zurück
- [ ] Stille (< 0.006 RMS) gibt leeren String zurück, kein Retry
- [ ] Modell-Download zeigt Fortschritt in Prozent (testbar via Log-Output)
- [ ] `VocabLearner` schreibt/liest `vocab_cache.json` kompatibel mit Python-Version
- [ ] Tests: `TranscriberTests` (Filter-Logik mit Mock-Results), `VocabLearnerTests`

## Offene Fragen

- Welche WhisperKit-Version ist stabil genug? (0.9.x oder `main`-Branch?)
- Soll `large-v3-turbo` der Default bleiben oder wechseln wir auf ein CoreML-optimiertes Modell?
- WhisperKit lädt Modelle standardmäßig nach `~/Library/Caches/` — auf `~/.cache/huggingface/hub/` umlenken für Kompatibilität mit bestehendem Cache?
