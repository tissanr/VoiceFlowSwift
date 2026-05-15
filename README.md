# VoiceFlow Swift

Native macOS Push-to-Talk Sprache-zu-Text App — Swift-Rewrite von [VoiceFlow](https://github.com/tissanr/VoiceFlow).

**Hotkey:** `Fn + Shift` halten → sprechen → loslassen → Text erscheint an der Cursor-Position.

Alles läuft **lokal** auf Apple Silicon — kein Cloud-Dienst, kein API-Key.

---

## Stack

| Komponente          | Technologie                                                                   |
| ------------------- | ----------------------------------------------------------------------------- |
| Spracherkennung     | [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML, Apple Silicon) |
| LLM Post-Processing | [mlx-swift](https://github.com/ml-explore/mlx-swift) (Qwen 2.5 / Phi-4-mini)  |
| UI                  | SwiftUI + AppKit (Menubar, Overlay, History)                                  |
| Text-Injektion      | CGEvent + Accessibility API                                                   |
| Hotkey              | CGEventTap (Quartz)                                                           |
| Audio               | AVFoundation                                                                  |

Kein C-Launcher. Kein Python. Kein 1 GB venv.

---

## Status

> **In Planung.** Der Implementierungsplan liegt als 7 Phasendokumente vor.

Ausgangspunkt ist der Python-Stack von [VoiceFlow](https://github.com/tissanr/VoiceFlow) —
alle Features werden 1:1 portiert, der Stack wird dabei vollständig ausgetauscht.

---

## Migrationsdoku

→ [`docs/swift-migration/`](docs/swift-migration/README.md)

| Phase                                              | Titel                          | Dauer  |
| -------------------------------------------------- | ------------------------------ | ------ |
| [1](docs/swift-migration/phase-1-foundation.md)    | Xcode-Projekt & Foundation     | 1–2 Wo |
| [2](docs/swift-migration/phase-2-audio-input.md)   | Audio & Hotkey                 | 2–3 Wo |
| [3](docs/swift-migration/phase-3-whisper.md)       | WhisperKit-Integration         | 3–4 Wo |
| [4](docs/swift-migration/phase-4-llm.md)           | LLM Enhancement                | 3–4 Wo |
| [5](docs/swift-migration/phase-5-text-delivery.md) | Text Delivery & AX API         | 3–4 Wo |
| [6](docs/swift-migration/phase-6-ui.md)            | UI (MenuBar, Overlay, History) | 3–4 Wo |
| [7](docs/swift-migration/phase-7-distribution.md)  | Distribution & Cleanup         | 1–2 Wo |

---

## Voraussetzungen

- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 13 Ventura oder neuer
- Xcode 15+
