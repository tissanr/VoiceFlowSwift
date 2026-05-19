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
        
        guard result == .success, let focusedCF = focusedElement else {
            return getFromActiveWindow()
        }
        let element = focusedCF as! AXUIElement
        return getContext(from: element)
    }
    
    /// Extrahiert den Kontext aus einem AXUIElement
    private static func getContext(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        
        guard valueResult == .success, let text = value as? String else {
            return nil
        }
        
        var selectedRangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        
        var range = CFRange(location: 0, length: 0)
        if rangeResult == .success, let rangeCF = selectedRangeValue {
            AXValueGetValue(rangeCF as! AXValue, .cfRange, &range)
        } else {
            range.location = text.count
        }
        
        let index = text.index(text.startIndex, offsetBy: max(0, min(range.location, text.count)))
        return String(text[..<index])
    }
    
    private static func getFromActiveWindow() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFTypeRef)
        
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success else {
            return nil
        }
        
        guard let windowCF = focusedWindow else { return nil }
        let win = windowCF as! AXUIElement
        var focusedElement: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
           let focusedCF = focusedElement {
            return getContext(from: focusedCF as! AXUIElement)
        }
        
        return nil
    }
    
    static func shouldCapitalize(context: String?) -> Bool {
        guard let context = context?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty else {
            return true
        }
        
        let sentenceEndings: Set<Character> = [".", "!", "?", "\n"]
        if let lastChar = context.last, sentenceEndings.contains(lastChar) {
            return true
        }
        
        return false
    }
}
