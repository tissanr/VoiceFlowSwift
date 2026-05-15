# Phase 6 — UI (MenuBar, Overlay, History)

> **Dauer:** 3–4 Wochen | **Vorgänger:** Phase 4 + Phase 5 | **Nachfolger:** Phase 7

## Ziel

Vollständige native macOS-UI: Menubar-App mit State Machine, schwebendes Overlay, History-Fenster.

## Warum jetzt

UI kann erst sinnvoll gebaut werden wenn alle Backend-Phasen (Audio, Whisper, LLM, Delivery)
vorhanden sind. Diese Phase integriert alles zu einer nutzbaren App.

---

## Komponenten

### 6.1 AppDelegate & State Machine

**Python-Quelle:** `ui/menubar_app.py` (State Machine + Pipeline-Orchestrierung)

```swift
// Sources/VoiceFlow/UI/AppState.swift
@Observable
class AppState {
    enum State {
        case idle
        case recording
        case stopping
        case processing
        case initializing(progress: Double)
        case downloading(model: String, progress: Double)
        case error(String)
    }
    var current: State = .idle
    var settings: AppSettings = .load()
}
```

**Pipeline-Orchestrierung** (entspricht `_begin_recording` / `_end_recording` in Python):

```swift
// Sources/VoiceFlow/UI/PipelineCoordinator.swift
@MainActor
final class PipelineCoordinator {
    func beginRecording() async
    func endRecording() async

    // Ablauf endRecording():
    //  1. AudioRecorder.stop() → [Float]
    //  2. state = .processing
    //  3. Transcriber.transcribe(audio, vocabulary) → TranscriptionResult
    //  4. TextNormalizer.normalize(text)
    //  5. LLMPostProcessor.process(text, ...) [wenn aktiviert]
    //  6. VocabLearner.learn(original, corrected) [Background]
    //  7. WordLogger.log(...) [Background]
    //  8. TextDelivery.deliver(text, context, bundle, mode)
    //  9. state = .idle
}
```

**Warmup beim Start:**

```swift
// Reihenfolge (sequenziell, zeigt Overlay "Modell lädt..."):
// 1. Transcriber.warmup()   → zeigt "Whisper lädt..."
// 2. LLMPostProcessor.warmup() → zeigt "LLM lädt..."
// 3. state = .idle           → zeigt "Modell bereit" (kurz)
```

---

### 6.2 MenuBarController

**Python-Quelle:** `ui/menubar_app.py` (Menu-Items, Icon-Updates)

```swift
// Sources/VoiceFlow/UI/MenuBarController.swift
import AppKit

final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    func setup(state: AppState)
    func updateIcon(for state: AppState.State)
}
```

**Menu-Struktur** (identisch Python):

- Verlauf…
- ─────────
- Modell ▶ (tiny / base / small / medium / large / large-turbo)
- Sprache ▶ (Auto / Deutsch / English)
- Mikrofon ▶ (Geräteliste dynamisch)
- ─────────
- Textausgabe ▶
- Enhancement-Level ▶
- Enhancement-Stil ▶
- LLM-Runtime ▶
- MLX-Modell ▶
- Ollama-Modell ▶
- ─────────
- Töne ✓
- Bei Login starten ✓
- ─────────
- Beenden

**Icon-Updates:**

```swift
// Template-Image (schwarz/weiß, macOS invertiert automatisch)
statusItem.button?.image = NSImage(named: "MenuBarIcon")
statusItem.button?.image?.isTemplate = true

// Während Recording: animiertes Icon oder Waveform-Symbol
```

**NSMenu in Swift:** Kein `rumps` mehr — direkt `NSMenu` + `NSMenuItem` mit `action`/`target`.
Settings-Änderungen via `@Observable` AppState propagieren.

---

### 6.3 Overlay

**Python-Quelle:** `ui/overlay.py` (~400 Zeilen), `ui/overlay_levels.py`

```swift
// Sources/VoiceFlow/UI/OverlayWindow.swift
import SwiftUI
import AppKit

final class OverlayWindow: NSPanel {
    // NSPanel: floats above all windows, no activation
    // Level: .statusBar + 1
    // StyleMask: .borderless, .nonactivatingPanel
    // CollectionBehavior: .canJoinAllSpaces, .fullScreenAuxiliary
}

struct OverlayView: View {
    @Binding var state: AppState.State
    @State private var phase: Double = 0  // für Waveform-Animation
    @State private var barHeights: [Double] = Array(repeating: 0, count: 9)
    var audioRMS: Float

    var body: some View {
        // Pill-Shape, near-black Hintergrund
        // Recording: Rose-Waveform (3 Harmonische)
        // Processing: Blauer Spinner (Braille-Zeichen rotieren)
        // Downloading: Fortschrittsbalken
        // Ready: kurz "Modell bereit" dann fade out
    }
}
```

