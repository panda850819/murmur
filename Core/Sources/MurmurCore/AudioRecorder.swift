import AVFoundation
import Foundation
import os
import WhisperKit

/// Records audio from the system default input through WhisperKit's
/// `AudioProcessor`, writes a 16 kHz mono Float32 WAV on stop, and exposes
/// `@Published` state for SwiftUI binding.
///
/// Sprint 3 goals:
/// - goal-L0-a: ≥ 3 s usable recording (no enforced minimum here; the UI
///   simply doesn't gate on duration)
/// - goal-L0-b: WAV format = 16 kHz mono Float32 PCM (WAVWriter)
/// - goal-L0-c: Saved under `Application Support/Murmur/Recordings/`
/// - goal-L0-d: 30 s hard cap (auto-stop)
/// - goal-L0-e: File opens in QuickTime (covered by AVAudioFile + format)
/// - goal-L0-f: Mic dialog says "Murmur" (covered by .app bundle + Info.plist)
@MainActor
public final class AudioRecorder: ObservableObject {
    public static let hardCapSeconds: TimeInterval = 30

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var lastSavedURL: URL?
    @Published public private(set) var lastError: String?

    // Shared instance (known-good for the 1st recording). The earlier
    // "fresh AudioProcessor per session" attempt regressed the 1st
    // recording to zero-capture, so it was reverted; the real cause of the
    // "2nd+ recording captures nothing" report is being diagnosed with the
    // instrumentation below rather than guessed at.
    private let audioProcessor: AudioProcessor
    private var hardCapTask: Task<Void, Never>?

    // --- TEMP diagnostics (remove once the 2nd+ no-capture bug is fixed) ---
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
        do {
            try audioProcessor.startRecordingLive(inputDeviceID: nil, callback: nil)
        } catch {
            Self.log.error("session #\(n) startRecordingLive threw: \(error.localizedDescription)")
            lastError = "Start failed: \(error.localizedDescription)"
            return
        }
        startedAt = Date()
        isRecording = true
        Self.log.info("session #\(n) started; samples=\(self.audioProcessor.audioSamples.count)")
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

        // stopRecording() synchronously removes the input tap (WhisperKit
        // AudioProcessor.swift:1090). AVAudioNode.removeTap is synchronous
        // w.r.t. in-flight tap blocks, so once it returns nothing can append
        // to audioSamples — the read+clear below is race-free, no lock needed.
        audioProcessor.stopRecording()
        isRecording = false

        let samples = Array(audioProcessor.audioSamples)
        audioProcessor.audioSamples.removeAll(keepingCapacity: false)

        let n = sessionCount
        let ms = Int((startedAt.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
        Self.log.info("session #\(n) stopped after \(ms)ms; captured=\(samples.count) samples")

        guard !samples.isEmpty else {
            // TEMP: surface session #, hold ms, sample count on-screen so a
            // single screenshot disambiguates 1st-vs-2nd / short-hold / engine.
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
