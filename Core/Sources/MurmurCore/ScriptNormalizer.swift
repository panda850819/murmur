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
    /// Script guarantee gated by detected language. Only Chinese output is
    /// normalized; ja/ko/en/etc. pass through untouched — the transcriber runs
    /// with `detectLanguage:true`, and `toTraditional` would otherwise rewrite
    /// Japanese/Korean kanji (会議→會議) into corrupt Sino glyphs.
    public static func normalize(_ text: String, language: String) -> String {
        language == "zh" ? toTraditional(text) : text
    }

    /// Unconditional Simplified→Traditional. Rewrites ANY Han character, so
    /// callers must gate on Chinese-language text (use `normalize(_:language:)`).
    public static func toTraditional(_ s: String) -> String {
        s.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) ?? s
    }
}
