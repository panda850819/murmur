import Foundation
import WhisperKit

/// Murmur shared core. Voice-to-text logic shared between macOS and (future) iOS targets.
///
/// Sprint 2 scaffold: WhisperKit is imported to verify the dependency resolves and
/// links cleanly. No transcription logic yet — that arrives in Sprint 3+.
public enum Murmur {
    /// Library version, surfaced for the app's "About" dialog later.
    public static let version = "0.0.1"

    /// Confirms the WhisperKit module loaded. Returns the WhisperKit class name as a
    /// trivial check that the symbol is reachable at runtime, not just at compile time.
    public static func whisperKitReachable() -> String {
        String(describing: WhisperKit.self)
    }
}
