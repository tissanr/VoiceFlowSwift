import Cocoa
import Combine

/// Phase 6 — NSStatusItem Menubar-Controller
@MainActor
final class MenuBarController: NSObject {
    
    private var statusItem: NSStatusItem!
    private let state: AppState
    private var cancellables = Set<AnyCancellable>()
    
    // Actions
    var onHistoryOpen: (() -> Void)?
    var onQuit: (() -> Void)?
    
    init(state: AppState) {
        self.state = state
        super.init()
        setupStatusItem()
        setupObservers()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoiceFlow")
            button.image?.isTemplate = true
        }
        buildMenu()
    }
    
    private func setupObservers() {
        state.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.updateIcon(for: status)
            }
            .store(in: &cancellables)
    }
    
    private func buildMenu() {
        let menu = NSMenu()
        
        // 1. Verlauf
        menu.addItem(withTitle: "Verlauf...", action: #selector(historyClicked), keyEquivalent: "y").target = self
        menu.addItem(NSMenuItem.separator())
        
        // 2. Modell
        let modelMenu = NSMenu()
        ["tiny", "base", "small", "medium", "large-v3", "large-v3-turbo", "large-turbo"].forEach { variant in
            let item = NSMenuItem(title: variant, action: #selector(modelSelected(_:)), keyEquivalent: "")
            item.target = self
            item.state = (state.settings.modelSize == variant) ? .on : .off
            modelMenu.addItem(item)
        }
        let modelItem = NSMenuItem(title: "Modell", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)
        
        // 3. Sprache
        let langMenu = NSMenu()
        ["auto", "de", "en"].forEach { lang in
            let item = NSMenuItem(title: lang, action: #selector(languageSelected(_:)), keyEquivalent: "")
            item.target = self
            item.state = (state.settings.language == lang) ? .on : .off
            langMenu.addItem(item)
        }
        let langItem = NSMenuItem(title: "Sprache", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. Settings Toggles
        let soundItem = NSMenuItem(title: "Töne", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = state.settings.soundEnabled ? .on : .off
        menu.addItem(soundItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Beenden
        menu.addItem(withTitle: "Beenden", action: #selector(quitClicked), keyEquivalent: "q").target = self
        
        statusItem.menu = menu
    }
    
    private func updateIcon(for status: AppStatus) {
        guard let button = statusItem.button else { return }
        switch status {
        case .idle:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Bereit")
        case .recording:
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Aufnahme...")
        case .processing, .stopping:
            button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Verarbeitung...")
        case .error:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Fehler")
        default:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoiceFlow")
        }
        button.image?.isTemplate = true
    }
    
    // MARK: - Actions
    
    @objc private func historyClicked() {
        onHistoryOpen?()
    }
    
    @objc private func modelSelected(_ sender: NSMenuItem) {
        state.settings.modelSize = sender.title
        state.settings.save()
        buildMenu()
    }
    
    @objc private func languageSelected(_ sender: NSMenuItem) {
        state.settings.language = sender.title
        state.settings.save()
        buildMenu()
    }
    
    @objc private func toggleSound() {
        state.settings.soundEnabled.toggle()
        state.settings.save()
        buildMenu()
    }
    
    @objc private func quitClicked() {
        onQuit?()
    }
}
