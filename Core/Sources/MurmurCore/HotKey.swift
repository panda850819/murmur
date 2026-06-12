#if os(macOS)
import Foundation
import ApplicationServices
import IOKit.hid

/// Test seam over the global hotkey input source. The concrete
/// implementation (a CGEvent tap) is macOS UI-glue and lives in the app
/// target; this protocol lets `HotKeyBridge`'s serialisation + permission
/// orchestration be unit-tested with a fake — mirrors `Recording` /
/// `Transcribing` / `Pasting`.
@MainActor
public protocol HotKeyMonitoring: AnyObject {
    var onPress: (() -> Void)? { get set }
    /// `mode` is the chord resolved over the whole hold (Right⇧ seen → 翻譯,
    /// `/` seen → 詢問); only meaningful when `cancelled` is false.
    var onRelease: ((_ cancelled: Bool, _ mode: DictationMode) -> Void)? { get set }
    @discardableResult
    func start() -> Bool
    func stop()
}

/// The two macOS TCC permissions this feature needs, behind a seam so the
/// gating logic is testable without touching the real TCC database.
public protocol PermissionProbe {
    /// Accessibility (`kTCCServiceAccessibility`) — post the synthetic ⌘V.
    func accessibilityTrusted(prompt: Bool) -> Bool
    /// Input Monitoring (`kTCCServiceListenEvent`) — observe the global
    /// keyboard tap. A *different* permission from Accessibility: without it
    /// a listen-only tap is silently restricted to this app's own events
    /// (the hotkey then only fires while Murmur is frontmost).
    func inputMonitoringTrusted(prompt: Bool) -> Bool
}

/// Bridges the global hotkey's press/release into the `DictationCoordinator`
/// and owns the permission state the UI renders.
///
/// Press/release are serialised through a single task chain so a fast tap
/// can't run the release's `toggle()` before the press's `toggle()` has
/// finished establishing the recording state.
///
/// On the "unbounded task chain" worry: it is bounded *for this input
/// shape*. Hold-to-talk emits exactly one `onPress` then one `onRelease`
/// per cycle; macOS modifier `flagsChanged` does **not** key-repeat, and the
/// next press cannot arrive before the release. Each task drops its
/// predecessor once `await previous?.value` returns, so chain depth stays
/// ≤2 and fully drains. Cancelling `previous` instead would break the
/// press-before-release ordering this exists to guarantee.
@MainActor
public final class HotKeyBridge: ObservableObject {
    @Published public private(set) var accessibilityGranted = true
    @Published public private(set) var inputMonitoringGranted = true

    public var allPermissionsGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }

    private let monitor: any HotKeyMonitoring
    private let probe: any PermissionProbe
    private var pending: Task<Void, Never>?
    private var attached = false

    public init(monitor: any HotKeyMonitoring, probe: any PermissionProbe) {
        self.monitor = monitor
        self.probe = probe
    }

    public func attach(to dictation: DictationCoordinator) {
        guard !attached else { return }
        attached = true
        monitor.onPress = { [weak self] in
            self?.enqueue { await dictation.toggle() }
        }
        monitor.onRelease = { [weak self] cancelled, mode in
            self?.enqueue {
                if cancelled {
                    await dictation.cancel()
                } else {
                    await dictation.toggle(mode: mode)
                }
            }
        }
        // Prompt for both once here — launch is the right user-initiated
        // moment, not mid-transcription. Both grants only take effect after
        // an app relaunch (the UI says so).
        let imTrusted = probe.inputMonitoringTrusted(prompt: true)
        let axTrusted = probe.accessibilityTrusted(prompt: true)
        let started = monitor.start()
        inputMonitoringGranted = imTrusted && started
        accessibilityGranted = axTrusted
    }

    /// Re-check after the user (says they) granted the permissions. The tap
    /// was likely created while untrusted, so tear it down and recreate —
    /// even then a TCC grant for an event tap usually only takes effect
    /// after an app relaunch, which the UI tells the user.
    public func retry() {
        monitor.stop()
        let started = monitor.start()
        inputMonitoringGranted =
            probe.inputMonitoringTrusted(prompt: false) && started
        accessibilityGranted = probe.accessibilityTrusted(prompt: false)
    }

    private func enqueue(_ action: @escaping () async -> Void) {
        let previous = pending
        pending = Task {
            await previous?.value
            await action()
        }
    }

    /// Test-only: await the in-flight serialised action so a test can
    /// deterministically observe the post-press/release coordinator state.
    func _waitForPending() async {
        await pending?.value
    }
}

/// The single owner of the real TCC checks. Both `ClipboardPaster` (paste =
/// Accessibility) and `HotKeyBridge` (hotkey = Input Monitoring, paste-state
/// mirror = Accessibility) go through this one implementation so the
/// `AXIsProcessTrustedWithOptions` dance isn't reimplemented per call site.
public struct RealPermissionProbe: PermissionProbe {
    public init() {}

    public func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    public func inputMonitoringTrusted(prompt: Bool) -> Bool {
        let granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            == kIOHIDAccessTypeGranted
        if !granted, prompt {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        return granted
    }
}
#endif
