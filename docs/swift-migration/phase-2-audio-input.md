# Phase 2 — Audio & Hotkey

> **Dauer:** 2–3 Wochen | **Vorgänger:** Phase 1 | **Nachfolger:** Phase 3

## Ziel

Fn+Shift-Hotkey erkennen und Mikrofon-Audio aufnehmen — vollständig nativ, ohne C-Launcher.

## Warum jetzt

Der C-Launcher existiert nur wegen Mikrofon- und Accessibility-Permissions in Python-Prozessen.
Als native Swift-App erhält `VoiceFlow.app` diese Permissions direkt — der gesamte Socket-Mechanismus
entfällt. Phase 3 (Whisper) braucht fertige PCM-Daten als Input.

---

## Komponenten

### 2.1 HotkeyManager

**Python-Quelle:** `core/hotkey_manager.py` (~225 Zeilen)

Der CGEventTap-Ansatz bleibt erhalten — er ist der zuverlässigste Weg für globale Hotkeys ohne
assistive access auf macOS. Nur der PyObjC-Wrapper wird durch Swift-nativen Quartz-Import ersetzt.

```swift
// Sources/VoiceFlow/Input/HotkeyManager.swift
import Quartz

final class HotkeyManager {
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}

    func start()   // CGEventTap installieren, CFRunLoop starten (Background-Thread)
    func stop()    // CGEventTap deaktivieren, CFRunLoop stoppen
}
```

**Implementierungsdetails:**

- `CGEventTapCreate` mit `kCGHIDEventTap`, `kCGHeadInsertEventTap`, `kCGEventTapOptionListenOnly`
- Events: `kCGEventFlagsChanged`, `kCGEventKeyDown`, `kCGEventKeyUp`
- Fn-Erkennung: `CGEventGetFlags(event) & 0x800000 != 0` (NX_DEVICELCMDKEYMASK)
  - Achtung: Fn-Bit ist `1 << 23` = `0x800000`, nicht im Standard-NSEvent-Enum
- Shift-Erkennung: Keycodes 56 (linke Shift), 60 (rechte Shift)
- Callbacks auf `DispatchQueue.main` dispatchen
- Fallback (CGEventTap nicht verfügbar): Polling via `CGEventSourceKeyState` alle 40 ms auf
  `DispatchQueue(label: "hotkey-poll", qos: .userInteractive)`

**Input-Monitoring-Permission:**

- `CGEventTapCreate` schlägt fehl wenn Input Monitoring nicht gewährt
- Beim Fehlschlag: `AXIsProcessTrusted()` prüfen, ggf. Systemeinstellungen öffnen via
  `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)`

**Risiken:**

- Fn-Bit-Maske ist undokumentiert — auf Sequoia (macOS 15) verifizieren
- CGEventTap braucht einen laufenden CFRunLoop auf dem Thread wo er erstellt wurde

---

### 2.2 AudioRecorder

**Python-Quelle:** `core/audio_recorder.py` (~340 Zeilen) + C-Launcher AudioQueue-Code

Der gesamte Socket-Mechanismus (`START_RECORDING`, `STOP_RECORDING`, `GET_RMS`) entfällt.
AVFoundation ersetzt CoreAudio direkt in Swift.

```swift
// Sources/VoiceFlow/Audio/AudioRecorder.swift
import AVFoundation
import Accelerate

actor AudioRecorder {
    // Startet Aufnahme, Buffer-Accumulation im Hintergrund
    func start(deviceID: AudioDeviceID?) async throws

    // Stoppt Aufnahme, gibt normalisiertes float32-Array zurück
    func stop() async -> AudioSamples  // typealias [Float]

    // Aktueller RMS-Pegel (für Overlay-Visualisierung)
    var currentRMS: Float { get }
}
```

**Implementierungsdetails:**