**Animation:**

- `TimelineView(.animation(minimumInterval: 1/30))` für 30 fps Waveform
- `OverlayLevelMapper.barHeights(rms: audioRMS, phase: phase)` aus Phase 2
- Glow-Effekt: `shadow(color: .rose, radius: 18)` (SwiftUI) oder CALayer-Shadow (AppKit)
- Rose-Farbe: `#F2667A`, Sky Blue: `#66CCFF`, Near-Black: `#0A0A0F`

**Positionierung:**

```swift
// Bildschirm-Unterkante, zentriert horizontal
let screen = NSScreen.main!
let x = screen.frame.midX - overlayWidth / 2
let y = screen.frame.minY + 20
```

**Risiken:**

- SwiftUI `NSPanel` Integration via `NSHostingView` kann Rendering-Quirks haben
- `TimelineView` auf non-main-Thread-Updates reagiert ggf. mit Delays → RMS-Wert via
  `@Published` oder `withAnimation` auf Main Thread pushen

---

### 6.4 HistoryWindow

**Python-Quelle:** `ui/history_window.py` (~300 Zeilen)

```swift
// Sources/VoiceFlow/UI/HistoryWindow.swift
struct HistoryView: View {
    @State private var entries: [LogEntry] = []
    @State private var searchText = ""
    @State private var selectedTab: Tab = .history

    enum Tab { case history, analytics }

    var body: some View {
        // Tab-Auswahl (Pill-Style, wie Python-Original)
        // .history: List mit Datum-Gruppen, klicken zum Re-Injizieren
        // .analytics: WPM-Gauge, Streak-Heatmap, Session-Stats
    }
}
```

**Analytik-Dashboard** (identisch Python):

- WPM-Gauge via SwiftUI `Canvas`
- GitHub-style Heatmap: `LazyHGrid` mit 7 Zeilen (Wochentage) × N Spalten (Wochen)
- Mini-Cards: Sitzungsdauer, Sitzungen/30 Tage, Genauigkeit, Längster Text

**Fenster öffnen:**

```swift
// Beim Klick auf "Verlauf…" im Menü:
NSApp.activate(ignoringOtherApps: true)
historyWindowController.showWindow(nil)
```

---

### 6.5 SettingsView (optional in Phase 6)

Wenn Zeit: einfaches `Settings`-Fenster via SwiftUI `Settings { ... }` Scene für
Einstellungen die nicht ins Menü passen (Ollama-URL, Debug-Trace).

---

## Swift-Frameworks & Bibliotheken

| Framework                             | Zweck                               |
| ------------------------------------- | ----------------------------------- |
| SwiftUI                               | OverlayView, HistoryView, Analytics |
| AppKit (NSStatusBar, NSMenu, NSPanel) | MenuBar, Overlay-Fenster            |
| Combine / @Observable                 | State-Propagation                   |

---

## Done-Kriterium

- [ ] App startet ohne Dock-Icon, Menubar-Icon erscheint
- [ ] `Fn + Shift` → Overlay erscheint mit Waveform-Animation
- [ ] Loslassen → Overlay zeigt Processing-Spinner, dann verschwindet
- [ ] Text erscheint an Cursor-Position (End-to-End mit allen Phasen)
- [ ] History-Fenster öffnet sich, zeigt bestehende Einträge aus `word_log.jsonl`
- [ ] Modell-Wechsel im Menü lädt neues Modell mit Download-Fortschritt im Overlay
- [ ] Dark Mode funktioniert korrekt (near-black Farben)

## Offene Fragen

- SwiftUI für Overlay oder reines AppKit NSView? (SwiftUI einfacher, AppKit mehr Kontrolle über Rendering-Timing)
- Soll das History-Fenster als `NSWindowController` oder als `openWindow(id:)` (SwiftUI) implementiert werden?
- Re-Injektion aus History: welcher Delivery-Modus soll verwendet werden (aktuelle Settings oder immer TYPE)?
