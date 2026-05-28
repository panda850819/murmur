---
date: 2026-05-28
type: pitfall
tags: [whisperkit, transcription, unicode, simplified-traditional, icu, language-detection, cold-review]
sprint: murmur-sprint-8-traditional-script-guarantee
---

# A script/locale normalization on ASR output must be gated on the detected language

## Symptom

Murmur transcribes with `DecodingOptions(detectLanguage: true)` — it emits
whatever language was spoken (zh / ja / ko / en / ...). To guarantee Traditional
Chinese output, a Simplified→Traditional pass was added to the output path:

```swift
return ScriptNormalizer.toTraditional(text)   // iter 1 — WRONG
```

`Hans-Hant` rewrites **every** Han character regardless of source language. So a
Japanese dictation `東京で会議をします` came out `東京で會議をします` — valid
Japanese kanji silently corrupted into Sino-Japanese hybrid glyphs, on the path
every paste goes through.

## Root cause

Applying a *language-specific* text normalization unconditionally to the output
of a *language-agnostic* recognizer. The mental model was "the user speaks
Traditional Chinese, fix the simplified glyphs" — but the recognizer is not
pinned to Chinese (and pinning it is a known regression, see Sprint 7). Han
characters are shared across zh/ja/ko; `Hans-Hant` has no way to know the source
language, so it mangles non-Chinese CJK.

## Fix

Gate the conversion on the per-result detected language; extract the gate into a
pure function so the preservation case is testable without loading a model:

```swift
public static func normalize(_ text: String, language: String) -> String {
    language == "zh" ? toTraditional(text) : text
}
// transcriber:
results.map { ScriptNormalizer.normalize($0.text, language: $0.language) }
```

`WhisperKit.TranscriptionResult` carries `.language` (the detected code).
Regression guard: `normalize("東京で会議をします", language: "ja")` must be a no-op.

## Secondary finding — ICU beats OpenCC for *script-drift* correction

The original lever was OpenCC. A library-first probe showed Apple's built-in ICU
`StringTransform("Hans-Hant")` is the better fit for THIS problem:

- char-level (matches the failure: glyph drift, not Mainland vocabulary),
- context-aware on one-to-many ambiguities — `干杯→乾杯`, `面条→麵條`,
  `皇后` stays `皇后` (empress, not `皇後`), verified empirically,
- zero dependency, idempotent, leaves ASCII/numerals untouched.

OpenCC's phrase-level (s2twp) would add a dictionary dependency AND over-reach
into vocabulary the speaker actually said (`信息→訊息`). For glyph-drift safety,
phrase conversion is the wrong tool.

## How it was caught

Not by the author. Cold review (decorrelated context, no knowledge of intent)
**and** Codex adversarial cross-check **independently** flagged the same P1. The
in-session reviewer (me) had absorbed the "user speaks Chinese" framing and
stopped questioning the input domain — textbook confirmation bias. The eval gate
also missed it: the fixture set has no non-Chinese-CJK clip, so it stayed green.
The unit test that would have caught it (`ja` preservation) didn't exist until
the cold reviewer demanded it.

## Removal trigger

None — this is a correctness invariant. If a future change makes the recognizer
Chinese-only (it won't, by design), the gate becomes redundant but harmless.

## Origin

- Sprint 8 (`docs/sessions/2026-05-28-sprint-8-traditional-script-guarantee.md`).
- Builds on Sprint 7's diagnosis that script drift (not language detection) is
  the residual zh issue: `docs/learnings/pitfalls/2026-05-28-zh-residual-wer-is-numeral-and-script-not-language-detection.md`.
- Reinforces the cold-review-catches-confirmation-bias pattern already in the brain.
