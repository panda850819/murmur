---
schema_version: 1
date: 2026-06-12
type: sprint
state: SHIPPED
topic: M5 dictation history + silent-audio guard + stats
mode: default (architect + subagent build — first run of the new Stage 3 default)
iteration: 2
tags: [sprint, shipped]
---

# Sprint — M5 history + silent-detect + stats — 2026-06-12

First sprint under the flipped Stage 3 default (pandastack `d4f8f75`, Panda
directive same day): main session = architect (spec / review verdicts / git),
implementation and cold review = subagents.

## Stage progression

| Stage | Status | Output |
|---|---|---|
| 3 execute | subagent, commit b881968 | SilenceDetector + HistoryStore + stats + UI, 35 tests |
| 4 review | cold subagent: 1 P1 + 3 P2 + 2 P3 | fix subagent, commit ded515d |
| 5/6 ship | SHIPPED | PR #10 (stacked on #9), CI green (swift test + xcodebuild) |

## What was built

- `SilenceDetector`: RMS over the recorded WAV before transcribe. `true` only
  for *fully decoded and genuinely quiet* (zero-frame included); unreadable /
  garbage / mid-read failure → `false`, so a real dictation is never silently
  dropped — the transcriber fails loudly instead. Seam: `silenceCheck` closure
  on the coordinator.
- `HistoryStore`: local-only JSON, cap 200 newest-first, CorrectionStore
  persistence pattern, CJK-aware word count (CJK punctuation + fullwidth forms
  are separators). Appended ONLY after the paste reports success.
- Stats footnote derived from kept records, labeled `(last 200)`;
  minutes saved = words/40 − words/150.

## Subagent deviations accepted by the architect

- Degraded translate (raw transcript pasted) DOES append to history — the
  invariant is "history mirrors what landed in the document".
- WAV on disk is Float32 (not 16-bit PCM as spec'd); detector reads via
  `AVAudioFile`, the symmetric path. Spec was wrong, agent was right.

## Review findings (all fixed in ded515d unless noted)

- P1 history appended before/regardless of paste success → append iff pasted.
- P2 CJK punctuation counted as words (~+1/sentence) → separator ranges
  U+3000–303F, U+FF00–FFEF.
- P2 stats read as lifetime but derive from capped 200 → labeled.
- P2 silence fail-closed direction inverted → contract rewritten (see above).
- P3 accepted as-is: stale "WAVWriter symmetry" comments (production audio is
  written by AVAudioRecorder, not WAVWriter — detector still correct); Date
  exact-equality after JSON round-trip in one test (flake-pattern, watch CI).

## OPEN_QUESTIONS

- RMS threshold 0.005 unvalidated against a real muted-mic recording —
  dogfood smoke item (with M3a's real-key smoke).
- History UI shows last 20 of 200; no search/pagination. Fine for dogfood.

## Remaining flows after this sprint

- M4 dictionary + gbrain flywheel — next sprint, the differentiator.
- M2 / M3b iOS — still hardware-gated (Panda's iPhone + signing team).
- M6 distribution + the two 🔴 privacy gates (terms.json at-rest; B' filter
  shipped in #8) — after M4.
