import Quartz
import AppKit

// Phase 2 — Global Fn+Shift hotkey via CGEventTap
// Fn bit (0x800000) is undocumented but stable on Sequoia.
final class HotkeyManager {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var pollTimer: DispatchSourceTimer?
    private var permissionRetryTimer: DispatchSourceTimer?
    private var didOpenInputMonitoringSettings = false

    private var fnDown = false
    private var shiftDown = false
    private var recording = false
    private var lastPollFnDown = false
    private var lastPollShiftDown = false

    private enum KeyCode {
        static let fn: CGKeyCode = 63
        static let leftShift: CGKeyCode = 56
        static let rightShift: CGKeyCode = 60
    }

    // MARK: - Public

    func start() {
        guard eventTap == nil, pollTimer == nil else { return }

        if createEventTap(openSettingsOnFailure: true) {
            print("[HotkeyManager] CGEventTap created — listening for Fn+Shift")
        } else {
            print("[HotkeyManager] CGEventTap failed — polling fallback active, retrying")
            startPollingFallback()
            startPermissionRetryTimer()
        }
    }

    func stop() {
        permissionRetryTimer?.cancel()
        permissionRetryTimer = nil
        pollTimer?.cancel()
        pollTimer = nil

        eventTap.map { CGEvent.tapEnable(tap: $0, enable: false) }
        if let tapRunLoop {
            let source = runLoopSource
            CFRunLoopPerformBlock(tapRunLoop, CFRunLoopMode.commonModes.rawValue) {
                if let source {
                    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                }
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(tapRunLoop)
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        fnDown = false
        shiftDown = false
        recording = false
    }

    // MARK: - CGEventTap

    private func createEventTap(openSettingsOnFailure: Bool) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        var created = false

        let t = Thread {
            let mask: CGEventMask =
                (1 << CGEventType.flagsChanged.rawValue) |
                (1 << CGEventType.keyDown.rawValue) |
                (1 << CGEventType.keyUp.rawValue)

            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                    manager.handleEvent(type: type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                sem.signal()
                return
            }

            let runLoop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.eventTap = tap
            self.runLoopSource = source
            self.tapRunLoop = runLoop
            created = true
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            sem.signal()
            CFRunLoopRun()
        }
        t.name = "HotkeyManager.tap"
        t.qualityOfService = .userInteractive
        t.start()
        sem.wait()
        if created {
            tapThread = t
            return true
        }

        if openSettingsOnFailure {
            openInputMonitoringSettingsOnce()
        }
        return false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                print("[HotkeyManager] CGEventTap re-enabled")
            }
            return
        }

        let flags = event.flags
        // Fn bit 0x800000 is undocumented (NX_DEVICELFNKEYMASK); verified on Sequoia.
        let fnBit = CGEventFlags(rawValue: 0x0080_0000)
        if type == .flagsChanged {
            fnDown = flags.contains(fnBit)
            shiftDown = flags.contains(.maskShift)
            print("[HotkeyManager] flagsChanged raw=0x\(String(flags.rawValue, radix: 16)) fn=\(fnDown) shift=\(shiftDown)")
        }

        updateRecordingState()
    }

    // MARK: - Polling fallback (no Input Monitoring grant)

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
        fnDown = CGEventSource.keyState(.hidSystemState, key: KeyCode.fn)
        shiftDown = CGEventSource.keyState(.hidSystemState, key: KeyCode.leftShift)
            || CGEventSource.keyState(.hidSystemState, key: KeyCode.rightShift)
        if fnDown != lastPollFnDown || shiftDown != lastPollShiftDown {
            lastPollFnDown = fnDown
            lastPollShiftDown = shiftDown
            print("[HotkeyManager] polling fn=\(fnDown) shift=\(shiftDown)")
        }
        updateRecordingState()
    }

    private func startPermissionRetryTimer() {
        guard permissionRetryTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.retryEventTapAfterPermissionChange()
        }
        timer.resume()
        permissionRetryTimer = timer
    }

    private func retryEventTapAfterPermissionChange() {
        guard eventTap == nil else {
            permissionRetryTimer?.cancel()
            permissionRetryTimer = nil
            return
        }

        if createEventTap(openSettingsOnFailure: false) {
            pollTimer?.cancel()
            pollTimer = nil
            permissionRetryTimer?.cancel()
            permissionRetryTimer = nil
            print("[HotkeyManager] CGEventTap created after permission granted")
        }
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

    private func requestInputMonitoringPermissionIfNeeded() {
        let granted = CGPreflightListenEventAccess()
        print("[HotkeyManager] Input Monitoring preflight=\(granted) bundle=\(Bundle.main.bundlePath)")
        guard !granted else { return }

        print("[HotkeyManager] Input Monitoring permission requested")
        if !CGRequestListenEventAccess() {
            openInputMonitoringSettingsOnce()
        }
    }

    private func openInputMonitoringSettingsOnce() {
        guard !didOpenInputMonitoringSettings else { return }
        didOpenInputMonitoringSettings = true
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
        print("[HotkeyManager] Input Monitoring settings opened")
    }
}
