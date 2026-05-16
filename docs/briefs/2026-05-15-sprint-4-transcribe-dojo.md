---
date: 2026-05-15
type: prep
flow: sprint
topic: murmur-sprint-4-transcribe
tags: [prep, dojo, sprint-4, eng-lead]
---

# Dojo prep — Sprint 4: WhisperKit model-load + transcribe round-trip

> Scope locked via /sprint 4 intake: load WhisperKit `base` model →
> transcribe the WAV produced by Sprint 3 → UI shows transcript.
> Closes the `record → text` half of the v0.1 "one button one flow".
> Model size = **base** (~140 MB), user-confirmed at intake.

## Capability probe

```
[1] AGENTS substrate : ok  (~/.agents/AGENTS.md, 237 lines)
[2] vault root       : ok  (Inbox/ + docs/)
[3] lib/ files       : ok  (capability-probe, gate-contract, skill-decision-tree, push-once, escape-hatch)
[4] persona skills   : ok  (eng-lead + 8)
[5] cli tools        : ok  (swift 6.2.4, xcodegen 2.45.4, Xcode 26.3)
[6] write paths      : ok  (Inbox/ + docs/ writable)
→ 6/6 green
```

## Past cases

| Case | Relevance | Takeaway |
|---|---|---|
| `2026-05-14-sprint-3-audio.md` (SHIPPED) | high | WAV recorder shipped. `lastSavedURL` is the Sprint 4 input. OPEN_Q #3 explicitly defers a transcribe test seam to "Sprint 4 dojo". |
| `2026-05-14-sprint-3-audio-dojo.md` | high | WhisperKit `AudioProcessor` API confirmed there; same checkout (@1.0.0) has the transcribe API confirmed below. |
| `learnings/pitfalls/2026-05-14-xcodegen-…-missing-link.md` | **load-bearing** | The Sprint 3 "4-strike unfixable infra wall" was a masked BUILD SUCCEEDED — caused by the `xcodebuild` invocation flags, not the build. See Gotcha 1. |
| `2026-05-11-sprint-2-repo-bootstrap.md` | medium | Core/ SPM + MurmurMac scaffold this extends. WhisperKit pinned `exact 1.0.0`. |

## Lib loaded

```
✓ lib/capability-probe.md     (substrate availability — 6/6 green)
✓ lib/skill-decision-tree.md  (persona routing → eng-lead, feature impl)
✓ lib/push-once.md            (grill: push once then accept)
✓ lib/escape-hatch.md         (grill: 2-strike user-stop)
✓ lib/gate-contract.md        (Stage 4 review 4-option gate)
```

## WhisperKit transcribe API — confirmed (Core/.build/checkouts/WhisperKit @ 1.0.0)

```swift
// WhisperKit.swift
public init(_ config: WhisperKitConfig = WhisperKitConfig()) async throws        // l.56
public convenience init(model: String? = nil, downloadBase: URL? = nil,
    modelFolder: String? = nil, … , download: Bool = true, …) async throws       // l.96

open func transcribe(audioPath: String, decodeOptions: DecodingOptions? = nil,
    callback: TranscriptionCallback? = nil) async throws -> [TranscriptionResult] // l.823
open func transcribe(audioArray: [Float], …) async throws -> [TranscriptionResult] // l.867

// Models.swift — TranscriptionResult (typealias of TranscriptionResultStruct)
public var text: String                                                          // l.544
```

- `WhisperKitConfig`: `model: String?`, `downloadBase: URL?`, `modelFolder: String?`,
  `download: Bool`, `prewarm: Bool?`, `load: Bool?`, `modelStateCallback`.
- Model-string resolution (`WhisperKit.swift` l.319-337): `config.model` nil →
  `modelSupport.default` (device-recommended); else used directly. Folder names on
  `argmaxinc/whisperkit-coreml` are `openai_whisper-base` etc. `download(variant:)`
  searches `*variant/*` then falls back to `*openai*variant/*`, so `"base"` resolves,
  but **prefer the explicit `"openai_whisper-base"`** to skip the ambiguity branch.
