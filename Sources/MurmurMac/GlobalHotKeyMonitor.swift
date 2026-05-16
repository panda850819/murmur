import AppKit
import IOKit.hid

/// "Hold Right ⌘ to talk" global trigger.
///
/// Observes a session-level CGEvent tap for the Right Command physical key
/// (keycode 54 — Carbon `RegisterEventHotKey` can't bind a bare modifier or
/// tell left ⌘ from right ⌘, so a flagsChanged tap is the only path). The
/// tap is listen-only: every event is passed through unmodified so Right⌘
/// keeps working as a normal modifier.
///
/// macOS-only and deliberately outside `MurmurCore`: a CGEvent tap is an
/// input source (peer of the SwiftUI Button), not part of the unit-tested
/// record → transcribe → paste flow that lives behind protocol seams in the
/// shared library.
///
/// Interaction model (v0.1, hold-to-talk):
/// - Right⌘ down  → `onPress` (start recording)
/// - Right⌘ up    → `onRelease(cancelled:)`
///     - `cancelled == true` when another key was pressed during the hold
///       (a real Right⌘+key chord) or the hold was shorter than `minHold`
///       (accidental brush) → caller aborts without transcribing.
///     - `cancelled == false` → caller stops, transcribes, pastes.
@MainActor
final class GlobalHotKeyMonitor {
    private static let rightCommandKeyCode: Int64 = 54
    private static let minHold: TimeInterval = 0.18

    var onPress: (() -> Void)?
    var onRelease: ((_ cancelled: Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var runLoopSource: CFRunLoopSource?
    /// The +1-retained `self` handed to the C callback via `refcon`. Released
    /// in `stop()` to balance `passRetained` (prevents the dangling-pointer
    /// crash if the monitor outlives nothing / is torn down while the tap is
    /// still draining its run-loop source).
    private var retainedSelf: UnsafeMutableRawPointer?
    /// Read from the tap's delivery thread (in `reenable()`) to revive a tap
    /// the system disabled. Written only on the main actor in start/stop.
    private nonisolated(unsafe) var portForReenable: CFMachPort?

    private var active = false
    private var otherKeyDuringHold = false
    private var pressedAt: TimeInterval = 0

    /// Whether the process may observe global keyboard input. This is
    /// **Input Monitoring** (`kTCCServiceListenEvent`) — a *different* TCC
    /// permission from Accessibility. Without it a listen-only keyboard tap
    /// is silently restricted to the creating app's own events (the hotkey
    /// then only fires while Murmur is frontmost). Passing `prompt: true`
    /// surfaces the system dialog and adds Murmur to the Input Monitoring
    /// list; the grant only takes effect after the app is relaunched.
    static func inputMonitoringTrusted(prompt: Bool) -> Bool {
        let granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            == kIOHIDAccessTypeGranted
        if !granted, prompt {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        return granted
    }

    /// Installs the tap. Returns `false` if it could not be created. Note a
    /// listen-only tap is created even WITHOUT Input Monitoring — it just
    /// won't see other apps' events — so a `true` here is necessary but not
    /// sufficient; gate on `inputMonitoringTrusted()` for the real signal.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let opaqueSelf = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalHotKeyMonitor>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                // The system disables a tap on user-switch / screen-lock /
                // (defensively) timeout. Without re-enabling here the hotkey
                // silently dies until an app restart — exactly the kind of
                // daily-dogfood reliability hole v0.1 must not have.
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    monitor.reenable()
                } else {
                    monitor.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: opaqueSelf
        ) else {
            // tapCreate failed — release the retain we just took.
            Unmanaged<GlobalHotKeyMonitor>.fromOpaque(opaqueSelf).release()
            return false
        }

        let runLoop = CFRunLoopGetCurrent()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoop = runLoop
        self.runLoopSource = source
        self.retainedSelf = opaqueSelf
        self.portForReenable = tap
        return true
    }

    func stop() {
        if let runLoopSource, let runLoop {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        portForReenable = nil
        tap = nil
        runLoop = nil
        runLoopSource = nil
        if let retainedSelf {
            Unmanaged<GlobalHotKeyMonitor>.fromOpaque(retainedSelf).release()
            self.retainedSelf = nil
        }
    }

    /// Runs on the tap's delivery thread. Safe: only touches the CF port,
    /// which CoreGraphics permits re-enabling from the callback thread.
    nonisolated private func reenable() {
        if let portForReenable {
            CGEvent.tapEnable(tap: portForReenable, enable: true)
        }
    }

    // Runs on the tap's delivery thread. Read the event, then hop to the
    // main actor for state mutation + callbacks.
    nonisolated private func handle(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let commandDown = event.flags.contains(.maskCommand)
        DispatchQueue.main.async { [weak self] in
            self?.process(type: type, keyCode: keyCode, commandDown: commandDown)
        }
    }

    private func process(type: CGEventType, keyCode: Int64, commandDown: Bool) {
        switch type {
        case .keyDown where active:
            otherKeyDuringHold = true

        case .flagsChanged where keyCode == Self.rightCommandKeyCode:
            if commandDown, !active {
                active = true
                otherKeyDuringHold = false
                pressedAt = ProcessInfo.processInfo.systemUptime
                onPress?()
            } else if !commandDown, active {
                active = false
                let tooShort = ProcessInfo.processInfo.systemUptime
                    - pressedAt < Self.minHold
                onRelease?(otherKeyDuringHold || tooShort)
            }

        default:
            break
        }
    }
}
