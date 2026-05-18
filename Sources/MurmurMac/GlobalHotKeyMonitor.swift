import AppKit
import os
import MurmurCore

/// "Hold Right ⌘ to talk" global trigger — the macOS concrete behind
/// `MurmurCore.HotKeyMonitoring`.
///
/// Observes a session-level CGEvent tap for the Right Command physical key
/// (keycode 54 — Carbon `RegisterEventHotKey` can't bind a bare modifier or
/// tell left ⌘ from right ⌘, so a flagsChanged tap is the only path). The
/// tap is listen-only: every event is passed through unmodified so Right⌘
/// keeps working as a normal modifier.
///
/// macOS-only and deliberately outside `MurmurCore`: a CGEvent tap is an
/// input source (peer of the SwiftUI Button), not part of the unit-tested
/// flow. The serialisation + permission orchestration that *is* worth testing
/// lives in `MurmurCore.HotKeyBridge` behind this protocol seam.
///
/// Interaction model (v0.1, hold-to-talk):
/// - Right⌘ down  → `onPress` (start recording)
/// - Right⌘ up    → `onRelease(cancelled:)`
///     - `cancelled == true` when another key was pressed during the hold
///       (a real Right⌘+key chord) or the hold was shorter than `minHold`
///       (accidental brush) → caller aborts without transcribing.
///     - `cancelled == false` → caller stops, transcribes, pastes.
@MainActor
final class GlobalHotKeyMonitor: HotKeyMonitoring {
    private static let rightCommandKeyCode: Int64 = 54
    /// `NX_DEVICERCMDKEYMASK` (IOLLEvent.h) — set iff the *right* Command key
    /// is physically down. The aggregate `.maskCommand` is true if *either*
    /// ⌘ is down, so it can't tell right-⌘ release from left-⌘ still-held
    /// (→ `active` would never clear, recording stuck). This side-specific
    /// device flag is the correct signal.
    private static let rightCommandDeviceFlag: UInt64 = 0x10
    private static let minHold: TimeInterval = 0.18

    var onPress: (() -> Void)?
    var onRelease: ((_ cancelled: Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var runLoopSource: CFRunLoopSource?
    /// The +1-retained `self` handed to the C callback via `refcon`. Released
    /// in `stop()` to balance `passRetained` (prevents the dangling-pointer
    /// crash if the monitor is torn down while the tap is still draining its
    /// run-loop source).
    private var retainedSelf: UnsafeMutableRawPointer?
    /// The tap port, read from the tap's delivery thread in `reenable()` and
    /// written on the main actor in start/stop. Lock-guarded rather than
    /// `nonisolated(unsafe)` so the cross-thread access is actually
    /// synchronised, not just silenced.
    private let portBox = OSAllocatedUnfairLock<CFMachPort?>(initialState: nil)

    private var active = false
    private var otherKeyDuringHold = false
    private var pressedAt: TimeInterval = 0

    /// Installs the tap. Returns `false` if it could not be created. Note a
    /// listen-only tap is created even WITHOUT Input Monitoring — it just
    /// won't see other apps' events — so a `true` here is necessary but not
    /// sufficient; `HotKeyBridge` gates on `PermissionProbe` for the real
    /// signal.
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
        portBox.withLock { $0 = tap }
        return true
    }

    func stop() {
        if let runLoopSource, let runLoop {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        portBox.withLock { $0 = nil }
        tap = nil
        runLoop = nil
        runLoopSource = nil
        if let retainedSelf {
            Unmanaged<GlobalHotKeyMonitor>.fromOpaque(retainedSelf).release()
            self.retainedSelf = nil
        }
    }

    /// Runs on the tap's delivery thread. Re-enabling a tap from inside its
    /// own callback is the established pattern (Hammerspoon et al.); Apple's
    /// docs are silent on it rather than forbidding it. The lock makes the
    /// port read race-free against a concurrent `stop()`.
    nonisolated private func reenable() {
        portBox.withLock { port in
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
        }
    }

    // Runs on the tap's delivery thread. Read the event, then hop to the
    // main actor for state mutation + callbacks.
    nonisolated private func handle(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let rightCommandDown =
            (event.flags.rawValue & Self.rightCommandDeviceFlag) != 0
        DispatchQueue.main.async { [weak self] in
            self?.process(type: type, keyCode: keyCode, rightCommandDown: rightCommandDown)
        }
    }

    private func process(type: CGEventType, keyCode: Int64, rightCommandDown: Bool) {
        switch type {
        case .keyDown where active:
            otherKeyDuringHold = true

        case .flagsChanged where keyCode == Self.rightCommandKeyCode:
            if rightCommandDown, !active {
                active = true
                otherKeyDuringHold = false
                pressedAt = ProcessInfo.processInfo.systemUptime
                onPress?()
            } else if !rightCommandDown, active {
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
