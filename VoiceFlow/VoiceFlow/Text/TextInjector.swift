import Foundation
import ApplicationServices
import AppKit
import Quartz

/// Phase 5 — Text-Injektion via CGEventPost / AX API
final class TextInjector {
    
    /// Injiziert Text via Keyboard-Events (kein Clipboard)
    static func typeText(_ text: String) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        for scalar in text.unicodeScalars {
            let keyCode: CGKeyCode
            let isNewline = (scalar.value == 0x0A || scalar.value == 0x0D)
            
            if isNewline {
                keyCode = 36 // Return Keycode
            } else {
                keyCode = 0 // Wird ignoriert wenn Unicode-String gesetzt wird
            }
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
                continue
            }
            
            if !isNewline {
                var utf16 = Array(scalar.utf16)
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            }
            
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            
            // Kurze Pause zwischen Zeichen um Überlastung zu vermeiden
            Thread.sleep(forTimeInterval: 0.001)
        }
        
        return true
    }
    
    /// Setzt Text direkt per AXValue (für native Apps)
    static func insertDirect(_ text: String, context: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return false
        }
        
        let element = focusedElement as! AXUIElement
        
        // 1. Hole aktuellen Wert
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let currentText = value as? String else {
            return false
        }
        
        // 2. Erstelle neuen Wert
        let prefix = currentText.prefix(context.count)
        let suffix = currentText.dropFirst(context.count)
        let newValue = String(prefix) + text + String(suffix)
        
        // 3. Setze neuen Wert
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef) == .success else {
            return false
        }
        
        // 4. Setze Cursor ans Ende des eingefügten Texts
        var range = CFRange(location: context.count + text.count, length: 0)
        let axRange = AXValueCreate(.cfRange, &range)!
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        
        return true
    }
    
    /// Cmd+V simulieren
    static func triggerPaste() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        let cmdKey: CGEventFlags = .maskCommand
        
        // 'v' Keycode ist 9
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }
        
        keyDown.flags = cmdKey
        keyUp.flags = cmdKey
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        return true
    }
    
    // MARK: - Clipboard Management
    
    @MainActor
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    @MainActor
    static func saveClipboard() -> (String?, [NSPasteboardItem]?) {
        let pasteboard = NSPasteboard.general
        return (pasteboard.string(forType: .string), pasteboard.pasteboardItems)
    }
    
    @MainActor
    static func restoreClipboard(text: String?, items: [NSPasteboardItem]?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let items = items {
            pasteboard.writeObjects(items)
        } else if let text = text {
            pasteboard.setString(text, forType: .string)
        }
    }
}
