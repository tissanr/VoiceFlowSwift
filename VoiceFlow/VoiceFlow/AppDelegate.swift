import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Phase 6: MenuBarController hier initialisieren
    }

    func applicationWillTerminate(_ notification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
