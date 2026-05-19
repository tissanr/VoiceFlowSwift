import Foundation
import ApplicationServices
import AppKit

/// Phase 5 — Cursor-Kontext via AX API
struct CursorContext {
    
    /// Holt den Text vor dem Cursor im aktuell fokussierten Element
    static func get() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement as! AXUIElement? else {
            // Fallback: Suche nach dem fokussierten Element im aktiven Fenster
            return getFromActiveWindow()
        }
        
        return getContext(from: element)
    }
    
    /// Extrahiert den Kontext aus einem AXUIElement
    private static func getContext(from element: AXUIElement) -> String? {
        // 1. Prüfe ob es ein Textfeld ist
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        // 2. Versuche AXValue zu lesen
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        
        guard valueResult == .success, let text = value as? String else {
            return nil
        }
        
        // 3. Versuche die Selektion zu finden
        var selectedRangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        
        var range = CFRange(location: 0, length: 0)
        if rangeResult == .success {
            AXValueGetValue(selectedRangeValue as! AXValue, .cfRange, &range)
        } else {
            // Wenn keine Range verfügbar, nehmen wir an der Cursor ist am Ende
            range.location = text.count
        }
        
        // 4. Extrahiere Text bis zum Cursor
        let index = text.index(text.startIndex, offsetBy: max(0, min(range.location, text.count)))
        let context = String(text[..<index])
        
        return context
    }
    
    /// Fallback: Sucht das fokussierte Element im aktiven Fenster
    private static func getFromActiveWindow() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        // Versuche AXManualAccessibility für Electron/Chromium zu setzen
        // Das ist ein bekannter Trick um Accessibility in Chromium-Apps zu erzwingen
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)
        
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success else {
            return nil
        }
        
        // Hier könnte man rekursiv nach dem Element mit kAXFocusedAttribute = true suchen
        // Für den Anfang versuchen wir das fokussierte Element direkt vom Fenster zu bekommen
        var focusedElement: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success {
            return getContext(from: focusedElement as! AXUIElement)
        }
        
        return nil
    }
    
    /// Prüft ob der Kontext eine Großschreibung am Anfang des nächsten Wortes erfordert
    static func shouldCapitalize(context: String?) -> Bool {
        guard let context = context?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty else {
            return true // Anfang des Dokuments
        }
        
        // Prüfe auf Satzende-Zeichen am Ende des Kontexts
        let sentenceEndings: Set<Character> = [".", "!", "?", "\n"]
        if let lastChar = context.last, sentenceEndings.contains(lastChar) {
            return true
        }
        
        return false
    }
}
