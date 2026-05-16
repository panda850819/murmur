---
date: 2026-05-16
type: pitfall
status: investigating
topic: Repeated WhisperKit recording → 2nd+ session captures nothing (root cause UNCONFIRMED)
tags: [pitfall, macos, whisperkit, avaudioengine, audio, murmur, open]
sprint: murmur-sprint-5-hotkey-paste
---

# Repeated WhisperKit recording → "No audio captured." on the 2nd+ session

> **Status: OPEN — root cause not yet confirmed.** This note records a
> *disproven* hypothesis so the wrong fix isn't reattempted, plus the
> instrumentation now in place to get ground truth. Do not treat the
> "fix" below as real until the instrumented data confirms a cause.

## Symptom

With one shared `AudioProcessor` (created at `AudioRecorder.init`): the
1st dictation after launch records + transcribes fine; the **2nd and
every subsequent** recording returns "No audio captured." (zero samples,
no thrown error). Surfaced once hold-to-talk made back-to-back dictation
the normal usage.

## Hypothesis #1 — DISPROVEN

"Reusing one `AudioProcessor` across sessions corrupts capture; build a
fresh one per session." Implemented (factory-injected
`AudioProcessor` per `start()`), shipped to dogfood. **Result: regression
— even the 1st recording then captured zero samples.** So instance reuse
is *not* the cause (a fresh per-session processor is strictly worse), and
the shared instance is the known-good baseline for at least the 1st
recording. Reverted.

Lesson already bankable: **WhisperKit `AudioProcessor` wants to be
long-lived; constructing it immediately before `startRecordingLive()`
breaks even the first capture.** Why is still unconfirmed — plausibly the
fresh `AVAudioEngine().inputNode` format is not ready when queried
synchronously right after `AudioProcessor()` construction, vs. an
instance that has existed since launch.

## Current state

Reverted to the shared instance + added temporary instrumentation
(`os.Logger` subsystem `com.panda.murmur` category `audio`, plus an
on-screen `[diag #session, ms, samples]` suffix on the no-capture error)
so a single screenshot / Console line tells us, per session: count,
hold duration, captured sample count, and whether `startRecordingLive`
threw. Next dogfood run produces the data; the real fix follows from it,
not from another guess.

## Why this is logged before it's solved

A confidently-written "fix" that regressed is worse than an open
question. The anti-pattern (pandastack `review` skill): "after 3-4 failed
patches the next patch is statistical noise — stop, dump the full failure
picture, diagnose with data." This file is that dump.

## Origin

- Murmur Sprint 5 dogfood (2026-05-16). Reports: "第二次之後就變成 no
  audio" → fresh-instance attempt → "第 1 次就 No audio" (regression) →
  revert + instrument. Resolution pending instrumented data.
