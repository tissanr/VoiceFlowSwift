import Foundation
import AppKit

enum DeliveryResult {
    case success
    case failure(String)
}

struct TextSpacing {
    static func addLeadingSpace(text: String, context: String?) -> String {
        guard let context = context, !context.isEmpty else { return text }
        if let lastChar = context.last, lastChar.isWhitespace || lastChar == "\n" { return text }
        if let firstChar = text.first, firstChar.isWhitespace { return text }
        return " " + text
    }
    
    static func capitalize(text: String, shouldCapitalize: Bool) -> String {
        guard shouldCapitalize, !text.isEmpty else { return text }
        var chars = Array(text)
        for i in 0..<chars.count {
            if chars[i].isLetter {
                chars[i] = Character(chars[i].uppercased())
                break
            }
        }
        return String(chars)
    }
}

final class TextDelivery {
    private static let terminalBundles: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "com.github.wez.wezterm", "net.kovidgoyal.kitty", "co.zeit.hyper", "io.alacritty"]
    private static let browserBundles: Set<String> = ["com.google.Chrome", "org.mozilla.firefox", "com.apple.Safari", "com.microsoft.edgemac", "com.microsoft.VSCode", "com.github.Electron"]
    
    static func deliver(text: String, context: String?, outputMode: TextOutputMode = .automatic) async -> DeliveryResult {
        var processedText = TextNormalizer.normalize(text)
        processedText = PostProcessor.process(processedText)
        let shouldCap = CursorContext.shouldCapitalize(context: context)
        processedText = TextSpacing.capitalize(text: processedText, shouldCapitalize: shouldCap)
        processedText = TextSpacing.addLeadingSpace(text: processedText, context: context)
        
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        switch outputMode {
        case .typing: return TextInjector.typeText(processedText) ? .success : .failure("Typing failed")
        case .paste: return await pasteDelivery(processedText)
        case .clipboardOnly: await TextInjector.copyToClipboard(processedText); return .success
        case .automatic:
            if terminalBundles.contains(bundleID) { return TextInjector.typeText(processedText.trimmingCharacters(in: .newlines)) ? .success : .failure("Terminal typing failed") }
            if let context = context {
                if TextInjector.insertDirect(processedText, context: context) { return .success }
                return TextInjector.typeText(processedText) ? .success : .failure("Fallback typing failed")
            }
            if browserBundles.contains(bundleID) { return await pasteDelivery(processedText) }
            await TextInjector.copyToClipboard(processedText); return .success
        }
    }
    
    private static func pasteDelivery(_ text: String) async -> DeliveryResult {
        let (oldText, oldItems) = await TextInjector.saveClipboard()
        await TextInjector.copyToClipboard(text)
        if TextInjector.triggerPaste() {
            try? await Task.sleep(for: .milliseconds(100))
            await TextInjector.restoreClipboard(text: oldText, items: oldItems)
            return .success
        }
        return .failure("Paste failed")
    }
}
