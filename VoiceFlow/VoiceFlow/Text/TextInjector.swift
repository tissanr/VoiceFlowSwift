import Foundation
import ApplicationServices
import AppKit
import Quartz

/// Phase 5 — Text-Injektion via CGEventPost / AX API
final class TextInjector {

    static func typeText(_ text: String) async -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
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
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    static func insertDirect(_ text: String, context: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedCF = focusedElement else { return false }
        let element = focusedCF as! AXUIElement

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let currentText = value as? String else { return false }

        // Split at the context boundary using UTF-16 offsets to match the AX API
        let utf16Count = context.utf16.count
        let utf16View = currentText.utf16
        guard let splitUTF16 = utf16View.index(utf16View.startIndex, offsetBy: utf16Count, limitedBy: utf16View.endIndex),
              let splitChar = splitUTF16.samePosition(in: currentText) else { return false }
        let newValue = String(currentText[..<splitChar]) + text + String(currentText[splitChar...])

        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef) == .success else { return false }

        // Cursor position as UTF-16 offset so AX places it correctly
        var range = CFRange(location: utf16Count + text.utf16.count, length: 0)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return true }
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

    // Deep-copies all item data before clearContents() invalidates the live items.
    @MainActor static func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = NSPasteboard.general.pasteboardItems else { return [] }
        return items.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    @MainActor static func restoreClipboard(_ saved: [[NSPasteboard.PasteboardType: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !saved.isEmpty else { return }
        let newItems = saved.map { typeDataMap -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in typeDataMap { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(newItems)
    }
}
