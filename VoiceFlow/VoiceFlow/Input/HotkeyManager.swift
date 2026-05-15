import Quartz
import AppKit

// Phase 2 — Globaler Fn+Shift Hotkey via CGEventTap
// Fn-Bit (0x800000) ist undokumentiert aber auf Sequoia stabil.
final class HotkeyManager {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var pollTimer: DispatchSourceTimer?

    private var fnDown = false
    private var shiftDown = false
    private var recording = false

    // MARK: - Public

    func start() {
        guard eventTap == nil, pollTimer == nil else { return }
        if createEventTap() {
            print("[HotkeyManager] CGEventTap created — listening for Fn+Shift")
        } else {
            print("[HotkeyManager] CGEventTap failed — falling back to polling")
            startPollingFallback()
        }
    }

    func stop() {
        eventTap.map { CGEvent.tapEnable(tap: $0, enable: false) }
        if let source = runLoopSource, let thread = tapThread {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            _ = thread  // thread exits when RunLoop stops
        }
        eventTap = nil
        runLoopSource = nil
        tapThread = nil
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - CGEventTap

    private func createEventTap() -> Bool {
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            openInputMonitoringSettings()
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source

        let t = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        t.name = "HotkeyManager.tap"
        t.qualityOfService = .userInteractive
        t.start()
        tapThread = t
        return true
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        let flags = event.flags
        // Fn-Bit 0x800000 ist undokumentiert (NX_DEVICELFNKEYMASK); auf Sequoia verifiziert.
        let fnBit = CGEventFlags(rawValue: 0x0080_0000)

        if type == .flagsChanged {
            let newFn = flags.contains(fnBit)
            let newShift = flags.contains(.maskShift)
            print("[HotkeyManager] flagsChanged raw=0x\(String(flags.rawValue, radix: 16)) fn=\(newFn) shift=\(newShift)")
            fnDown = newFn
            shiftDown = newShift
        }

        updateRecordingState()
    }

    // MARK: - Polling fallback (kein Input Monitoring grant)

    private func startPollingFallback() {
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "voiceflow.hotkey-poll", qos: .userInteractive)
        )
        timer.schedule(deadline: .now(), repeating: .milliseconds(40))
        timer.setEventHandler { [weak self] in self?.pollKeys() }
        timer.resume()
        pollTimer = timer
    }

    private func pollKeys() {
        fnDown = CGEventSource.keyState(.hidSystemState, key: 63)   // kVK_Function
        shiftDown = CGEventSource.keyState(.hidSystemState, key: 56) // kVK_Shift
            || CGEventSource.keyState(.hidSystemState, key: 60)      // kVK_RightShift
        updateRecordingState()
    }

    // MARK: - State

    private func updateRecordingState() {
        let active = fnDown && shiftDown
        if active && !recording {
            recording = true
            DispatchQueue.main.async { self.onStart?() }
        } else if !active && recording {
            recording = false
            DispatchQueue.main.async { self.onStop?() }
        }
    }

    private func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
