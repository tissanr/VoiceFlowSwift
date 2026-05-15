# Phase 5 — Text Delivery & AX API

> **Dauer:** 3–4 Wochen | **Vorgänger:** Phase 3 | **Nachfolger:** Phase 6

## Ziel

Transkribierten Text an der Cursor-Position in jede App injizieren — nativ in Swift, ohne
C-Launcher-Socket.

## Warum jetzt

Kann parallel zu Phase 4 laufen. Text Delivery ist das technisch riskanteste Modul der gesamten
Migration (AX API-Verhalten variiert stark zwischen Apps). Früher Start gibt Zeit für QA.

---

## Komponenten

### 5.1 CursorContext

**Python-Quelle:** `core/cursor_context.py` (~508 Zeilen)

Das komplexeste Modul. Liest Text vor dem Cursor via Accessibility API — drei Fallback-Strategien.

```swift
// Sources/VoiceFlow/Text/CursorContext.swift
import ApplicationServices

struct CursorContext {
    /// Text vor dem Cursor im fokussierten Textfeld, oder nil wenn nicht lesbar
    static func get() -> String?

    /// True wenn Cursor an Satzanfang steht (nach ".!?" oder am Textbeginn)
    static func shouldCapitalize(context: String?) -> Bool
}
```

**Strategie 1 — Direct AX (native Apps):**

```swift
let systemWide = AXUIElementCreateSystemWide()
var focusedElement: CFTypeRef?
AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

var value: CFTypeRef?
AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &value)

var selectedRange = CFRange()
// AXValueGetValue mit kAXValueCFRangeType
```

**Strategie 2 — AXManualAccessibility (Electron/Chromium):**

```swift
// Einmalig pro PID setzen:
AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)
// 150 ms warten (Chromium baut AX-Tree auf)
try await Task.sleep(for: .milliseconds(150))
// Dann Strategie 1 wiederholen
```

**Strategie 3 — AX Tree Traversal (Fallback):**

```swift
// Rekursiv durch kAXChildrenAttribute ab kAXFocusedWindowAttribute
// Suche nach Element mit kAXFocusedAttribute = true und kAXValueAttribute != nil
```

**Bekannte Eigenheiten (aus Python-Code übernehmen!):**

- Newline-Run-Korrektur: Wenn Kontext mit `\n` endet, kompletten zusammenhängenden Newline-Run einschließen
- `start == 0` und `current == cursor_context` → kein Placeholder-Delete, nur ans Ende anfügen
- Electron: nach `AXManualAccessibility` PID cachen, nicht erneut setzen
- Leerer String `""` ist gültiger Kontext (Cursor am Textanfang), `nil` bedeutet kein Textfeld

**CFRange in Swift:**

```swift
// AXValueCreate / AXValueGetValue für CFRange braucht UnsafeMutablePointer
var range = CFRange()
let axValue = AXValueCreate(.cfRange, &range)!
var outRange = CFRange()
AXValueGetValue(axValue, .cfRange, &outRange)
```

**Risiken:**

- **Größtes Risiko der gesamten Migration.** AX API verhält sich unterschiedlich auf macOS 13/14/15,
  in nativen Apps, Electron, WebKit, Terminal.
- Electron-Apps (Claude Code, VS Code) brauchen `AXManualAccessibility` — testen ob das in
  Swift genauso funktioniert wie in PyObjC
- CGEventTap und AX API können sich gegenseitig blockieren wenn auf demselben Thread

---

### 5.2 TextInjector

**Python-Quelle:** `core/text_injector.py` (~697 Zeilen)

```swift
// Sources/VoiceFlow/Text/TextInjector.swift
import Quartz
import ApplicationServices

struct TextInjector {
    /// Injiziert Text via Keyboard-Events (kein Clipboard)
    static func typeText(_ text: String) -> Bool

    /// Setzt Text direkt per AXValue (für native Apps mit Cursor-Kontext)
    static func insertDirect(_ text: String, context: String) -> Bool

    /// Cmd+V simulieren
    static func triggerPaste() -> Bool

    /// Cursor-Position via AX-Selection wiederherstellen
    static func restoreCursor(to context: String) -> Bool
}
```

**TYPE via CGEvent (kein Clipboard):**

