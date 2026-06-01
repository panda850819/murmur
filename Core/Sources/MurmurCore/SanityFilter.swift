import Foundation

/// Rejects garbage in LLM-enhanced output. The enhance step is best-effort: if
/// the model returns emoji, box-drawing art, control characters, or other
/// unexpected scalars, the caller discards the enhanced text and keeps the raw
/// transcript. BRIEF Quality gate #2 — any fixture that trips this is a
/// regression.
///
/// Char-level scalar scan, not a regex: the failure mode is a stray pictograph
/// or control byte, not a vocabulary issue. Plain dictation output (any script,
/// digits, ordinary punctuation, newlines) passes; decorative or control
/// scalars do not.
public enum SanityFilter {
    public static func isClean(_ text: String) -> Bool {
        firstViolation(in: text) == nil
    }

    /// First disallowed scalar, or `nil` if the whole string is clean. Returned
    /// (not just a bool) so callers can log *what* tripped the filter.
    public static func firstViolation(in text: String) -> Unicode.Scalar? {
        text.unicodeScalars.first(where: isDisallowed)
    }

    static func isDisallowed(_ scalar: Unicode.Scalar) -> Bool {
        // Common whitespace is always fine, even though \n/\r/\t are Cc.
        if scalar == "\n" || scalar == "\r" || scalar == "\t" || scalar == " " {
            return false
        }

        switch scalar.properties.generalCategory {
        case .control, .format, .privateUse, .surrogate, .unassigned, .lineSeparator, .paragraphSeparator:
            return true
        default:
            break
        }

        switch scalar.value {
        case 0x2500...0x259F:  // box drawing + block elements
            return true
        case 0x25A0...0x25FF:  // geometric shapes
            return true
        case 0x2600...0x27BF:  // misc symbols + dingbats
            return true
        case 0xFE00...0xFE0F:  // variation selectors (emoji presentation)
            return true
        case 0x1F000...0x1FAFF:  // emoji & supplemental pictographs
            return true
        default:
            break
        }

        // Catch emoji-presentation scalars outside the explicit ranges without
        // nuking ASCII digits/`#`/`*` (which are Emoji=Yes but Presentation=No).
        if scalar.properties.isEmojiPresentation {
            return true
        }

        return false
    }
}
