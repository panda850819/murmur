import AVFoundation
import Foundation
import os
import WhisperKit

/// Records audio from the system default input through WhisperKit's
/// `AudioProcessor`, writes a 16 kHz mono Float32 WAV on stop, and exposes
/// `@Published` state for SwiftUI binding.
///
/// Repeated-recording correctness (Sprint 5 dogfood):
/// WhisperKit's `startRecordingLive()` builds a brand-new `AVAudioEngine`
/// every call and `stopRecording()` does `engine.reset()` + nils it. A few
/// create→reset→recreate cycles on the macOS audio HAL leave a fresh
/// engine's input tap delivering zero buffers — the 2nd/3rd dictation
/// silently captures nothing. The fix: build the engine **once**
/// (`startRecordingLive`) and thereafter `pauseRecording()` /
/// `resumeRecordingLive()` so the engine is never reset. Samples are
/// accumulated through our own callback into a lock-guarded buffer rather
/// than read off WhisperKit's `audioSamples` (which the tap thread mutates).
///
/// Sprint 3 goals: ≥3 s recording, 16 kHz mono Float32 WAV, 30 s hard cap.
@MainActor
public final class AudioRecorder: ObservableObject {
    public static let hardCapSeconds: TimeInterval = 30

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var lastSavedURL: URL?
    @Published public private(set) var lastError: String?

    private let audioProcessor: AudioProcessor
    private var hardCapTask: Task<Void, Never>?
    private var didStartLive = false

    /// This session's samples, appended from the tap thread (via our
    /// callback) and read on the main actor — `OSAllocatedUnfairLock`
    /// synchronises both sides so the read is not a data race against the
    /// in-flight tap (we no longer rely on `stopRecording()`'s synchronous
    /// `removeTap`, since we never call it per session).
    private let captureBuffer = OSAllocatedUnfairLock<[Float]>(initialState: [])

    // --- TEMP diagnostics (remove once 2nd+ no-capture is confirmed fixed) ---
    private static let log = Logger(subsystem: "com.panda.murmur", category: "audio")
    private var sessionCount = 0
    private var startedAt: Date?

    public init(audioProcessor: AudioProcessor = AudioProcessor()) {
        self.audioProcessor = audioProcessor
    }

    /// Request mic permission and start recording. Idempotent — calling while
    /// already recording is a no-op.
    public func start() async {
        guard !isRecording else { return }
        lastError = nil

        guard await AudioProcessor.requestRecordPermission() else {
            lastError = "Microphone permission denied."
            return
        }

        sessionCount += 1
        let n = sessionCount
        captureBuffer.withLock { $0.removeAll(keepingCapacity: true) }

        let buffer = captureBuffer
        let sink: ([Float]) -> Void = { samples in
            buffer.withLock { $0.append(contentsOf: samples) }
        }

        do {
            if didStartLive {
                // Do NOT touch audioProcessor.audioSamples: the tap thread is
                // its writer and it has no synchronisation, so any main-actor
                // mutation here is a data race (codex P1-a). We read only our
                // own lock-guarded captureBuffer, so WhisperKit's internal
                // array is unused — it just grows for the app's lifetime
                // (paused between sessions, so only during active recording).
                // Accepted v0.1 tradeoff; the real resolution is the
                // bypass-WhisperKit-AudioProcessor path (see OPEN_QUESTIONS).
                try audioProcessor.resumeRecordingLive(inputDeviceID: nil, callback: sink)
            } else {
                try audioProcessor.startRecordingLive(inputDeviceID: nil, callback: sink)
                didStartLive = true
            }
        } catch {
            Self.log.error("session #\(n) start threw: \(error.localizedDescription)")
            lastError = "Start failed: \(error.localizedDescription)"
            return
        }

        startedAt = Date()
        isRecording = true
        Self.log.info("session #\(n) started (resume=\(self.didStartLive && n > 1))")
        hardCapTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.hardCapSeconds * 1_000_000_000))
            } catch {
                return  // cancelled by a manual stop() — don't fire auto-stop
            }
            await self?.stop()
        }
    }

    /// Stop recording and write the accumulated samples to WAV. Returns the URL
    /// written by this call, or nil if nothing was captured or the write failed
    /// (inspect `lastError`). Idempotent.
    @discardableResult
    public func stop() async -> URL? {
        guard isRecording else { return nil }
        hardCapTask?.cancel()
        hardCapTask = nil

        // Pause (NOT stop) — keeps the one engine alive so the next session
        // resumes it instead of churning a fresh engine through the HAL.
        audioProcessor.pauseRecording()
        isRecording = false

        let samples = captureBuffer.withLock { $0 }

        let n = sessionCount
        let ms = Int((startedAt.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
        Self.log.info("session #\(n) stopped after \(ms)ms; captured=\(samples.count) samples")

        guard !samples.isEmpty else {
            // TEMP: surface session #, hold ms, sample count on-screen.
            lastError = "No audio captured. [diag #\(n), \(ms)ms, \(samples.count) samples]"
            return nil
        }

        do {
            let url = try WAVWriter.write(samples: samples)
            lastSavedURL = url
            return url
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
            return nil
        }
    }
}
