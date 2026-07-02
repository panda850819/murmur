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
/// Interaction model (M3a, hold-to-talk, Typeless hotkey map):
/// - Right⌘ down  → `onPress` (start recording)
/// - Right⇧ held with Right⌘ (either order) → mode = 翻譯 translate
/// - `/` pressed during the hold → mode = 詢問 ask (the keystroke is
///   swallowed — it is the chord, not input for the focused app; this is why
///   the tap is `.defaultTap`, not `.listenOnly`)
/// - Right⌘ up    → `onRelease(cancelled:mode:)`
///     - `cancelled == true` when another key (not `/`) was pressed during
///       the hold (a real Right⌘+key chord) or the hold was shorter than
///       `minHold` (accidental brush) → caller aborts without transcribing.
///     - `cancelled == false` → caller stops, transcribes, runs the mode flow.
@MainActor
final class GlobalHotKeyMonitor: HotKeyMonitoring {
    private static let rightCommandKeyCode: Int64 = 54
    private static let slashKeyCode: Int64 = 44 // kVK_ANSI_Slash
    /// `NX_DEVICERSHIFTKEYMASK` — right Shift physically down (same
    /// side-specific device-flag family as the Right⌘ one below).
    private static let rightShiftDeviceFlag: UInt64 = 0x04
    /// `NX_DEVICERCMDKEYMASK` (IOLLEvent.h) — set iff the *right* Command key
    /// is physically down. The aggregate `.maskCommand` is true if *either*
    /// ⌘ is down, so it can't tell right-⌘ release from left-⌘ still-held
    /// (→ `active` would never clear, recording stuck). This side-specific
    /// device flag is the correct signal.
    private static let rightCommandDeviceFlag: UInt64 = 0x10
    private static let minHold: TimeInterval = 0.18

    var onPress: (() -> Void)?
    var onRelease: ((_ cancelled: Bool, _ mode: DictationMode) -> Void)?

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

    /// Pairs a swallowed `/` keyDown with its keyUp (so the up is eaten even
    /// if Right⌘ was released in between — an orphan keyUp confuses apps).
    /// The down itself needs no held state: the keyDown event carries the
    /// current modifier flags, so the verdict reads Right⌘ off the very event
    /// it gates — no missed-flagsChanged hazard can wedge it. Lock-guarded
    /// because it lives on the tap thread while `stop()` resets it from main.
    private let slashDownBox = OSAllocatedUnfairLock(initialState: false)

    private var active = false
    private var otherKeyDuringHold = false
    private var mode: DictationMode = .dictate
    private var pressedAt: TimeInterval = 0

    /// Installs the tap. Returns `false` if it could not be created. An
    /// ACTIVE (`.defaultTap`) keyboard tap requires Accessibility trust —
    /// `tapCreate` returns nil without it — so a `false` here points at the
    /// Accessibility grant, not Input Monitoring; `HotKeyBridge` attributes
    /// it accordingly.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        // keyUp is observed only to swallow the `/` chord's release in ask
        // mode; everything else ignores it.
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let opaqueSelf = Unmanaged.passRetained(self).toOpaque()

        // `.defaultTap` (not `.listenOnly`) so the `/`-during-hold chord can
        // be swallowed instead of reaching the focused app as ⌘/ (which many
        // editors bind to toggle-comment). Every other event is passed
        // through unmodified, same as before.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
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
                    return Unmanaged.passUnretained(event)
                }
                let swallow = monitor.handle(type: type, event: event)
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: opaqueSelf
        ) else {
            // tapCreate failed — release the retain we just took.
            Unmanaged<GlobalHotKeyMonitor>.fromOpaque(opaqueSelf).release()
            return false
        }

        // The tap gets its own thread + run loop. A `.defaultTap` is
        // SYNCHRONOUS — WindowServer holds every keyboard event in the
        // session until this callback returns — so parking it on the main
        // run loop would turn any Murmur main-thread hitch (SwiftUI layout,
        // an AX call) into system-wide typing latency. The callback itself
        // stays trivially cheap: read flags, one lock, dispatch to main.
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoopBox = OSAllocatedUnfairLock<CFRunLoop?>(initialState: nil)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            let runLoop = CFRunLoopGetCurrent()
            runLoopBox.withLock { $0 = runLoop }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "murmur.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait() // bounded: the thread signals before entering its loop
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoop = runLoopBox.withLock { $0 }
        self.runLoopSource = source
        self.retainedSelf = opaqueSelf
        portBox.withLock { $0 = tap }
        return true
    }

    func stop() {
        if let runLoopSource, let runLoop {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
            CFRunLoopStop(runLoop) // lets the tap thread exit its CFRunLoopRun
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        portBox.withLock { $0 = nil }
        slashDownBox.withLock { $0 = false } // never carry a half-swallowed `/` across restart
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

    // Runs on the tap's delivery thread. Read the event, decide the swallow
    // verdict synchronously (the `/` chord must not reach the focused app),
    // then hop to the main actor for state mutation + callbacks. Returns
    // `true` iff the event should be deleted.
    nonisolated private func handle(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let rightCommandDown =
            (event.flags.rawValue & Self.rightCommandDeviceFlag) != 0
        let rightShiftDown =
            (event.flags.rawValue & Self.rightShiftDeviceFlag) != 0

        let swallow = slashDownBox.withLock { (slashDown: inout Bool) -> Bool in
            if type == .keyDown, keyCode == Self.slashKeyCode, rightCommandDown {
                slashDown = true
                return true
            }
            if type == .keyUp, keyCode == Self.slashKeyCode, slashDown {
                slashDown = false
                return true
            }
            return false
        }

        DispatchQueue.main.async { [weak self] in
            self?.process(
                type: type,
                keyCode: keyCode,
                rightCommandDown: rightCommandDown,
                rightShiftDown: rightShiftDown,
                swallowed: swallow
            )
        }
        return swallow
    }

    private func process(
        type: CGEventType,
        keyCode: Int64,
        rightCommandDown: Bool,
        rightShiftDown: Bool,
        swallowed: Bool
    ) {
        switch type {
        case .keyDown where active:
            if swallowed, keyCode == Self.slashKeyCode {
                // The 詢問 chord — upgrades the hold, never cancels it.
                mode = .ask
            } else {
                otherKeyDuringHold = true
            }

        case .flagsChanged where keyCode == Self.rightCommandKeyCode:
            if rightCommandDown, !active {
                active = true
                otherKeyDuringHold = false
                mode = rightShiftDown ? .translate : .dictate
                pressedAt = ProcessInfo.processInfo.systemUptime
                onPress?()
            } else if !rightCommandDown, active {
                active = false
                let tooShort = ProcessInfo.processInfo.systemUptime
                    - pressedAt < Self.minHold
                onRelease?(otherKeyDuringHold || tooShort, mode)
            }

        case .flagsChanged where active && rightShiftDown && mode == .dictate:
            // Right⇧ joined the hold after Right⌘ — upgrade to 翻譯. `.ask`
            // is not downgraded: an explicit `/` outranks the shift flag.
            mode = .translate

        default:
            break
        }
    }
}
