---
date: 2026-05-14
type: dojo-brief
topic: murmur-sprint-3-audio
tags: [dojo, sprint-3-audio, eng-lead]
---

# Dojo prep — Sprint 3 audio (post-infra resume)

> Sprint 3 audio scope per `docs/briefs/2026-05-12-sprint-3-scope.md`.
> Infra now green: `chore/xcode-bootstrap` SHIPPED, bootstrap.sh + xcodebuild
> CI lane both pass.

## Past similar cases scanned

| Case | Relevance | Takeaway |
|---|---|---|
| Sprint 2 (`2026-05-11-sprint-2-repo-bootstrap.md`) | high | Established Core/ SPM + MurmurMac scaffold this work extends |
| Sprint 3 PAUSED1 + PAUSED2 (`2026-05-14-sprint-3-paused-xcode-infra.md`) | high | Original Sprint 3 dissolved into infra fight; infra resolved by xcode-bootstrap sprint; audio scope untouched |
| `murmur-xcode-bootstrap` (just SHIPPED) | high | bootstrap.sh / patch-xcodeproj.py / Murmur.xcodeproj graph now reliable; xcodebuild build path proven |
| `learnings/pitfalls/2026-05-14-xcodegen-local-package-product-dependency-missing-link.md` | medium | Why bootstrap.sh exists. Not load-bearing for audio code, only for build invocation |

## Current repo state (verified 2026-05-14)

```
murmur/
├── BRIEF.md / ROADMAP.md / LICENSE.md / README.md
├── project.yml                                # XcodeGen, locked Sprint 3
├── scripts/bootstrap.sh                       # xcodegen generate + patch
├── scripts/patch-xcodeproj.py                 # XcodeGen 2.45.4 workaround
├── .github/workflows/ci.yml                   # spm + xcodebuild lanes (macos-15)
├── Sources/MurmurMac/
│   ├── MurmurApp.swift                        # placeholder ContentView, just shows version
│   ├── Info.plist                             # NSMicrophoneUsageDescription set
│   └── Murmur.entitlements                    # app-sandbox + device.audio-input + network.client
├── Core/
│   ├── Package.swift                          # MurmurCore lib + MurmurCoreTests
│   ├── Sources/MurmurCore/Murmur.swift        # version + whisperKitReachable() stub
│   └── Tests/MurmurCoreTests/MurmurCoreTests.swift  # 2 trivial assertions
└── Murmur.xcodeproj/                          # gitignored, regen via bootstrap.sh
```

No half-built audio code anywhere. `Murmur` enum in Core is the WhisperKit
reachability stub — leave it alone, add new `AudioRecorder` type alongside.

## WhisperKit AudioProcessor — confirmed API (Core/.build/checkouts/WhisperKit @ 1.0.0)

```swift
// Sources/WhisperKit/Core/Audio/AudioProcessor.swift
public final class AudioProcessor: ... {
    public var audioSamples: ContiguousArray<Float> = []    // accumulated, 16kHz mono Float32
    public var audioBufferCallback: (([Float]) -> Void)?    // live tap

    public static func requestRecordPermission() async -> Bool      // line 780
    public static func getAudioDevices() -> [AudioDevice]           // line 810 (macOS)

    public func startRecordingLive(
        inputDeviceID: DeviceID? = nil,
        callback: (([Float]) -> Void)? = nil
    ) throws                                                         // line 1030

    public func stopRecording()                                      // line 1086
}
```

`setupEngine()` (line 974) creates `AVAudioFormat(commonFormat: .pcmFormatFloat32,
sampleRate: 16000, channels: 1, interleaved: false)`. So `audioSamples` after
`stopRecording()` is exactly what goal-L0-b asks for — no resample, no
channel mix needed on our side.

`WhisperAX/Views/ContentView.swift` line 1564-1620 demo confirmed: request
permission → `audioProcessor.startRecordingLive(inputDeviceID: id) { _ in }`
→ `stopRecording()`. Our path mirrors this minus the streaming transcribe
callback (we just collect samples and write the wav at stop).

## Implementation plan (eng-lead, minimal diff)

### Files added

```
Core/Sources/MurmurCore/AudioRecorder.swift                # new type
Core/Sources/MurmurCore/WAVWriter.swift                    # write 16kHz mono Float32 PCM to .wav
Core/Tests/MurmurCoreTests/WAVWriterTests.swift            # synthetic-samples WAV round-trip test
```

