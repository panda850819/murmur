---
date: 2026-05-28
type: pitfall
tags: [whisperkit, transcription, decoding-prompt, prompt-leakage, numerals, architecture, dictation]
sprint: murmur-sprint-9-numeral-decode-prompt
---

# A WhisperKit conditioning prompt fixes numeral WER but leaks — wrong layer for a dictation tool

## What was tried

Bug: 「五點半開會」transcribes as 「5.5開會」 (Whisper numeral-normalizes 五點半 to
"5.5", losing 半 — see the Sprint 7 pitfall). Sprint 9 attempted a decode-side fix:
set `DecodingOptions.promptTokens` to a fixed Chinese conditioning prompt biasing
spelled-out numerals.

The WER result was excellent and surprised the prior Sprint-7 prediction that any
Chinese decode-bias wrecks English:

```
prompt =  我們五點半開會，三點交報告。我把 code push 上去之後再 update。
                          zh-short  zh-long  en     overall
  baseline (no prompt)    0.121     0.091    0.16   0.113
  + prompt (iter 2)       0.030     0.061    0.08   0.0565   (-50%)
```

- `五點半開會` → 「五點半開會」 (fixed), `三點` → 「三點」 (fixed).
- English IMPROVED (0.16→0.08), not wrecked. zh/en code-switching held (after adding
  a code-switching exemplar to the prompt; a pure-Chinese prompt regressed it).

## Why it was rejected anyway (the real defect)

**Prompt leakage.** A Whisper conditioning prompt is prepended to the decoder prefill
and is documented to be emitted verbatim on silence / weak / non-matching audio.
Empirically reproduced on this `base` model:

```
silent.wav (pure silence)   → "[BLANK_AUDIO]"         (suppressed — OK-ish)
quiet.wav  (near-silent)    → "上去之後再 update。"    ← prompt fragment LEAKED
```

Murmur is a push-to-talk tool that **auto-pastes** the result into the foreground app.
A user who holds the key and says nothing / half a word gets prompt garbage pasted into
their editor / Slack / terminal. That is a P0 for an auto-paste tool. Cold review and
Codex flagged it independently; the empirical test confirmed it.

The 12-clip eval set is all valid speech — it has **no silence / non-speech fixture**, so
the eval passed (−50% WER) while completely missing the P0. (Same shape as every other
"eval green, real-world broken" gap: the fixtures didn't cover the failure mode.)

## Root cause — wrong layer

A conditioning prompt fixes formatting at **decode time**, where it cannot be applied
safely: it biases every language, it is overfit-prone, and it leaks. Measured against a
standard dictation product (Typeless / Wispr Flow / Superwhisper), numeral/format quality
is not done this way. The standard pipeline is:

```
VAD / no-speech gate  →  ASR (Whisper, raw)  →  post-processing cleanup layer
  never paste on silence    raw transcript        punctuation / numerals / format
  (table stakes)                                  (deterministic or small LLM, no leak)
```

The numeral fix belongs in a **post-processing layer**, not the decoder. Silence safety
belongs in a **VAD / no-speech gate**, which is table stakes regardless of numerals.

## Decision (Sprint 9)

- Decode-prompt approach **rejected**. No code shipped; baseline restored to 0.1129.
- The −50% WER number is real but unshippable: it rides on a leak-prone mechanism.
- Correct roadmap (two independent, separately-scoped pieces):
  1. VAD / no-speech gate — never auto-paste on silence (also fixes pasting `[BLANK_AUDIO]`).
  2. Post-processing cleanup layer — numerals (五點半), punctuation, format. No decode change.

## Removal trigger

None — architectural conclusion. If a future Whisper/WhisperKit build exposes a
leak-free conditioning mechanism (e.g. guaranteed no prompt echo on non-speech),
re-evaluate; otherwise keep numeral/format work in post-processing.

## Origin

- Sprint 9 (`docs/sessions/2026-05-28-sprint-9-numeral-decode-prompt-paused.md`), 2026-05-28.
- Follows Sprint 7 (`docs/learnings/pitfalls/2026-05-28-zh-residual-wer-is-numeral-and-script-not-language-detection.md`) which first identified 五點半→5.5 as the residual.
