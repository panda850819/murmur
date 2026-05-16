---
date: 2026-05-16
type: pitfall
topic: Reusing one WhisperKit AudioProcessor across record sessions → silent zero-capture
tags: [pitfall, macos, whisperkit, avaudioengine, audio, murmur]
sprint: murmur-sprint-5-hotkey-paste
---

# WhisperKit `AudioProcessor` reuse → silent no-capture on the 2nd+ session

## Symptom

First dictation records and transcribes fine. The **second and every
subsequent** recording in the same app launch produces "No audio
captured." (zero samples) — no error, no crash, the engine appears to
start. Surfaced the moment hold-to-talk made repeated discrete recordings
the normal usage (a button-only UI hid it because nobody recorded twice
in a row during testing).

## Root cause

`AudioRecorder` held **one** `WhisperKit.AudioProcessor`, created in
`init`, and called `startRecordingLive()` / `stopRecording()` on it every
cycle. WhisperKit's `stopRecording()` *does* tear its engine down
(`engine.disconnectNodeInput`, `engine.stop()`, `engine.reset()`,
`audioEngine = nil`) and `startRecordingLive()` *does* build a fresh
`AVAudioEngine` via `setupEngine()` (which `prepare()`s and `start()`s it).
On paper reuse should work — but in practice, reusing the *same
AudioProcessor instance* across sessions leaves the audio input in a state
where the next `setupEngine()`'s freshly-installed tap never receives
buffers. The tap is installed, the engine reports started, `audioSamples`
just stays empty.

## Fix

Build a **fresh `AudioProcessor` per recording session**; release it on
stop so the next `start()` constructs a new one:

```swift
private let makeProcessor: () -> AudioProcessor
private var audioProcessor: AudioProcessor?

public init(makeProcessor: @escaping () -> AudioProcessor = { AudioProcessor() }) {
    self.makeProcessor = makeProcessor
}
// start(): let p = makeProcessor(); try p.startRecordingLive(...); audioProcessor = p
// stop():  p.stopRecording(); read p.audioSamples; audioProcessor = nil
```

Injecting a `() -> AudioProcessor` factory (not a single instance) keeps
the test seam while guaranteeing per-session freshness.

## Why non-obvious

1. WhisperKit's `stopRecording()` looks like a complete teardown
   (`engine.reset()` + `audioEngine = nil`), so "reuse is fine" reads as
   true from the source.
2. No error surfaces — `startRecordingLive()` doesn't throw, the engine
   starts, the tap installs. The only signal is empty `audioSamples`,
   which our layer reports as the generic "No audio captured."
3. A button-driven UI rarely exercises back-to-back recordings, so it
   stays latent until a hotkey makes repeated dictation the default.

## Origin

- Murmur Sprint 5 dogfood (2026-05-16). User: "第二次之後就變成 no audio."
  Read WhisperKit 1.0.0 `AudioProcessor.swift` (`startRecordingLive` 1030,
  `setupEngine` 974, `stopRecording` 1086) to confirm the teardown looked
  complete, then applied the fresh-per-session pattern WhisperKit's own
  demos use for discrete recordings.
- Pattern echo: same shape as the S5 permission pitfall — "looks complete
  / returns success, but the next cycle silently does nothing." When a
  second cycle silently no-ops, suspect cross-session instance reuse first.
