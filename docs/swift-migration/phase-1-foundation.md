# Phase 1 — Xcode-Projekt & Foundation

> **Dauer:** 1–2 Wochen | **Vorgänger:** – | **Nachfolger:** Phase 2

## Ziel

Lauffähiges Xcode-Projekt mit App-Skeleton, Datenmodellen und Logging — ohne Whisper oder UI-Logik.

## Warum jetzt

Alle späteren Phasen bauen auf dem Build-System, den Settings-Typen und den Logger-Protokollen auf.
Diese Basis muss stabil sein bevor irgendein Feature integriert wird.

---

## Komponenten

### 1.1 Xcode-Projekt & Swift Package

**Python-Äquivalent:** `build_app.py`, `requirements.txt`

- Neues Xcode-Projekt: `VoiceFlow.xcodeproj`, Target `VoiceFlow` (macOS App)
- Deployment Target: macOS 13.0 (Ventura)
- Architecture: `arm64` only
- `Package.swift` für Abhängigkeiten (SPM):
  ```swift
  .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
  .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
  ```
- `Info.plist` Einträge:
  - `LSUIElement = true` (kein Dock-Icon)
  - `NSMicrophoneUsageDescription`
  - `NSAppleEventsUsageDescription`
- Entitlements: `com.apple.security.device.audio-input`

**Risiken:** SPM-Konflikt zwischen WhisperKit und mlx-swift (beide ziehen mlx-swift-core). Vor Beginn prüfen ob `Package.resolved` stabil ist.

---

### 1.2 AppSettings

**Python-Quelle:** `settings/app_settings.py` (51 Zeilen)

```swift
// Sources/VoiceFlow/Settings/AppSettings.swift
struct AppSettings: Codable {
    var modelSize: String = "large-turbo"
    var language: String = "auto"
    var microphoneDevice: String? = nil
    var enhancementLevel: EnhancementLevel = .minimal
    var enhancementStyle: EnhancementStyle = .concise
    var llmRuntime: LLMRuntime = .mlx
    var mlxModelSize: String = "qwen2.5-1.5b-4bit"
    var ollamaBaseURL: String = "http://localhost:11434"
    var ollamaModel: String = ""
    var transcriptionProfile: TranscriptionProfile = .balanced
    var soundEnabled: Bool = true
    var autoCapitalize: Bool = true
    var textOutputMode: TextOutputMode = .inject
    // ...
}
```

- Laden/Speichern: `~/.voiceflow/settings.json` via `JSONDecoder`/`JSONEncoder`
- Kein UserDefaults — Dateibasiert wie bisher (gleiche Pfade, Rückwärtskompatibilität)
- `@Observable` Macro (macOS 14+) oder manuelles `NotificationCenter` für Reaktivität

**Risiken:** `@Observable` erfordert macOS 14. Deployment Target prüfen.

---

### 1.3 WordLogger

**Python-Quelle:** `core/word_logger.py` (~150 Zeilen)

```swift
// Sources/VoiceFlow/Logging/WordLogger.swift
actor WordLogger {
    func log(text: String, wordCount: Int, duration: TimeInterval, correctionRatio: Double?)
    func readEntries(limit: Int) -> [LogEntry]
}
```

- JSONL-Format beibehalten (`~/.voiceflow/word_log.jsonl`) — Rückwärtskompatibilität mit History-Fenster
- `actor` statt `DispatchQueue` Background-Thread
- `FileHandle` für Append-only Writes

---

### 1.4 LatencyTrace

**Python-Quelle:** `core/latency_trace.py` (~60 Zeilen)

```swift
// Sources/VoiceFlow/Logging/LatencyTrace.swift
struct LatencyTrace {
    let traceID: UUID
    var steps: [(name: String, timestamp: ContinuousClock.Instant)]
    func finish() // schreibt nach ~/.voiceflow/perf_trace.jsonl
}
```

---

### 1.5 App-Skeleton (`@main`)

**Python-Quelle:** `main.py`

```swift
// Sources/VoiceFlow/App.swift
@main
struct VoiceFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // kein Dock-Icon
        // Phase 6: MenuBarController hier initialisieren
    }
}
```

---

### 1.6 XCTest-Infrastruktur

- Target `VoiceFlowTests` im Xcode-Projekt
- Test-Helfer: `MockFileManager`, `TempDirectory` (erstellt tmp-Verzeichnis, räumt nach Test auf)
- Erste Tests: `AppSettingsTests`, `WordLoggerTests`, `LatencyTraceTests`

---

## Swift-Frameworks & Bibliotheken

| Framework                                  | Zweck                        |
| ------------------------------------------ | ---------------------------- |
| Foundation                                 | JSON, FileManager, URL, Date |
| Swift Concurrency (`actor`, `async/await`) | Thread-safe Logging          |
| XCTest                                     | Unit Tests                   |

Keine externen Abhängigkeiten in dieser Phase (WhisperKit/mlx-swift nur deklariert, nicht genutzt).

---

## Done-Kriterium

- [ ] `xcodebuild -scheme VoiceFlow build` kompiliert ohne Warnings
- [ ] App startet, kein Dock-Icon, kein Fenster
- [ ] `AppSettings` schreibt/liest `~/.voiceflow/settings.json` korrekt
- [ ] `WordLogger` schreibt JSONL, bestehende Python-Logs werden korrekt gelesen
- [ ] Alle Tests grün: `xcodebuild test -scheme VoiceFlow`

## Offene Fragen

- Deployment Target: macOS 13 (kein `@Observable`) oder macOS 14?
- SPM vs. Xcode-integriertes Package-Management? (SPM empfohlen für CI)
- Soll `~/.voiceflow/` Verzeichnis beim ersten Start automatisch angelegt werden?
