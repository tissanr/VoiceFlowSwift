import Foundation
import AppKit

enum DeliveryResult {
    case success
    case failure(String)
}

/// Phase 5 — Spacing & Formatting Helpers
struct TextSpacing {
    /// Fügt ein führendes Leerzeichen hinzu, wenn nötig
    static func addLeadingSpace(text: String, context: String?) -> String {
        guard let context = context, !context.isEmpty else {
            return text
        }
        
        // Wenn der Kontext mit Whitespace endet, brauchen wir kein Leerzeichen
        if let lastChar = context.last, lastChar.isWhitespace || lastChar == "\n" {
            return text
        }
        
        // Wenn der Text bereits mit Whitespace beginnt, brauchen wir kein Leerzeichen
        if let firstChar = text.first, firstChar.isWhitespace {
            return text
        }
        
        return " " + text
    }
    
    /// Stellt sicher, dass der Text korrekt großgeschrieben wird
    static func capitalize(text: String, shouldCapitalize: Bool) -> String {
        guard shouldCapitalize, !text.isEmpty else {
            return text
        }
        
        var chars = Array(text)
        // Finde das erste alphabetische Zeichen
        for i in 0..<chars.count {
            if chars[i].isLetter {
                chars[i] = Character(chars[i].uppercased())
                break
            }
        }
        return String(chars)
    }
}

/// Phase 5 — Delivery-Pipeline (inject / paste / clipboard fallback)
final class TextDelivery {
    
    private static let terminalBundles: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2",
        "com.github.wez.wezterm", "net.kovidgoyal.kitty",
        "co.zeit.hyper", "io.alacritty"
    ]
    
    private static let browserBundles: Set<String> = [
        "com.google.Chrome", "org.mozilla.firefox", "com.apple.Safari",
        "com.microsoft.edgemac", "com.microsoft.VSCode", "com.github.Electron"
    ]
    
    /// Liefert den Text an die Ziel-App aus
    static func deliver(
        text: String,
        context: String?,
        outputMode: TextOutputMode = .automatic
    ) async -> DeliveryResult {
        
        // 1. Vorverarbeitung
        var processedText = TextNormalizer.normalize(text)
        processedText = PostProcessor.process(processedText)
        
        // 2. Formatting basierend auf Kontext
        let shouldCap = CursorContext.shouldCapitalize(context: context)
        processedText = TextSpacing.capitalize(text: processedText, shouldCapitalize: shouldCap)
        processedText = TextSpacing.addLeadingSpace(text: processedText, context: context)
        
        // 3. Ziel-App bestimmen
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmostApp?.bundleIdentifier ?? ""
        
        // 4. Delivery-Strategie wählen
        switch outputMode {
        case .typing:
            return typeDelivery(processedText, bundleID: bundleID)
            
        case .paste:
            return await pasteDelivery(processedText)
            
        case .clipboardOnly:
            await TextInjector.copyToClipboard(processedText)
            return .success
            
        case .automatic:
            if terminalBundles.contains(bundleID) {
                // Terminal: trailing newlines oft problematisch bei TYPE
                let trimmed = processedText.trimmingCharacters(in: .newlines)
                return typeDelivery(trimmed, bundleID: bundleID)
            } else if context != nil {
                // Native App mit Kontext: Direct AX
                if TextInjector.insertDirect(processedText, context: context!) {
                    return .success
                }
                // Fallback wenn Direct AX fehlschlägt
                return typeDelivery(processedText, bundleID: bundleID)
            } else if browserBundles.contains(bundleID) {
                // Browser/Electron ohne Kontext: Paste
                return await pasteDelivery(processedText)
            } else {
                // Fallback: Clipboard
                await TextInjector.copyToClipboard(processedText)
                return .success
            }
        }
    }
    
    private static func typeDelivery(_ text: String, bundleID: String) -> DeliveryResult {
        if TextInjector.typeText(text) {
            return .success
        }
        return .failure("Keyboard simulation failed")
    }
    
    private static func pasteDelivery(_ text: String) async -> DeliveryResult {
        // Clipboard sichern
        let (oldText, oldItems) = await TextInjector.saveClipboard()
        
        // Neuen Text kopieren
        await TextInjector.copyToClipboard(text)
        
        // Paste triggern
        if TextInjector.triggerPaste() {
            // Kurze Pause damit die App das Paste verarbeiten kann bevor wir es wiederherstellen
            try? await Task.sleep(for: .milliseconds(100))
            
            // Clipboard wiederherstellen
            await TextInjector.restoreClipboard(text: oldText, items: oldItems)
            return .success
        }
        
        return .failure("Paste simulation failed")
    }
}
