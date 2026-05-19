import Foundation
import ApplicationServices
import AppKit
import Quartz

/// Phase 5 — Text-Injektion via CGEventPost / AX API
final class TextInjector {
    
    static func typeText(_ text: String) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        for scalar in text.unicodeScalars {
            let keyCode: CGKeyCode = (scalar.value == 0x0A || scalar.value == 0x0D) ? 36 : 0
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { continue }
            
            if keyCode == 0 {
                var utf16 = Array(scalar.utf16)
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.001)
        }
        return true
    }
    
    static func insertDirect(_ text: String, context: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else { return false }
        let element = focusedElement as! AXUIElement
        
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let currentText = value as? String else { return false }
        
        let prefix = currentText.prefix(context.count)
        let suffix = currentText.dropFirst(context.count)
        let newValue = String(prefix) + text + String(suffix)
        
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef) == .success else { return false }
        
        var range = CFRange(location: context.count + text.count, length: 0)
        let axRange = AXValueCreate(.cfRange, &range)!
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        return true
    }
    
    static func triggerPaste() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
    
    @MainActor static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    @MainActor static func saveClipboard() -> (String?, [NSPasteboardItem]?) {
        let pb = NSPasteboard.general
        return (pb.string(forType: .string), pb.pasteboardItems)
    }
    
    @MainActor static func restoreClipboard(text: String?, items: [NSPasteboardItem]?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let items = items { pb.writeObjects(items) }
        else if let text = text { pb.setString(text, forType: .string) }
    }
}
