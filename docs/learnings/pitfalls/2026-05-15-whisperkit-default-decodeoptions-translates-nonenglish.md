---
date: 2026-05-15
type: pitfall
tags: [whisperkit, transcription, decodeoptions, language-detection]
sprint: murmur-sprint-4-transcribe
---

# WhisperKit default DecodingOptions silently "translates" non-English speech to English

## Symptom

`WhisperKit.transcribe(audioPath:)` called with no `decodeOptions` (i.e.
`decodeOptions: nil` → WhisperKit's `DecodingOptions()` default) transcribes
Chinese (or any non-English) speech as an **English translation**, not the
spoken language. Observed: spoke 「你好，我今天想要來測試中文，是不是對的？」,
got `"Okay, let's test it."`.

## Root cause

`DecodingOptions` defaults (WhisperKit 1.0.0, `Core/Configurations.swift:155`):

```
task: DecodingTask = .transcribe          // NOT the cause — already transcribe
language: String? = nil
usePrefillPrompt: Bool = true
detectLanguage: Bool? = nil
// in init body:
self.detectLanguage = detectLanguage ?? !usePrefillPrompt
```

With `detectLanguage == nil` and `usePrefillPrompt == true`:
`detectLanguage` resolves to `!true == false`. So: no language given, language
detection **off**, prefill prompt **on**. WhisperKit prefills the decoder with
the English language token by default → the multilingual model decodes the
audio as if it were English, which for non-English speech produces an
English-translation-like output. `task` is already `.transcribe`; changing it
does nothing. The lever is `detectLanguage`, not `task`.

## Fix

Pass explicit options; turn language detection on:

```swift
let options = DecodingOptions(task: .transcribe, detectLanguage: true)
let results = try await kit.transcribe(audioPath: wavURL.path, decodeOptions: options)
```

`detectLanguage: true` runs WhisperKit's language-detection pass per
recording, so it transcribes in whatever language was actually spoken
(handles mixed Chinese/English dictation). Leave `language: nil` so detection
drives it; only hard-pin `language:` if you want to force one language.

## Why it slips past code review + CI

The model can't run in `swift test` / CI (≈140 MB download + Core ML
inference), so the only place this surfaces is manual smoke. Code review sees
`kit.transcribe(audioPath:)` and reads it as obviously correct — the defect
lives entirely in a third-party default, not in the diff. **Manual smoke with
actual non-English speech is the only gate that catches it.** Caught here at
sprint Stage 5 ship-gate smoke, fixed in iteration 2.

Update (Sprint 6, 2026-05-28): the WER eval harness (`scripts/eval.sh` +
human-recorded fixtures) is now a second, automated gate. The v0.1 baseline
encodes the Bug #1 zone (zh-short-06 「五點半開會」 at WER 0.60), so a later
change that worsens short-zh detection fails the regression gate without a
human re-listening. "Only gate" held until Sprint 6; it no longer does. The
harness still needs real recorded speech, so it complements manual smoke
rather than removing the need for human fixtures.

## Removal trigger

None — this is a permanent API-usage requirement, not a workaround. If
WhisperKit changes the `detectLanguage` default to `true`, the explicit option
becomes redundant but harmless; keep it as intent documentation.

## Origin

- Sprint 4 (`docs/sessions/2026-05-15-sprint-4-transcribe.md`), manual smoke
  iteration 2, 2026-05-15.
