import Foundation

/// Which of the three Typeless-parity behaviors a dictation runs as (M3a).
/// Decided by the hotkey chord at hold time, carried through the release into
/// `DictationCoordinator.toggle(mode:)`:
/// - 口述 dictate: Right ⌘ alone — transcribe → enhance → paste (M1 path).
/// - 翻譯 translate: Right ⇧ + Right ⌘ — transcribe → translate to the
///   target language → paste.
/// - 詢問 ask: `/` pressed while Right ⌘ is held — transcribe the spoken
///   question, answer it (about the current selection, if any) → paste.
public enum DictationMode: Sendable, Equatable {
    case dictate
    case translate
    case ask
}

/// Test seam over "read the selected text in the frontmost app". The concrete
/// implementation (an AX API call) is macOS UI-glue and lives in the app
/// target; ask-mode's flow stays unit-testable with a fake — mirrors
/// `Pasting` / `Recording`.
@MainActor
public protocol SelectionReading: AnyObject {
    /// The selection in the focused UI element, or `nil` when there is none
    /// (or the app doesn't expose one via Accessibility).
    func selectedText() -> String?
}
