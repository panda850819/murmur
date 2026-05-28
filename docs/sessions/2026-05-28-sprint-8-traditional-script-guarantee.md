# Sprint 8 — Traditional-script guarantee — 2026-05-28

## What

`/sprint` (no topic). Session-start sync locked the topic to the Sprint 7
follow-up: **中文數字/時間 + 繁體 script 保證**. Grill converged the un-derivable
fork to three sub-goals; Panda chose **(3) Traditional-script guarantee** — make
transcription output always Traditional, OpenCC simplified→traditional as the
named lever; numerals (五點半→5.5) deliberately out of scope.

Deliverable: a script-normalization pass on the transcription output path so
that when WhisperKit renders Mandarin in Simplified glyphs (the `small` model
emits 点/开/会/饭, per Sprint 7), Murmur still pastes Traditional.

## Decisions

- **ICU `StringTransform("Hans-Hant")`, not OpenCC.** Library-first probe showed
  the platform ICU transform does char-level S→T and is context-aware on
  one-to-many ambiguities (干杯→乾杯, 面条→麵條, 皇后 stays 皇后). OpenCC's
  phrase-level (s2twp) would add a dependency + dictionary data AND over-reach
  into vocabulary the speaker actually said (信息→訊息). The failure is glyph
  drift, not vocabulary, so char-level is the right scope.
- **Gate on detected language.** (Added iter 2 — see review.) The transcriber
  runs `detectLanguage:true`, so it also emits ja/ko. `normalize(_:language:)`
  only converts when the detected language is `zh`; other languages pass through.

## How (sprint progression)

- **Stage 0 probe**: green (Inbox/ absent — murmur uses docs/, inlined prep).
- **Stage 1 dojo**: read WER.swift / Transcriber.swift / baseline.json + Sprint 7
  pitfall. Found WER scorer has no numeral/script normalization; transcriber has
  no language pin (Sprint 7 already proved pin is pure regression).
- **Stage 2 grill**: fork → Panda chose (3). Library-first probe disproved the
  named OpenCC lever in favor of built-in ICU (verified idempotency + ASCII/
  numeral safety with a throwaway swift script before committing).
- **Stage 3 execute (iter 1)**: `ScriptNormalizer.toTraditional` + single seam in
  `WhisperKitTranscriber.transcribe()`. 4 unit tests + eval delta +0.0000.
- **Stage 4 review (iter 1)**: cold review (decorrelated context) + Codex
  cross-check **both independently flagged a P1**: the transform ran on ALL
  output regardless of detected language → Japanese `東京で会議をします` →
  `東京で會議をします`, corrupting valid Japanese kanji. Confirmation-bias miss
  (I scoped to "user speaks Chinese" and forgot the transcriber is
  language-agnostic).
- **Stage 3 execute (iter 2)**: gated the conversion on `language == "zh"`,
  extracted the gate into a pure `normalize(_:language:)` so the
  Japanese-preservation case is testable without a model. Locked in the verified
  ambiguous-char behavior with tests.
- **Stage 4 review (iter 2)**: clean. Codex re-review: "P1 resolved", all files
  clean. 8/8 unit tests, eval delta +0.0000.

## Verification

- **Unit tests are the proof the safety net fires** — the eval is a no-op on the
  current fixtures (`base` already emits Traditional), so 8 deterministic tests
  carry the proof: simplified→traditional fires, Japanese preserved, ASCII/
  numerals untouched, idempotent.
- **Eval proves no regression** — delta +0.0000 over 12 clips, per-clip identical
  to baseline. zh-short-06 (五點半→5.5) stays 0.6, as scoped.
- **Integration proven via eval** — eval runs the real `WhisperKitTranscriber`
  path, so the per-result language gating is exercised end-to-end, not just at
  the unit level.

## Terminal state: SHIPPED

No baseline change (delta 0). Numeral/time handling (五點半→5.5) remains a scoped
follow-up, untouched by this sprint per Panda's fork choice.

## See Also

- `docs/learnings/pitfalls/2026-05-28-script-normalization-must-gate-on-detected-language.md`
- `docs/learnings/pitfalls/2026-05-28-zh-residual-wer-is-numeral-and-script-not-language-detection.md` (Sprint 7 — what surfaced this)
- `docs/sessions/2026-05-28-sprint-7-bug1-diagnosis.md`
