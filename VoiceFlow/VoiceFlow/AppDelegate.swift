import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkey = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("✅ APP STARTED")
        NSApp.setActivationPolicy(.accessory)

        hotkey.onStart = { print("[HotkeyManager] ▶ recording started") }
        hotkey.onStop  = { print("[HotkeyManager] ■ recording stopped") }
        hotkey.start()
    }

    func applicationWillTerminate(_ notification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
