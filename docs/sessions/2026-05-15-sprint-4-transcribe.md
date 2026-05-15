---
date: 2026-05-15
type: sprint
state: SHIPPED
topic: murmur-sprint-4-transcribe
mode: default
iteration: 2
persona: pandastack:eng-lead
tags: [sprint, shipped, whisperkit, transcribe, model-load]
---

# Sprint — murmur-sprint-4-transcribe — 2026-05-15

Closes the `record → text` half of the v0.1 "one button one flow": load
WhisperKit `base` on first use, transcribe the WAV produced by Sprint 3,
show the transcript in the UI. Scope locked at `/sprint 4` intake +
3-question grill.

## Capability probe

```
[1] AGENTS substrate : ok  (~/.agents/AGENTS.md, 237 lines)
[2] vault root       : ok  (Inbox/ + docs/)
[3] lib/ files       : ok  (capability-probe, gate-contract, skill-decision-tree, push-once, escape-hatch)
[4] persona skills   : ok  (eng-lead + 8)
[5] cli tools        : ok  (swift 6.2.4, xcodegen 2.45.4, Xcode 26.3)
[6] write paths      : ok
→ 6/6 green
```

## Stage progression

| Stage | Status | Output |
|---|---|---|
| 0 capability probe | ok | 6/6 green |
| 1 dojo | done | `docs/briefs/2026-05-15-sprint-4-transcribe-dojo.md` |
| 2 grill (lite) | done | 3 Qs (existence / scope / reversibility), all recommended option accepted first reply, 0 push-once, 0 escape-hatch |
| 3 execute | done | iter 1: Transcriber + protocol seam + 4 tests. iter 2: detectLanguage fix (Stage-5 smoke defect) |
| 4 review | done | inline P1 reentrancy AUTO-FIXED; cold review 2 findings both verified non-reproducing; Codex unavailable |
| 5 ship gate | SHIPPED | manual smoke iter 1 → English-translation defect; iter 2 fix → user confirmed Chinese transcript correct ("gj" / "ship that bro") |
| 6 terminal | SHIPPED | this artifact |

## Scope (grill-locked)

**IN**: model-load (`openai_whisper-base`) · transcribe saved WAV · UI shows
transcript · `Transcribing` protocol seam · mock-engine tests.
**OUT** (each its own future slice): Groq fallback · LLM enhance · paste ·
hotkey · fixture set + WER baseline · streaming · model picker · progress bar
· iOS · settings page.

Grill log: Q1 existence → new `Transcriber` type, leave `whisperKitReachable()`
stub (recommended, first reply). Q2 scope → base on-device round-trip only
(recommended, first reply). Q3 reversibility → two-way door, additive
(recommended, first reply).

## Files

**Added**

- `Core/Sources/MurmurCore/Transcriber.swift` — `protocol Transcribing` seam;
  `actor WhisperKitTranscriber` (lazy single-flight model load, `base`,
  `downloadBase` under App Support container); `@MainActor Transcriber`
  `ObservableObject` (isTranscribing / transcript / lastError, idempotent);
  `makeDefault()` factory (keeps WhisperKit import out of the app target).
- `Core/Tests/MurmurCoreTests/TranscriberTests.swift` — 4 tests (success,
  failure, error-clears-on-success, in-flight-call-is-no-op) via fake engines;
  no real model.

**Modified**

- `Sources/MurmurMac/MurmurApp.swift` — ContentView gets `Transcriber`,
  "Transcribing…" spinner, transcript scroll view, record button disabled
  during transcribe; `toggle()` transcribes only a genuinely new WAV
  (keyed off URL identity + no error).

## Stage 4 review

**Inline (eng-lead, 3 lenses)** — P1: `WhisperKitTranscriber` is an `actor`
but `await WhisperKit(config)` is a suspension point; two concurrent first
calls could each see `whisperKit == nil` and start two downloads (actor
reentrancy). Real app path is guarded by `Transcriber`'s idempotency, but the
actor is `public`. **AUTO-FIXED**: in-flight `Task` memoization
(`loadTask`) → single download under concurrency.

**Cold review (decorrelated, raw diff only)**

