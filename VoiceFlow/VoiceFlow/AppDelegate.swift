import Cocoa
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    private let state = AppState.shared
    private var menuBar: MenuBarController?
    private var pipeline: PipelineCoordinator?
    private let hotkey = HotkeyManager()
    
    private var overlayWindow: OverlayWindow?
    private var historyWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("✅ VOICEFLOW STARTED")
        NSApp.setActivationPolicy(.accessory)
        
        // 1. Initialisierung
        self.menuBar = MenuBarController(state: state)
        self.pipeline = PipelineCoordinator(state: state)
        self.overlayWindow = OverlayWindow()
        
        // SwiftUI View in Overlay einbetten
        let overlayView = OverlayView(state: state)
        overlayWindow?.contentView = NSHostingView(rootView: overlayView)
        
        // 2. Hotkey Setup
        hotkey.onStart = { [weak self] in
            Task { @MainActor in
                await self?.pipeline?.beginRecording()
                self?.showOverlay(true)
            }
        }
        hotkey.onStop = { [weak self] in
            Task { @MainActor in
                await self?.pipeline?.endRecording()
                // Overlay bleibt ggf. noch für Processing sichtbar
                // und wird via State-Observer in showOverlay gesteuert
            }
        }
        hotkey.start()
        
        // 3. MenuBar Actions
        menuBar?.onHistoryOpen = { [weak self] in
            self?.showHistory()
        }
        menuBar?.onQuit = {
            NSApp.terminate(nil)
        }
        
        // 4. Warmup
        Task {
            await pipeline?.warmup()
        }
        
        setupStateObservers()
    }

    private func setupStateObservers() {
        state.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                switch status {
                case .idle:
                    self?.showOverlay(false)
                case .recording, .processing, .stopping, .initializing, .downloading:
                    self?.showOverlay(true)
                case .error(let msg):
                    print("ERROR: \(msg)")
                    self?.showOverlay(true)
                }
            }
            .store(in: &state.cancellables)
    }
    
    private func showOverlay(_ show: Bool) {
        if show {
            overlayWindow?.orderFrontRegardless()
        } else {
            overlayWindow?.orderOut(nil)
        }
    }
    
    private func showHistory() {
        if historyWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "VoiceFlow Verlauf"
            window.contentView = NSHostingView(rootView: HistoryView())
            window.delegate = self
            window.center()
            self.historyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        historyWindow = nil
    }

    func applicationWillTerminate(_ notification: Notification) {}
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
