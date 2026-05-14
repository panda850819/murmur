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

    private let audioProcessor: AudioProcessor
    private var hardCapTask: Task<Void, Never>?

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

        do {
            try audioProcessor.startRecordingLive(inputDeviceID: nil, callback: nil)
        } catch {
            lastError = "Start failed: \(error.localizedDescription)"
            return
        }

        isRecording = true
        hardCapTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.hardCapSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    /// Stop recording, write the accumulated samples to WAV, expose the URL.
    /// Idempotent.
    public func stop() async {
        guard isRecording else { return }
        hardCapTask?.cancel()
        hardCapTask = nil

        audioProcessor.stopRecording()
        isRecording = false

        let samples = Array(audioProcessor.audioSamples)
        audioProcessor.audioSamples.removeAll(keepingCapacity: false)

        guard !samples.isEmpty else {
            lastError = "No audio captured."
            return
        }

        do {
            lastSavedURL = try WAVWriter.write(samples: samples)
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
        }
    }
}
