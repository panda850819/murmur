---
date: 2026-05-28
type: pitfall
tags: [whisperkit, transcription, wer, language-detection, numerals, traditional-chinese]
sprint: murmur-sprint-7-bug1-diagnosis
---

# "Bug #1" residual Chinese WER is numeral + script normalization, not language detection

## Symptom (the inherited framing, which was wrong)

Sprint 5/6 carried Bug #1 forward as "Chinese speech → English output —
`detectLanguage:true` misdetects on short clips." The v0.1 eval baseline
showed `zh-short-06`「五點半開會」at WER 0.60, which looked like it confirmed
short-clip language misdetection.

The planned fix was to pin `DecodingOptions(language: "zh")` (Chinese-first).
The eval harness disproved that plan.

## What the harness actually showed

Pinning `language: "zh"` (model `base`):

```
                 zh-short  zh-long   en      overall   script
base + detect    0.121     0.091     0.16    0.113     Traditional
pin language:zh  0.121     0.091     0.52    0.169     en wrecked, zero zh gain
small + detect   0.182     0.106     0.08    0.121     Simplified (en fixed)
```

- zh-short was **identical** (0.121) with detect vs zh-pin. Language detection
  was already picking Chinese correctly — pinning changed nothing for zh.
- English collapsed under the pin: `en-03` "we should ship the beta..." →
  「我們就把這個字寫到達到這個字」(forced-zh garbage), `en-01` →
  「《Skate all the release review for a next Tuesday》」. Pure regression.

The residual zh errors, from the actual hypotheses:

- `zh-short-06`「五點半開會」→「**5.5開會**」 — Whisper numeral-normalizes 五點半
  to Arabic "5.5", losing 半 (half). This is the one genuinely broken paste.
- `zh-long-01`「三點」→「3點」 — same numeral normalization, but acceptable.
- `zh-short-04`「訊息傳出去了」→「訊息傳出去的」 — 了/的 acoustic homophone, minor.

## Root cause

The residual short-Chinese WER is **text-normalization + minor acoustics on the
`base` model**, not language detection:

1. **Arabic-numeral normalization** — Whisper emits 「3點」for 「三點」and mangled
   「五點半」into 「5.5」. The 半→".5" loss is a real decode error; you cannot
   recover 半 from "5.5" by post-processing digits.
2. **Acoustic homophones** (了/的) — model-size territory, marginal.

`base` outputs **Traditional** Chinese (correct for this user). `small` fixes
English and keeps 半 (「5点半」), but emits **Simplified** (点/开/会/饭) → wrong
script for a Traditional writer, and zh WER gets *worse*. So a model bump is not
a free win for a Traditional-Chinese-first tool.

## Decision (Sprint 7)

- Keep `base` + `detectLanguage:true`. No code change shipped — every variant
  tried was a measured regression or no-op.
- `language:"zh"` pin **rejected** with evidence (trades English for zero zh gain).
- The real, narrow residual (Chinese numeral/time mangling, e.g. 五點半→5.5) is
  logged as a scoped follow-up, not crammed into this sprint.

## Why this slipped past the inherited framing

The brain/session framing ("language misdetection on short clips") was the
Sprint 4 symptom, already fixed by `detectLanguage:true`. The baseline number
(zh-short-06 = 0.60) was read as confirming the old framing. Only running the
harness with hypotheses printed (`ref=[...] hyp=[...]`) exposed that the error
was 五點半→5.5, a normalization artifact — not English leakage. **Print the
hypotheses, don't trust the WER number to tell you the failure class.**

## Follow-up (scoped, not yet opened)

Chinese numeral/time handling + Traditional-script guarantee. Candidate levers:
WER-scorer numeral normalization (3點≡三點; standard in ASR eval), a decode
prompt biasing spelled-out numbers, or `small`+OpenCC simplified→traditional.
Each is a product decision; deserves its own intake, not a tail-end patch.

## Removal trigger

None — this is a diagnosis record. Supersede only if a future model/option
makes the numeral mangling disappear (re-measure with the harness to confirm).

## Origin

- Sprint 7 (`docs/sessions/2026-05-28-sprint-7-bug1-diagnosis.md`), 2026-05-28.
- Builds on `docs/learnings/pitfalls/2026-05-15-whisperkit-default-decodeoptions-translates-nonenglish.md`.
</content>
</invoke>