- Transcript = `results.map(\.text).joined()` (usually one element).
- Network entitlement: `Murmur.entitlements` already has `network.client` = true →
  no entitlement change needed for model download.

## Gotchas (prior sessions)

1. **[2026-05-14 xcode-bootstrap pitfall] xcodebuild invocation can mask BUILD
   SUCCEEDED.** The Sprint 3 PAUSED2 "4-strike unfixable wall" did not reproduce —
   `-arch arm64 -destination 'platform=macOS,arch=arm64'` raises "destination implies
   architecture" and hides the real result. **Use `ONLY_ACTIVE_ARCH=YES` +
   `-destination 'platform=macOS'`, NOT `-arch arm64`.** When a build error repeats
   after fixes, re-test the harness, not just the code.
2. **[Sprint 3 OPEN_Q #3 / cold-reviewer C3] Transcribe needs a protocol test seam —
   this is Stage 3 work, not Stage 4.** WhisperKit's real model (≈140 MB HF download +
   Core ML inference) cannot run in `swift test`/CI. Introduce `protocol Transcribing`;
   real impl wraps `WhisperKit`, a fake drives tests. Per the sprint skill's
   new-pipeline-branch rule, the handler-level test with a mock is part of the
   implementation, not deferred to review.
3. **[Sprint 3 sandbox path] Model download path under sandbox.** WhisperKit's
   `downloadBase` defaults to an HF cache dir a sandboxed app may not write. Set
   `downloadBase` under the Application Support container (same root `WAVWriter` uses).
   Confirm the model actually lands inside the container at manual smoke.
4. **First-launch latency UX.** `base` first run = ~140 MB download + prewarm; tens of
   seconds to minutes. UI MUST show a non-frozen state (`isTranscribing` / model-loading
   label). A progress bar is polish → OUT. A status label is the minimal honest slice.
5. **Scope-drift magnet.** `AudioProcessor` + the WAV are right there; the urge to also
   wire Groq fallback / LLM enhance / paste / hotkey / fixture+WER will appear
   mid-execute. Sprint 3's out-of-scope reminder lists every one of those as Sprint 4+,
   each its own slice. STOP + log to Inbox if it surfaces.
6. **CI stays mock-only.** `.github/workflows/ci.yml` runs `cd Core && swift test` on
   `macos-15`. Do NOT add a model-downloading test (network + 140 MB + minutes = flaky).
   Real transcribe = manual smoke only. Do NOT strip `runs-on: macos-15` (WhisperKit
   real min = macOS 14 / Swift 6, brain CI gotcha guard).

## Current code surface (Sprint 4 builds on)

```
Core/Sources/MurmurCore/
  Murmur.swift          enum: version + whisperKitReachable() stub (leave alone)
  AudioRecorder.swift   @MainActor OO: start/stop → writes WAV → lastSavedURL
  WAVWriter.swift       16kHz mono Float32 .wav (WhisperKit-native input — comment
                        already says "Sprint 4 transcribe can load this")
Sources/MurmurMac/MurmurApp.swift   ContentView: Record/Stop + lastSavedURL/lastError
Core/Tests/MurmurCoreTests/WAVWriterTests.swift   8 tests, green
```

## Suggested entry point

Add `Transcriber.swift` to `Core/` — `@MainActor ObservableObject` owning a
`Transcribing` protocol (real impl = WhisperKit `base`, `downloadBase` →
Application Support container). Wire `AudioRecorder.stop()` success →
`Transcriber.transcribe(wavURL:)` → publish `transcript` + `isTranscribing` →
`ContentView` renders both. Tests: `TranscriberTests` with a fake `Transcribing`
(state machine + error path; no real model). Verify: `cd Core && swift test`,
then `./scripts/bootstrap.sh` + `xcodebuild … ONLY_ACTIVE_ARCH=YES` (Gotcha 1),
then manual smoke (record → see real transcript).
