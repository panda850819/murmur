---
date: 2026-05-16
type: pitfall
status: resolved-design
topic: Repeated WhisperKit recording → 2nd+ session captures nothing
tags: [pitfall, macos, whisperkit, avaudioengine, audio, murmur]
sprint: murmur-sprint-5-hotkey-paste
---

# Repeated WhisperKit recording → "No audio captured." on the 2nd+ session

> **RESOLUTION (supersedes the analysis below).** Several intermediate
> conclusions here were drawn on a stale "ghost" binary (see the
> `2026-05-18-xcodebuild-stale-deriveddata` pitfall) and are unreliable.
> On *verified* builds the real, general pattern is: **re-activating
> macOS audio input throws `-10868` (`kAudioUnitErr_FormatNotSupported`)
> after a few cycles, regardless of how** — WhisperKit
> `startRecordingLive`/`stopRecording` (~#2–3), WhisperKit `pause`/`resume`
> (#6), and an own persistent `AVAudioEngine` with `stop()`/`start()`
> (#2) all failed identically. The only design that structurally avoids it:
> start ONE `AVAudioEngine` once for the app's lifetime, install the input
> tap once, **never stop/pause/reset it**, and gate sample accumulation
> with a flag. Cost: mic indicator stays on while the app is open
> (accepted v0.1). General lesson: on macOS, treat "stop then re-start
> audio input" as a known-bad operation — keep the input graph alive and
> gate downstream, don't tear capture down per use.

## Symptom

With one shared `AudioProcessor` calling `startRecordingLive()` /
`stopRecording()` per dictation: the first 1–2 recordings work; a later
one (observed: session #3, full 2520 ms hold) returns "No audio
captured." — **zero** samples, no thrown error, despite a long hold.

## Root cause (data + source confirmed)

WhisperKit 1.0.0 `AudioProcessor`:
- `startRecordingLive()` → `setupEngine()` builds a **brand-new
  `AVAudioEngine`**, installs the tap, `prepare()` + `start()`.
- `stopRecording()` → `engine.disconnectNodeInput` + `engine.stop()` +
  **`engine.reset()`** + `audioEngine = nil`.

So every dictation creates and hard-resets a new `AVAudioEngine` on the
same macOS audio HAL. After a few create→reset→recreate cycles the next
engine's input tap silently delivers **zero** buffers — `processBuffer`
never fires, `audioSamples` stays empty. Diagnostic `[diag #3, 2520ms, 0
samples]` confirmed: not a short-hold/cancel issue, the engine genuinely
captured nothing on the 3rd cycle.

## Disproven hypothesis (kept so it isn't retried)

"Build a fresh `AudioProcessor` per session." **Regressed the 1st
recording to zero-capture** — a brand-new processor's first
`setupEngine()` queries `inputNode.inputFormat(forBus:0)` on a cold
engine. Instance reuse is *not* the cause; engine create/reset churn is.

## Fix

Build the engine **once** and never reset it per session:
- 1st `start()` → `startRecordingLive(callback:)` (creates the engine).
- `stop()` → `pauseRecording()` (engine.pause(); tap stays installed;
  engine NOT reset/niled).
- subsequent `start()` → `resumeRecordingLive(callback:)` (just
  `audioEngine?.start()` on the same paused engine).
- `stopRecording()` only ever runs via `AudioProcessor.deinit` (app
  teardown).

Accumulate samples through our **own callback into an
`OSAllocatedUnfairLock<[Float]>`** instead of reading WhisperKit's
`audioSamples` — we no longer call `stopRecording()` per session, so its
synchronous `removeTap` (the old basis for a lock-free read) is gone; the
lock makes the tap-thread append / main-actor read race-free.

## Why non-obvious

`stopRecording()` reads as the natural "end a recording" call and looks
like a clean teardown, so the start/stop-per-session shape is the obvious
one. The damage is cumulative HAL state across engine resets, so it
*works the first couple of times* — masking the bug in any quick test.
WhisperKit's own `pause`/`resume` API is the intended path for repeated
capture but isn't signposted as "use this instead of stop/start".

## Origin

- Murmur Sprint 5 dogfood (2026-05-16). "第二次之後就變成 no audio" →
  fresh-instance attempt (regressed #1) → revert + on-screen `[diag …]`
  instrumentation → `#3, 2520ms, 0 samples` pinned the engine-churn
  mechanism → pause/resume + own-buffer fix. Final user verification
  pending; mechanism is data + source confirmed.
- General rule: when a repeated-resource operation works the first N times
  then silently no-ops, suspect cumulative teardown/recreate state on a
  shared OS resource (audio HAL, file handle, GPU context) before
  suspecting your own per-call logic.
