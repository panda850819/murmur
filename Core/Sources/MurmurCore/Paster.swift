import Foundation

/// Test seam over "put text into the foreground app". Mirrors `Recording` /
/// `Transcribing`: the coordinator's flow stays unit-testable with a fake
/// instead of touching the real pasteboard / synthesising key events.
///
/// `paste` returns `false` when the OS refused (e.g. Accessibility not
/// granted) so the coordinator can surface an actionable hint instead of
/// silently dropping the transcript.
@MainActor
public protocol Pasting: AnyObject {
    @discardableResult
    func paste(_ text: String) -> Bool
}

/// Compile-safe `Pasting` for platforms without a real implementation (the
/// future iOS target, until it gets a keyboard-extension / share-sheet paste
/// path). Not `#if`-gated on purpose: `DictationCoordinator.makeDefault()`
/// must compile everywhere MurmurCore links. Reports success so the
/// coordinator doesn't surface a spurious "couldn't paste" error.
@MainActor
public final class NoopPaster: Pasting {
    public init() {}
    @discardableResult
    public func paste(_ text: String) -> Bool { true }
}

#if os(macOS)
import AppKit
import ApplicationServices

/// macOS `Pasting`: writes the transcript to the general pasteboard and
/// synthesises ⌘V into whatever app is frontmost. Gated on Accessibility
/// trust — without it `CGEvent.post` is a no-op, so we check first and
/// surface the system prompt rather than appear to "lose" the text.
///
/// Clipboard-clobber is accepted v0.1 behaviour (documented in the sprint
/// OPEN_QUESTIONS); restoring the prior pasteboard is a later refinement.
@MainActor
public final class ClipboardPaster: Pasting {
    public init() {}

    /// `true` if the process is Accessibility-trusted. When not, passing
    /// `prompt: true` surfaces the one-time System Settings dialog.
    @discardableResult
    public func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    @discardableResult
    public func paste(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }

        // Pasteboard write needs no special permission and is the manual
        // fallback if the synthetic keystroke is refused — always do it first.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // prompt:false — a denied check here would otherwise re-open the
        // System Settings dialog after *every* transcription. The app drives
        // the grant non-modally instead (GlobalHotKeyMonitor.start() failing
        // → the "Open Settings / Re-check" UI in MurmurApp).
        guard ensureAccessibilityPermission(prompt: false) else { return false }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }
        let vKey: CGKeyCode = 0x09 // kVK_ANSI_V
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
#endif