### Files edited

```
Sources/MurmurMac/MurmurApp.swift                          # ContentView gets Record/Stop button + status
```

### `AudioRecorder` shape

```swift
@MainActor
public final class AudioRecorder: ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var lastSavedURL: URL?
    @Published public private(set) var lastError: String?

    private let audioProcessor = AudioProcessor()
    private var hardCapTask: Task<Void, Never>?
    private let hardCapSeconds: TimeInterval = 30  // goal-L0-d

    public init() {}

    public func start() async {
        guard !isRecording, await AudioProcessor.requestRecordPermission() else {
            lastError = "Microphone permission denied."
            return
        }
        do {
            try audioProcessor.startRecordingLive(inputDeviceID: nil, callback: nil)
            isRecording = true
            lastError = nil
            hardCapTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.hardCapSeconds ?? 30))
                guard !Task.isCancelled else { return }
                await self?.stop()
            }
        } catch {
            lastError = "Start failed: \(error.localizedDescription)"
        }
    }

    public func stop() async {
        guard isRecording else { return }
        hardCapTask?.cancel()
        hardCapTask = nil
        audioProcessor.stopRecording()
        isRecording = false
        let samples = Array(audioProcessor.audioSamples)
        audioProcessor.audioSamples.removeAll(keepingCapacity: false)
        do {
            let url = try WAVWriter.write(samples: samples)
            lastSavedURL = url
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
        }
    }
}
```

### `WAVWriter` shape

```swift
public enum WAVWriter {
    public static let sampleRate: Double = 16_000   // goal-L0-b
    public static let channelCount: AVAudioChannelCount = 1

    public static func write(samples: [Float], at url: URL? = nil) throws -> URL {
        let target = try url ?? Self.makeTimestampedURL()
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else { throw WAVError.formatUnavailable }
        let file = try AVAudioFile(forWriting: target, settings: format.settings)
        // chunked PCM buffer write — 4096 frames per chunk to keep peak memory bounded
        var idx = 0
        let frameChunk = 4096
        while idx < samples.count {
            let end = min(idx + frameChunk, samples.count)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(end - idx)) else {
                throw WAVError.bufferAllocationFailed
            }
            buffer.frameLength = AVAudioFrameCount(end - idx)
            let dst = buffer.floatChannelData![0]
            samples.withUnsafeBufferPointer { src in
                dst.update(from: src.baseAddress!.advanced(by: idx), count: end - idx)
            }
            try file.write(from: buffer)
            idx = end
        }
        return target
    }

    private static func makeTimestampedURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        // Inside sandbox this resolves to:
        // ~/Library/Containers/com.panda.murmur/Data/Library/Application Support/
        // Outside sandbox (swift test): ~/Library/Application Support/
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return appSupport
            .appendingPathComponent("Murmur/Recordings", isDirectory: true)
            .appendingPathComponent("\(stamp).wav")
    }
}

public enum WAVError: Error {
    case formatUnavailable
    case bufferAllocationFailed
}
```

### `MurmurApp.swift` ContentView edits

Replace placeholder VStack with:

```swift
struct ContentView: View {
    @StateObject private var recorder = AudioRecorder()

    var body: some View {
        VStack(spacing: 16) {
            Text("Murmur")
                .font(.largeTitle).fontWeight(.semibold)
            Text("v\(Murmur.version)")
                .font(.callout).foregroundStyle(.secondary)
            Button(action: toggle) {
                Text(recorder.isRecording ? "Stop" : "Record")
                    .frame(minWidth: 120)
            }
            .keyboardShortcut(.return, modifiers: [])
            .controlSize(.large)
            if let url = recorder.lastSavedURL {
                Text("Saved: \(url.lastPathComponent)")
                    .font(.footnote).foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if let err = recorder.lastError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 240)
    }

    private func toggle() {
        Task {
            if recorder.isRecording { await recorder.stop() }
            else { await recorder.start() }
        }
    }
}
```

### Tests

```swift
final class WAVWriterTests: XCTestCase {
    func testWriteRoundTripsAt16kHzMonoFloat32() throws {
        // 1 second of 440 Hz sine at 16 kHz
        let n = 16_000
        let samples: [Float] = (0..<n).map { i in
            Float(sin(2 * .pi * 440 * Double(i) / 16_000))
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wavwriter-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = try WAVWriter.write(samples: samples, at: tmp)
        XCTAssertEqual(url, tmp)

        let f = try AVAudioFile(forReading: url)
        XCTAssertEqual(f.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(f.fileFormat.channelCount, 1)
        XCTAssertEqual(f.length, AVAudioFramePosition(n))
    }
}
```