- `AVAudioEngine` + `AVAudioInputNode`
- `installTap(onBus:bufferSize:format:block:)` für kontinuierliche Callbacks
- Sample-Rate: 16.000 Hz, 1 Kanal, Float32 (WhisperKit erwartet dieses Format)
- Buffer-Akkumulation: `[Float]` Array, vorallokiert mit 16.000 \* 120 Samples (2 min),
  via `AVAudioPCMBuffer.floatChannelData`
- RMS: Accelerate `vDSP_rmsqv` in jedem Callback, atomarer Float-Store
- Gerät wählen: `AVCaptureDevice.devices(for: .audio)` → `AudioDeviceID` via CoreAudio
  Property `kAudioHardwarePropertyDefaultInputDevice`
- Format-Conversion (falls Gerät nicht 16kHz liefert): `AVAudioConverter`

**Mikrofon-Permission:**

- `AVCaptureDevice.requestAccess(for: .audio)` beim ersten Start
- Kein Fallback nötig (keine sounddevice-Alternative mehr)

**Risiken:**

- `AVAudioEngine` hat auf manchen Macs einen cold-start Delay (~100 ms) beim ersten `start()`
  → Engine einmalig beim App-Start initialisieren (warm halten), nur tap ein-/ausschalten
- Gerätewechsel während Aufnahme: Engine stoppen/neustarten nötig

---

### 2.3 OverlayLevelMapper

**Python-Quelle:** `ui/overlay_levels.py` (~150 Zeilen)

Reine Mathematik, kein Framework-Bezug.

```swift
// Sources/VoiceFlow/UI/OverlayLevelMapper.swift
struct OverlayLevelMapper {
    /// Konvertiert RMS (0…1) zu 9 normalisierten Balkenhöhen (0…1)
    static func barHeights(rms: Float, phase: Double) -> [Double]
}
```

- Perceptual-Scaling: `pow(rms, 0.4)` (wie Python-Original)
- Sinus-Wellen-Modulation pro Balken mit versetzten Phasen
- Smoothing: exponentielles Moving Average (α = 0.3)

---

### 2.4 C-Launcher entfernen

Nach Phase 2 ist der C-Launcher für Audio und Text-Injektion nicht mehr nötig.
Text-Injektion (CGEvent) wandert in Phase 5 direkt nach Swift.

**Konkret:**

- `build_app.py` LAUNCHER_C-Block bleibt vorerst (wird in Phase 7 entfernt)
- Socket `/tmp/.voiceflow_inject.sock` wird in Phase 5 nicht mehr gestartet
- Python-Fallback-Pfad `audio_recorder.py` bleibt im Python-Branch unberührt

---

## Swift-Frameworks & Bibliotheken

| Framework         | Zweck                                |
| ----------------- | ------------------------------------ |
| AVFoundation      | Mikrofon-Aufnahme, Format-Conversion |
| Accelerate (vDSP) | RMS-Berechnung, Audio-Normalisierung |
| Quartz            | CGEventTap, CGEventGetFlags          |
| CoreAudio         | Geräte-Enumeration (AudioDeviceID)   |

---

## Done-Kriterium

- [ ] `Fn + Shift` starten/stoppen löst Callbacks aus (auf Sequoia verifiziert)
- [ ] Aufnahme liefert `[Float]` mit 16.000 Hz, Stille hat RMS < 0.005
- [ ] `currentRMS` schwankt sichtbar beim Sprechen (manuell via Breakpoint/Log prüfen)
- [ ] Kein C-Launcher-Socket beim Start der Swift-App
- [ ] Tests: `HotkeyManagerTests` (mit Mock-Callbacks), `AudioRecorderTests` (Stille + Ton)

## Offene Fragen

- Soll `AVAudioEngine` permanent warm gehalten werden (empfohlen) oder nur während Aufnahme?
- Welches Gerät soll Standard sein wenn kein Gerät in Settings konfiguriert?
- Fn-Taste auf externen Tastaturen ohne Fn-Taste: alternativen Hotkey anbieten?
