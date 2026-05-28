import Foundation

/// Guarantees Chinese transcription output is Traditional script.
///
/// WhisperKit can render Mandarin in Simplified glyphs (the `small` model
/// emits 点/开/会/饭), which is the wrong script for a Traditional writer.
/// The conversion is a char-level Simplified→Traditional pass via the
/// platform ICU transform. It is context-aware enough to resolve one-to-many
/// ambiguities correctly (干杯→乾杯, 面条→麵條, while 皇后 stays 皇后) and is
/// idempotent on already-Traditional text.
///
/// Char-level, not phrase-level (OpenCC s2twp), is deliberate: the failure is
/// glyph drift, not vocabulary. Phrase conversion would rewrite words the
/// speaker actually said (信息→訊息), which is wrong.
public enum ScriptNormalizer {
    /// Whisper language codes treated as Chinese for script normalization.
    /// Mandarin is `zh`, Cantonese is `yue` — both are written Chinese and a
    /// Traditional writer wants either rendered Traditional. ja/ko/en/etc. are
    /// excluded: `toTraditional` would rewrite their shared Han characters
    /// (Japanese 会議→會議) into corrupt Sino glyphs.
    static let chineseLanguages: Set<String> = ["zh", "yue"]

    /// Script guarantee gated by detected language. Only Chinese output is
    /// normalized; everything else passes through untouched. The transcriber
    /// runs `detectLanguage:true`, so this gate is what keeps non-Chinese safe.
    public static func normalize(_ text: String, language: String) -> String {
        chineseLanguages.contains(language) ? toTraditional(text) : text
    }

    /// Unconditional Simplified→Traditional. Rewrites ANY Han character, so
    /// callers must gate on Chinese-language text (use `normalize(_:language:)`).
    public static func toTraditional(_ s: String) -> String {
        s.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) ?? s
    }
}
