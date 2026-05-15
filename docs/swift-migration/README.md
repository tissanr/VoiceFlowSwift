# VoiceFlow — Swift-Migration

> **Branch:** `swift-migration` | **Worktree:** `~/dev/VoiceFlow-swift/`

Migration von Python/C-Launcher auf Swift + WhisperKit. Ziel ist eine echte native macOS-App
ohne C-Launcher-Hack, mit nativem Permission-Flow, ~20 MB Bundle (statt 1,1 GB venv) und
trivialem Homebrew-Cask.

---

## Warum migrieren?

| Problem (Python-Stack)              | Lösung (Swift-Stack)                         |
| ----------------------------------- | -------------------------------------------- |
| C-Launcher-Hack für Permissions     | Native `.app`, Permissions out-of-the-box    |
| 1,1 GB venv für Distribution        | ~20 MB Bundle, Modelle separat geladen       |
| Homebrew: pip install in postflight | Homebrew Cask: einfach die `.app` verpacken  |
| Startup-Zeit Python + Model-Load    | Schnellerer App-Start                        |
| sounddevice-Fallback für Mikrofon   | AVFoundation exklusiv, keine Doppelstrategie |

**Nicht migriert:** Die Kernlogik (Whisper → LLM → Text injection) bleibt gleich —
nur der Stack wechselt.

---

## Phasenübersicht

| Phase | Dokument                                             | Titel                          | Dauer  |
| ----- | ---------------------------------------------------- | ------------------------------ | ------ |
| 1     | [phase-1-foundation.md](phase-1-foundation.md)       | Xcode-Projekt & Foundation     | 1–2 Wo |
| 2     | [phase-2-audio-input.md](phase-2-audio-input.md)     | Audio & Hotkey                 | 2–3 Wo |
| 3     | [phase-3-whisper.md](phase-3-whisper.md)             | WhisperKit-Integration         | 3–4 Wo |
| 4     | [phase-4-llm.md](phase-4-llm.md)                     | LLM Enhancement                | 3–4 Wo |
| 5     | [phase-5-text-delivery.md](phase-5-text-delivery.md) | Text Delivery & AX API         | 3–4 Wo |
| 6     | [phase-6-ui.md](phase-6-ui.md)                       | UI (MenuBar, Overlay, History) | 3–4 Wo |
| 7     | [phase-7-distribution.md](phase-7-distribution.md)   | Distribution & Cleanup         | 1–2 Wo |

**Gesamtschätzung:** 16–23 Wochen als Einzelentwickler.

---

## Abhängigkeitsgraph

```
Phase 1 (Foundation)
    └── Phase 2 (Audio & Hotkey)
            └── Phase 3 (Whisper)
                    ├── Phase 4 (LLM)
                    └── Phase 5 (Text Delivery)
                            └── Phase 6 (UI)  ← braucht alle vorherigen
                                    └── Phase 7 (Distribution)
```

Phase 4 und Phase 5 können parallel laufen sobald Phase 3 abgeschlossen ist.

---

## Wichtigste externe Abhängigkeiten

| Library                                               | Quelle | Zweck                                   |
| ----------------------------------------------------- | ------ | --------------------------------------- |
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | SPM    | Whisper auf Apple Silicon (CoreML)      |
| [mlx-swift](https://github.com/ml-explore/mlx-swift)  | SPM    | LLM-Inferenz (Qwen, Phi)                |
| AppKit / SwiftUI                                      | Xcode  | Menubar, Overlay, Fenster               |
| AVFoundation                                          | Xcode  | Mikrofon-Aufnahme                       |
| ApplicationServices                                   | Xcode  | AX API (Cursor-Kontext, Text-Injektion) |
| Quartz                                                | Xcode  | CGEvent für Keyboard-Events und Hotkey  |

---

## Dateipfad-Mapping (Python → Swift)

| Python-Datei                 | Swift-Ziel                                           |
| ---------------------------- | ---------------------------------------------------- |
| `core/hotkey_manager.py`     | `Sources/VoiceFlow/Input/HotkeyManager.swift`        |
| `core/audio_recorder.py`     | `Sources/VoiceFlow/Audio/AudioRecorder.swift`        |
| `core/transcriber.py`        | `Sources/VoiceFlow/Transcription/Transcriber.swift`  |
| `core/llm_post_processor.py` | `Sources/VoiceFlow/LLM/LLMPostProcessor.swift`       |
| `core/ollama_processor.py`   | `Sources/VoiceFlow/LLM/OllamaProcessor.swift`        |
| `core/vocab_learner.py`      | `Sources/VoiceFlow/Transcription/VocabLearner.swift` |
| `core/text_normalizer.py`    | `Sources/VoiceFlow/Text/TextNormalizer.swift`        |
| `core/text_injector.py`      | `Sources/VoiceFlow/Text/TextInjector.swift`          |
| `core/cursor_context.py`     | `Sources/VoiceFlow/Text/CursorContext.swift`         |
| `core/text_delivery.py`      | `Sources/VoiceFlow/Text/TextDelivery.swift`          |
| `core/model_manager.py`      | `Sources/VoiceFlow/Model/ModelManager.swift`         |
| `core/model_downloader.py`   | `Sources/VoiceFlow/Model/ModelDownloader.swift`      |
| `core/word_logger.py`        | `Sources/VoiceFlow/Logging/WordLogger.swift`         |
| `core/post_processor.py`     | `Sources/VoiceFlow/Text/PostProcessor.swift`         |
| `settings/app_settings.py`   | `Sources/VoiceFlow/Settings/AppSettings.swift`       |
| `ui/menubar_app.py`          | `Sources/VoiceFlow/UI/MenuBarController.swift`       |
| `ui/overlay.py`              | `Sources/VoiceFlow/UI/OverlayWindow.swift`           |
| `ui/history_window.py`       | `Sources/VoiceFlow/UI/HistoryWindow.swift`           |
| `main.py`                    | `Sources/VoiceFlow/App.swift` (`@main`)              |
| `build_app.py`               | `Package.swift` + Xcode-Projekt                      |
