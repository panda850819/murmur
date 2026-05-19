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
- **6b (blocked, human-required)**: record 10–20 Apple-device-native
  clips (iPhone + MacBook mic) + bootstrap baseline. An agent cannot
  produce Panda's voice; BRIEF forbids TTS / reused clips. This is the
  `/goal` halt point.

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

## Ranked proposal for the fixture question

1. **(recommended)** 12 clips, iPhone + MacBook, per kit. ~20 min,
   satisfies BRIEF gate as written.
2. iPhone-only —降規, BRIEF wants both mics; needs explicit Panda OK.
3. Skip fixtures, run 7/8 without an oracle — rejected: directly
   violates DONE WHEN + STOP RULES, repeats the ghost-binary class of
   error (changing transcription with no regression check).

## Findings (6a self-review)

No P0/P1. Declared coverage gap: the transcription path is not
unit-tested (needs model + real fixtures = 6b) — inherent to the split,
not a defect. Scope clean: Transcriber / DictationCoordinator untouched.

## OPEN_QUESTIONS

- Fixture set size/spread is the recommendation, not Panda-confirmed —
  resolve at 6b intake.
