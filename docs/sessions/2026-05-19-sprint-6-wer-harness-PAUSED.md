---
date: 2026-05-19
type: sprint
state: PAUSED
topic: Sprint 6 — WER eval harness + fixture baseline
branch: feat/sprint6-wer-eval-harness
driver: /goal (unattended, wrapping /sprint)
tags: [sprint, paused, murmur, eval]
---

# Sprint 6 — WER eval harness — 2026-05-19 — PAUSED

## Terminal state: PAUSED (blocked on human input, by design)

Driven by an unattended `/goal` wrapping `/sprint` for v0.1
feature-complete. Sprint 6 splits into:

- **6a (done, unattended-safe)**: WER/CER scoring engine + manifest
  contract + `MurmurEval` runner + recording kit. Committed `cb4a703`
  on `feat/sprint6-wer-eval-harness`. Verified: clean `swift build`,
  7/7 deterministic WER tests, binary runs and fails honestly with no
  fixtures. Not pushed / no PR — PAUSED does not ship.
- **6b (blocked, human-required)**: record 12 clips on Panda's actual
  dictation mic (AirPods Pro, macOS HFP 16 kHz mono) + bootstrap
  baseline. v0.1 = macOS-only and Panda dictates wearing AirPods, so
  the v0.1 fixture environment matches that — baseline must reflect
  reality or Bug #1's WER delta gets polluted by noise-profile
  differences. Other sources (MacBook built-in mic / iPhone) deferred
  to v0.2 sprint (manifest schema already supports them additively via
  the `source` field). An agent cannot produce Panda's voice; BRIEF
  forbids TTS / reused clips. This is the `/goal` halt point.

## Why the whole /goal halts here

DONE WHEN requires `fixture WER 不比前版差`; Sprint 7/8 VERIFY both
compare against the Sprint 6 baseline. No baseline → 7/8 cannot reach a
real SHIPPED, only a faked one. STOP RULES: PAUSED → stop, do not
fake-advance. So 7 and 8 are deliberately untouched.

## Resume (≈20 min, Panda only)

1. Follow `docs/eval/RECORDING-KIT.md` — 12-clip set, biased at the
   Bug #1 zone (short Chinese).
2. Drop wavs in `docs/eval/fixtures/`, write `manifest.json` (copy
   `manifest.example.json`).
3. `scripts/eval.sh --bootstrap-baseline` → writes `baseline.json`.
4. Commit fixtures + manifest + baseline on this branch → Sprint 6 =
   SHIPPED → push + PR.
5. Re-fire the same `/goal`; it resumes Sprint 7 (Bug #1) then Sprint 8,
   each gated by `scripts/eval.sh`.

## Fixture scope for v0.1 (corrected 2026-05-28: AirPods, not MacBook mic)

12 AirPods Pro clips: 6 short zh (Bug #1 zone) + 3 long zh + 3 en.
Originally specced as MacBook built-in mic; corrected at resume time
because Panda's actual daily dictation environment is AirPods Pro.
Baseline must match dogfood reality — measuring on a mic Panda doesn't
use would let Bug #1 WER deltas get washed out by noise-profile
differences across model versions. MacBook-mic / iPhone fixtures are
deferred to v0.2 sprint (manifest `source` field already supports
additive sources without harness change). Skipping fixtures entirely
and running 7/8 without an oracle was rejected: directly violates DONE
WHEN + STOP RULES, repeats the ghost-binary class of error (changing
transcription with no regression check).

## Findings (6a self-review)

No P0/P1. Declared coverage gap: the transcription path is not
unit-tested (needs model + real fixtures = 6b) — inherent to the split,
not a defect. Scope clean: Transcriber / DictationCoordinator untouched.

## OPEN_QUESTIONS

- iPhone fixture set is deferred to v0.2 sprint, not addressed here.
- Clip durations (`-t 5` for short, `-t 8` for long/en) are kit
  defaults; Panda may adjust per actual speech length.
