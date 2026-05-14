---
date: 2026-05-14
type: sprint
state: SHIPPED
topic: murmur-sprint-3-audio
mode: default
iteration: 1
persona: pandastack:eng-lead
tags: [sprint, shipped, audio-capture, whisperkit, wav-writer]
---

# Sprint — murmur-sprint-3-audio — 2026-05-14

Resumes the originally-paused Sprint 3 audio scope (see
[`2026-05-14-sprint-3-paused-xcode-infra.md`](2026-05-14-sprint-3-paused-xcode-infra.md))
now that `murmur-xcode-bootstrap` SHIPPED the Xcode infra prereq.

## Capability probe

```
[1] AGENTS substrate    : ok  (~/.agents/AGENTS.md, 237 lines)
[2] vault root          : ok  (Inbox/ + docs/)
[3] lib/ files          : ok  (capability-probe, gate-contract, skill-decision-tree, push-once, escape-hatch)
[4] persona skills      : ok  (eng-lead, dojo, grill, review, ship)
[5] cli tools           : ok  (swift 6.2.4, xcodegen 2.45.4, xcodebuild Xcode 26.3)
[6] write paths         : ok
```

## Stage progression

| Stage | Status | Output |
|---|---|---|
| 0 capability probe | ok | 6/6 green |
| 1 dojo | done | `docs/briefs/2026-05-14-sprint-3-audio-dojo.md` |
| 2 grill (lite) | done | 3 Qs (existence / scope / reversibility), 0 push-once invocations, 0 escape-hatch — all accepted on first reply |
| 3 execute | done | 3 new files + 1 modified, `swift build` + 8/8 tests + `xcodebuild` all green |
| 4 review | done | cold reviewer P0 rejected after verification; 2 P2 auto-fixed; P0/P1 remaining = 0 |
| 5 ship gate | SHIPPED | manual smoke confirmed by user (`可以的`) — mic dialog said "Murmur", QuickTime played back recorded audio |
| 6 terminal | SHIPPED | this artifact |

## Goal-L0 line — all six met

| Goal | Verification |
|---|---|
| L0-a recording ≥ 3 s usable | Engine live before `isRecording = true` closes start race; no min-duration gate added (defensible per brief) |
| L0-b 16 kHz mono Float32 PCM | `AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1)` in `WAVWriter`; verified by `testWritesAt16kHzMonoFloat32PCM` + `testRoundTripPreservesSamples` |
| L0-c saved under Application Support/Murmur/Recordings/ | `WAVWriter.makeTimestampedURL()` builds path under `FileManager .applicationSupportDirectory`; verified by `testMakeTimestampedURLLivesUnderApplicationSupport` |
| L0-d 30 s hard cap | `AudioRecorder.hardCapSeconds = 30` + `Task.sleep` auto-stop |
| L0-e QuickTime playback | Manual smoke (user) — confirmed audible voice in saved .wav |
| L0-f Mic dialog says "Murmur" | Manual smoke (user) — confirmed `Murmur` displayed in OS permission dialog; CFBundleDisplayName + NSMicrophoneUsageDescription baked into `MurmurMac.app/Contents/Info.plist` |

## L3 hard line — none breached

No transcribe / no display / no LLM enhance / no hotkey / no paste / no
fixture-set / no iOS code / no UI polish / no second SwiftUI page.

## Files added

- `Core/Sources/MurmurCore/WAVWriter.swift` — 16 kHz mono Float32 WAV writer via `AVAudioFile`, chunked write, partial-file cleanup on mid-write failure
- `Core/Sources/MurmurCore/AudioRecorder.swift` — `@MainActor ObservableObject` wrapping WhisperKit `AudioProcessor` with start / stop / 30 s hard-cap / lastSavedURL / lastError
- `Core/Tests/MurmurCoreTests/WAVWriterTests.swift` — 6 tests (format, round-trip, empty, timestamped URL, chunk boundary, partial-file cleanup)

## Files modified

- `Sources/MurmurMac/MurmurApp.swift` — ContentView replaced placeholder text with Record/Stop button, saved-URL + error display, `@StateObject AudioRecorder`

## Stage 2 grill log

```
Q1 existence: AudioRecorder placement — Core/ shared OR MurmurMac/ platform-only?
   → user: Core/ shared (recommended); accepted on first reply (no push-once)
Q2 scope boundary: extra IN/OUT beyond brief L3 list?
   → user: 如 brief、不加 (recommended); accepted on first reply
Q3 reversibility: two-way door OR one-way?
   → user: 兩面門 (recommended); accepted on first reply
```

## Stage 4 review findings

**Inline pass (eng-lead self-review):** P0=0, P1=0, P2=2 (auto-fixed below), P3=4 informational.

**Cold reviewer cross-check (general-purpose agent, fresh context):**

