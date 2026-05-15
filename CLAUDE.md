# VoiceFlow Swift — Claude Code Instruktionen

Diese Datei wird von Claude Code automatisch bei jedem Session-Start gelesen.

## Pflichtschritte zu Beginn jeder Session

1. **ROADMAP.md lesen** — enthält Entwicklungsstand, Architektur und offene Punkte
2. **Aktuelle Phase prüfen** — `docs/swift-migration/` enthält die Phasendokumente
3. **Kontext verstehen** bevor du Änderungen vorschlägst

## Pflichtschritte nach Änderungen

- Abgeschlossene Features in ROADMAP.md unter "Abgeschlossen" eintragen
- Neue offene Punkte unter "Geplant / Offen" ergänzen
- "Aktueller Stand" Abschnitt aktuell halten

## Projekt-Kontext

**Repo:** `~/dev/VoiceFlow-swift/` (Swift-Migration, aktive Arbeit auf `swift-migration-pr`)
**Python-Original:** `~/dev/VoiceFlow/` — Referenz für Logik und Verhalten, nicht für Code

VoiceFlow ist eine lokale macOS Menubar-App für Push-to-Talk Sprache-zu-Text.
Migration von Python/C-Launcher auf Swift + WhisperKit.

**Phasendokumente:** [`docs/swift-migration/`](docs/swift-migration/README.md)

## Build & Test

```bash
# Bauen
xcodebuild build -project VoiceFlow/VoiceFlow.xcodeproj -scheme VoiceFlow -configuration Debug

# Tests
xcodebuild test -project VoiceFlow/VoiceFlow.xcodeproj -scheme VoiceFlow -destination 'platform=macOS'
```

Xcode-Projekt liegt unter `VoiceFlow/VoiceFlow.xcodeproj`.
Aktuell existiert noch kein XCTest-Target.

## Projekt-Konventionen

- **Sprache:** Kommentare und Ausgaben auf Deutsch
- **Concurrency:** `actor` für thread-unsafe State, `async/await` durchgehend
- **Settings/Logs:** Dateipfade unter `~/.voiceflow/` — identisch zum Python-Original (Rückwärtskompatibilität)
- **Keine UserDefaults** — alles dateibasiert wie im Python-Original
- **Keine neuen Berechtigungen** ohne explizite Zustimmung des Users
- **Deployment Target:** macOS 13.0, `arm64` only

## Persistente Dateien (identisch zum Python-Original)

| Datei                           | Inhalt                                      |
| ------------------------------- | ------------------------------------------- |
| `~/.voiceflow/settings.json`    | App-Einstellungen                           |
| `~/.voiceflow/vocab_cache.json` | Gelernte Korrekturen                        |
| `~/.voiceflow/voiceflow.log`    | Laufzeit-Log                                |
| `~/.voiceflow/word_log.jsonl`   | Wort-Statistiken (JSONL, Append-only)       |
| `~/.voiceflow/perf_trace.jsonl` | Latenz-Traces                               |

## Wichtigste externe Abhängigkeiten (SPM)

| Library       | Zweck                              |
| ------------- | ---------------------------------- |
| WhisperKit    | Whisper auf Apple Silicon (CoreML) |
| mlx-swift     | LLM-Inferenz (Qwen, Phi)           |

## Aktueller Migrationsstand

**Phase 1 (Foundation):** Abgeschlossen
- ✅ Xcode-Projekt & Ordnerstruktur
- ✅ AppSettings (Settings/AppSettings.swift)
- ✅ WordLogger (Logging/WordLogger.swift)
- ✅ LatencyTrace (Logging/LatencyTrace.swift)
- ✅ AppDelegate minimal (kein Dock-Icon, kein Fenster)
- ✅ Phase 1 Done-Kriterium: `xcodebuild build` kompiliert
- 🔲 XCTest-Infrastruktur

**Phase 2 (Audio & Hotkey):** Implementiert, manuell zu verifizieren
- ✅ AudioRecorder mit AVAudioEngine, 16-kHz-Float-Ausgabe und RMS
- ✅ HotkeyManager mit CGEventTap und Polling-Fallback
- ✅ OverlayLevelMapper

**Phase 3 (WhisperKit):** Implementiert, Modell-/Audio-End-to-End-Test steht noch aus
- ✅ ModelManager mit Cache-Prüfung und Modellnamen-Mapping
- ✅ ModelDownloader für WhisperKit und HuggingFace-Downloads
- ✅ Transcriber mit WhisperKit, Warmup, Retry und Halluzinationsfilter
- ✅ VocabLearner mit `~/.voiceflow/vocab_cache.json`

**Phase 4–7:** Noch offen