```swift
static func typeText(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!

        if scalar.value == 0x0A {  // Newline → Return-Keycode
            keyDown.setIntValueField(.keyboardEventKeycode, value: 36)
            keyUp.setIntValueField(.keyboardEventKeycode, value: 36)
        } else {
            var utf16 = [UniChar](scalar.utf16)
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
    return true
}
```

**AX Direct Insert:**

```swift
// Identische Logik wie Python insert_text_direct():
// 1. Lese aktuellen AXValue
// 2. Prüfe ob current.hasPrefix(context) (Safety-Check)
// 3. Baue neuen Wert: current[..<context.endIndex] + text + current[context.endIndex...]
// 4. AXUIElementSetAttributeValue(kAXValueAttribute)
// 5. Setze kAXSelectedTextRangeAttribute auf Ende des eingefügten Texts
```

**Clipboard-Management:**

```swift
// NSPasteboard muss auf Main Thread aufgerufen werden
@MainActor static func copyToClipboard(_ text: String)
@MainActor static func saveClipboard() -> String?
@MainActor static func restoreClipboard(_ text: String?)
```

---

### 5.3 TextDelivery

**Python-Quelle:** `core/text_delivery.py` (~150 Zeilen), `core/text_spacing.py`

```swift
// Sources/VoiceFlow/Text/TextDelivery.swift
struct TextDelivery {
    static func deliver(
        text: String,
        context: String?,
        frontmostBundle: String?,
        outputMode: TextOutputMode
    ) async -> DeliveryResult
}
```

**Routing-Logik** (direkt aus Python portieren):

```swift
// Terminal-Apps → TYPE
let terminalBundles: Set<String> = [
    "com.apple.Terminal", "com.googlecode.iterm2",
    "com.github.wez.wezterm", "net.kovidgoyal.kitty",
    "co.zeit.hyper", "io.alacritty"
]

// Browser/Electron + kein Cursor-Kontext → Clipboard + Cmd+V
let browserBundles: Set<String> = [
    "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac",
    "com.microsoft.VSCode", "com.github.Electron", ...
]

// Logik:
if frontmostBundle ∈ terminalBundles → typeText (trailing newlines entfernen)
else if context != nil              → insertDirect oder restoreCursor + typeText
else if frontmostBundle ∈ browserBundles → clipboard + triggerPaste
else                                → clipboard only (show overlay)
```

**TextSpacing:**

```swift
struct TextSpacing {
    static func addLeadingSpace(text: String, context: String?) -> String
    static func capitalize(text: String, shouldCapitalize: Bool?) -> String
}
```

---

## Swift-Frameworks & Bibliotheken

| Framework             | Zweck                                       |
| --------------------- | ------------------------------------------- |
| ApplicationServices   | AX API (Cursor lesen, Text direkt setzen)   |
| Quartz                | CGEvent (Keyboard-Events, Paste-Simulation) |
| AppKit (NSPasteboard) | Clipboard lesen/schreiben                   |
| Foundation            | Bundle-ID via NSRunningApplication          |

---

## Done-Kriterium

- [ ] Text wird in TextEdit an Cursor-Position injiziert (Direct AX)
- [ ] Text wird in VS Code (Electron) korrekt injiziert (AXManualAccessibility)
- [ ] Text wird in Terminal.app via TYPE injiziert (keine Newline am Ende)
- [ ] Text wird in Chrome-Webformular via Clipboard+Cmd+V eingefügt
- [ ] Clipboard wird nach Injektion wiederhergestellt (kein Leak in Clipboard-Manager)
- [ ] Tests: `CursorContextTests` (Mock-AX), `TextInjectorTests`, `TextDeliveryTests`

## Offene Fragen

- AX API-Zugriff in Swift: direkt via C-Bridging-Header oder via `ApplicationServices` Swift-Overlay?
  (C-Bridging ist zuverlässiger für Low-Level-AX-Calls)
- Soll `AXObserver` für reaktive Cursor-Updates genutzt werden oder weiterhin Pull-Modell (vor Aufnahme lesen)?
- Muss die Accessibility-Permission-Anfrage beim App-Start explizit durch `AXIsProcessTrusted(options:)` getriggert werden?