### Verification path

```
# Stage 3 end checks
cd Core && swift build            # Core compiles
cd Core && swift test             # WAVWriterTests passes
./scripts/bootstrap.sh            # Xcode project regen + patch
xcodebuild -project Murmur.xcodeproj -scheme MurmurMac \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  ONLY_ACTIVE_ARCH=YES build      # .app builds

# Manual smoke (Stage 3 done line)
open build/Debug/Murmur.app        # or run from Xcode
# Click Record → talk 5s → click Stop → confirm filename shown
# open ~/Library/Containers/com.panda.murmur/Data/Library/Application\ Support/Murmur/Recordings/*.wav
# QuickTime should play back the 5s recording with audible voice. Mic dialog said "Murmur".
```

## Gotchas surfaced (carry into Stage 3)

1. **`getAudioDevices()` is macOS-only** in WhisperKit. Don't call from
   shared MurmurCore without `#if os(macOS)`. We don't need it — `nil` device
   id picks system default, which goal scope wants.
2. **AVAudioFile is in AVFoundation** — both targets already link it
   transitively through WhisperKit; explicit `import AVFoundation` still
   needed in `WAVWriter.swift`.
3. **`@MainActor` on AudioRecorder** matches `@Published` + SwiftUI binding.
   `AudioProcessor.startRecordingLive` is fine on main; its internal engine
   tap dispatches the buffer callback on its own queue. We don't take a
   buffer callback (callback: nil), so no thread hop needed.
4. **30s hard cap (goal-L0-d) implemented via `Task.sleep`** — cancels on
   manual stop. Cooperative cancellation; no signal handler / kqueue.
5. **`audioSamples.removeAll(keepingCapacity: false)`** prevents the buffer
   from growing unbounded across record cycles. WhisperKit's instance keeps
   the array on the live instance unless purged.
6. **Sandbox path resolution** — `FileManager` resolves application support
   inside the container at runtime. `swift test` runs unsandboxed so the
   test writes under `~/Library/Application Support/` directly — that's why
   the test uses `NSTemporaryDirectory()` to keep host trees clean.
7. **AVAudioFile write throws if directory missing** — `createDirectory(...,
   withIntermediateDirectories: true)` is idempotent and cheap on hot path.
8. **`#Preview` macro** still works since ContentView depends only on
   `AudioRecorder()` (no AVAudioEngine setup in init). Live preview won't
   record (no permission), but it renders.
9. **Hard kill anchor** — sprint estimate (per brief) 2-3 hr. goal-L1-a
   checkpoint at 2 hr, hard PAUSED at 3 hr.

## Out of scope reminder (from sprint-3-scope L3)

WhisperKit transcribe / hotkey / paste / LLM enhance / UI polish / iOS /
fixture-set + WER baseline / settings page → **all Sprint 4+**. Drift signal:
mid-execute urge to "also wire up transcribe since AudioProcessor is right
there" → STOP, log to Inbox/, continue Stage 3.

## Open prep questions for grill (Stage 2)

1. **Should AudioRecorder live in Core/ (shared) or in MurmurMac (platform)?**
   — Recommend Core/. It uses only AVAudioEngine + WhisperKit which exist
   on both platforms. Future iOS app gets it for free.
2. **WAV writer via AVAudioFile vs hand-rolled WAV header?** — Recommend
   AVAudioFile (less code, native Apple API, no custom header bugs).
3. **Auto-recover if `applicationSupportDirectory` create fails?** — No,
   throw. Sandbox app's container is provisioned by macOS — failure means
   something deeper is wrong, surface it.

## Ready check

- [x] Past Sprint 3 audio scope context loaded
- [x] WhisperKit AudioProcessor API confirmed
- [x] WhisperAX demo integration pattern read
- [x] Repo state verified clean (working tree, on chore/xcode-bootstrap)
- [x] Existing files mapped (no half-built audio code)
- [x] CI lanes proven (Sprint 2 + xcode-bootstrap)
- [x] Implementation skeleton sketched
- [x] Verification path defined (build + test + manual smoke)
