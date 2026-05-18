import AVFoundation
import Foundation

/// Records a mic clip straight to a 16 kHz mono Float32 WAV file using
/// **`AVAudioRecorder`** — the OS API purpose-built for "record a clip,
/// stop, repeat". It manages the audio session / HAL internally and is
/// robust to repeated start/stop, unlike a hand-driven `AVAudioEngine`
/// tap (whose engine-lifecycle churn threw `-10868` after a few cycles no
/// matter how it was driven — see the Sprint 5 audio pitfall). WhisperKit
/// already transcribes from a file URL, so live samples were never needed.
@MainActor
public final class AudioRecorder: ObservableObject {
    public static let hardCapSeconds: TimeInterval = 30

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var lastSavedURL: URL?
    @Published public private(set) var lastError: String?

    /// 16 kHz mono Float32 PCM WAV — the format Sprint 4 validated with
    /// WhisperKit, so the transcriber input is unchanged.
    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var hardCapTask: Task<Void, Never>?

    public init() {}

    public func start() async {
        guard !isRecording else { return }
        lastError = nil

        guard await Self.ensureMicPermission() else {
            lastError = "Microphone permission denied."
            return
        }

        do {
            let url = try WAVWriter.makeTimestampedURL()
            // A fresh AVAudioRecorder per clip is the intended usage — it,
            // not us, owns the session/HAL lifecycle.
            let rec = try AVAudioRecorder(url: url, settings: Self.settings)
            guard rec.prepareToRecord(), rec.record() else {
                lastError = "Couldn't start recording."
                return
            }
            recorder = rec
            currentURL = url
        } catch {
            lastError = "Start failed: \(error.localizedDescription)"
            return
        }

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

    @discardableResult
    public func stop() async -> URL? {
        guard isRecording, let rec = recorder, let url = currentURL else { return nil }
        hardCapTask?.cancel()
        hardCapTask = nil

        rec.stop()                 // finalises the WAV file synchronously
        isRecording = false
        recorder = nil
        currentURL = nil

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? Int) ?? 0

        // A bare WAV header (~44 bytes) with no samples ⇒ nothing captured.
        guard bytes > 1024 else {
            lastError = "No audio captured."
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        lastSavedURL = url
        return url
    }

    private static func ensureMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
        default:
            return false
        }
    }
}