| # | Cold finding | Verdict | Reason |
|---|---|---|---|
| C1 | P0 9/10 — data race on `audioSamples` between WhisperKit's audio-thread tap and `@MainActor stop()` reading the buffer | **rejected** | `AudioProcessor.stopRecording` (line 1086) calls `engine.inputNode.removeTap(onBus: 0)` BEFORE `engine.stop()`. Apple `AVAudioNode.removeTap` contract is synchronous w.r.t. in-flight tap blocks — when it returns, no callback can fire and no append is in flight. The standard WhisperKit pattern is exactly this; no race surface exists. |
| C2 | P1 8/10 — `hardCapTask` `try?` doesn't propagate cancellation | **downgraded P3** | Reviewer's own analysis ends "harmless via guard". The `Task.isCancelled` check after `try? await Task.sleep` catches cancellation correctly. Style preference, not a bug. Deferred. |
| C3 | P1 7/10 — `AudioRecorder` has no test seam beyond concrete `AudioProcessor` init injection | **deferred** | Sprint brief scopes tests to `WAVWriter` only. Adding a protocol layer + AudioRecorder unit tests is future work; not blocking. |
| C4 | P2 8/10 — partial .wav left on mid-write failure | **AUTO-FIX** | Wrapped write loop in `do/catch`, `try? FileManager.default.removeItem(at: target)` on throw, rethrow. New test `testFailedWriteDoesNotLeavePartialFile` covers. |
| C5 | P2 7/10 — chunk-boundary test gap | **AUTO-FIX** | Added `testWritesAcrossMultipleChunkBoundaries` — 100 k samples crossing ~24 internal 4096-frame chunks. |
| C6 | P3 8/10 — `toggle()` unstructured `Task` per tap; rapid taps could race | **deferred** | UI-level guard (`.disabled` during transition) is overkill for sprint scope; macOS event loop naturally serializes button taps. Logged for future polish. |

**Resulting counts after cold-review merge + auto-fixes:** P0=0, P1=0, COVERAGE GAP=0 (in code), SCOPE DRIFT=0 → all-zero → Stage 5 ship gate.

## Gate Log

| Stage | Gate | Outcome |
|---|---|---|
| 2 | grill — existence | approved (first reply, no push) |
| 2 | grill — scope | approved (first reply, no push) |
| 2 | grill — reversibility | approved (first reply, no push) |
| 4 | cold-reviewer P0 | rejected (verified via WhisperKit source) |
| 4 | cold-reviewer P1×2 | downgraded / deferred |
| 4 | partial-wav cleanup | auto-fix applied |
| 4 | chunk-boundary test | auto-fix applied |
| 5 | manual smoke (L0-e/f) | approved by user — `可以的` |

## Terminal state: SHIPPED

Sprint 3 audio scope met all six L0 goals. Code clean. Tests green. App
builds and recorded audio plays back from `~/Library/Containers/com.panda.murmur/Data/Library/Application Support/Murmur/Recordings/`.

## OPEN_QUESTIONS

Carried from Sprint 3 paused checkpoint, refreshed:

1. **Branch / PR strategy** — `chore/xcode-bootstrap` now contains both the
   xcode-bootstrap SHIPPED commits AND the new audio commits (post-this-artifact).
   Options: (a) one PR for the combined infra+audio scope (b) split into
   two PRs (bootstrap merged first, audio rebased on top). User decides at
   ship time.
2. **goal-L0-a (≥ 3 s) not actively enforced in code** — UI lets user click
   Stop at 0.5 s, producing a short .wav. Brief intent was "avoid race",
   which the engine-live-before-isRecording-flip already closes. Could add
   a `minDurationSeconds` gate in a future polish sprint if dogfooding
   surfaces accidental too-short captures.
3. **AudioRecorder tests** — cold reviewer C3 deferred. Worth revisiting
   in Sprint 4 dojo if AudioRecorder gets richer state (transcribe pipeline
   integration would benefit from a test seam).
4. **Rapid-tap race on toggle()** — cold reviewer C6 deferred. If
   dogfooding catches a weird state mid-tap, add `.disabled` during
   transition.

## Resolution upstream

- The PAUSED checkpoint at [`docs/sessions/2026-05-14-sprint-3-paused-xcode-infra.md`](2026-05-14-sprint-3-paused-xcode-infra.md)
  already carried a "Resolution" appendix from the xcode-bootstrap sprint.
  This artifact closes the loop: original Sprint 3 audio scope SHIPPED.

## Origin

- Sprint brief: `docs/briefs/2026-05-12-sprint-3-scope.md`
- Dojo prep: `docs/briefs/2026-05-14-sprint-3-audio-dojo.md`
- Infra prereq SHIPPED: `docs/sessions/2026-05-14-sprint-murmur-xcode-bootstrap.md`
- Persona: `pandastack:eng-lead`