| # | Finding | Verdict |
|---|---|---|
| 1 | P1 stale `lastSavedURL` re-transcription | **rejected — non-reproducing**. Every `stop()` path updates `lastSavedURL` (success) or sets `lastError` (failure); `lastError == nil` guard gates correctly. Reviewer self-downgraded to 7 with no concrete repro. The suggested URL-identity hardening was still applied as cheap robustness (call-site only, no AudioRecorder API change). |
| 2 | P2 test scheduler coupling in `testInFlightCallIsNoOp` | **rejected — not a bug**. `isTranscribing = true` runs synchronously on `@MainActor` before the `await`; ordering is guaranteed by actor isolation, not scheduler luck. |
| — | "single-flight Task caching is correct" | **cross-confirmed** the inline reentrancy auto-fix |

Codex: unavailable (companion script not present) — noted per contract.
Resulting counts: P0=0 P1=0 COVERAGE GAP=0 SCOPE DRIFT=0 → review clean.

## Stage 5 — manual smoke (the load-bearing gate)

WhisperKit's real model can't run in CI (≈140 MB + Core ML). Smoke is the
only functional gate.

- **iter 1**: spoke Chinese → got `"Okay, let's test it."` (English). Pipeline
  worked end-to-end; defect = WhisperKit default `DecodingOptions` translates
  non-English speech to English. **Root cause**: `detectLanguage` defaults to
  `!usePrefillPrompt == false` when `language == nil`, so the decoder prefills
  the English language token. `task` was already `.transcribe` — not the lever.
  → Stage 3 iteration 2.
- **fix**: `DecodingOptions(task: .transcribe, detectLanguage: true)`.
  Documented: `docs/learnings/pitfalls/2026-05-15-whisperkit-default-decodeoptions-translates-nonenglish.md`.
- **iter 2**: rebuilt, model cache reused (no re-download). User spoke Chinese
  → `"你好，我今天想要來測試中文，是不是對的？"` correct, in Chinese, no
  translation, no crash. **Smoke PASS.**

## Verification

`cd Core && swift build` ✓ · `swift test` 12/12 ✓ (6 WAVWriter + 4
Transcriber + 2 baseline) · `./scripts/bootstrap.sh` ✓ · `xcodebuild …
ONLY_ACTIVE_ARCH=YES build` `** BUILD SUCCEEDED **` ✓ (used the
correct invocation per the xcodegen pitfall — no `-arch arm64`). Functional:
manual smoke iter 2 PASS.

## Terminal state: SHIPPED

Record → text loop closed and user-validated in Chinese. Commits pushed to
`chore/xcode-bootstrap`; PR #1 (cumulative xcode-bootstrap → audio →
transcribe) auto-updates.

## OPEN_QUESTIONS

1. **Branch/PR strategy** — resolved by reality: one cumulative PR #1 for the
   branch is the established repo pattern. No split.
2. **`makeDefault()` silent degradation** — if App Support URL fails, falls
   back to WhisperKit's default cache dir; under sandbox that may not be
   writable → transcribe throws → surfaced as `lastError` (no crash).
   Acceptable degradation for v0.1; revisit if it bites in dogfood.
3. **`WhisperKitTranscriber` real-model path untested in CI** — by design
   (dojo gotcha 6). Single-flight memoization is a textbook pattern verified
   by construction + cold review; the `Transcribing` boundary is fully faked
   in tests. Real path = manual smoke only.
4. **Concurrent record-while-transcribing** — UI disables the record button
   during transcribe, and `Transcriber` is idempotent; a transcribe requested
   mid-flight is silently dropped (matches `AudioRecorder` idempotency). Fine
   for one-button-one-flow; revisit only if dogfood surfaces it.

## Origin

- Intake: `/sprint 4` (scope + model-size confirmed interactively)
- Dojo: `docs/briefs/2026-05-15-sprint-4-transcribe-dojo.md`
- Prereqs SHIPPED: `docs/sessions/2026-05-14-sprint-3-audio.md`,
  `docs/sessions/2026-05-14-sprint-murmur-xcode-bootstrap.md`
- Persona: `pandastack:eng-lead`
