import AVFoundation
import Foundation
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

    /// A FRESH `AudioProcessor` is built per recording session, not reused.
    /// Reusing one instance across start/stop cycles makes the 2nd+ session
    /// silently capture zero samples ("No audio captured.") — WhisperKit's
    /// `stopRecording()` does `engine.reset()` + nils its engine, but a
    /// reused processor still leaves the audio input in a state where the
    /// next `setupEngine()`'s tap never receives buffers. A new instance per
    /// session sidesteps it entirely (matches WhisperKit demo usage for
    /// discrete recordings).
    private let makeProcessor: () -> AudioProcessor
    private var audioProcessor: AudioProcessor?
    private var hardCapTask: Task<Void, Never>?

    public init(makeProcessor: @escaping () -> AudioProcessor = { AudioProcessor() }) {
        self.makeProcessor = makeProcessor
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

        let processor = makeProcessor()
        do {
            try processor.startRecordingLive(inputDeviceID: nil, callback: nil)
        } catch {
            lastError = "Start failed: \(error.localizedDescription)"
            return
        }
        audioProcessor = processor
        isRecording = true
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
        guard isRecording, let processor = audioProcessor else { return nil }
        hardCapTask?.cancel()
        hardCapTask = nil

        // stopRecording() synchronously removes the input tap (WhisperKit
        // AudioProcessor.swift:1090). AVAudioNode.removeTap is synchronous
        // w.r.t. in-flight tap blocks, so once it returns nothing can append
        // to audioSamples — the read below is race-free, no lock needed.
        processor.stopRecording()
        isRecording = false

        let samples = Array(processor.audioSamples)
        // Release this session's processor so the next start() builds a
        // fresh one (see `makeProcessor` doc — reuse = silent no-capture).
        audioProcessor = nil

        guard !samples.isEmpty else {
            lastError = "No audio captured."
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
