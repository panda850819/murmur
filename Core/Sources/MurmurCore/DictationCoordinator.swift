import Foundation

/// Test seam over the audio recorder so the coordinator's flow can be unit
/// tested without a real microphone / AVAudioEngine. Mirrors `Transcribing`.
@MainActor
public protocol Recording: AnyObject {
    var isRecording: Bool { get }
    var lastError: String? { get }
    func start() async
    func stop() async -> URL?
}

extension AudioRecorder: Recording {}

/// Owns the `record → transcribe` flow as a single testable unit, off the
/// SwiftUI view. The view binds to `phase` / `transcript` / `lastSavedURL` /
/// `errorMessage` and calls `toggle()`. This is the seam where the BRIEF's
/// later Groq-fallback and paste-to-foreground steps will attach.
@MainActor
public final class DictationCoordinator: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case recording
        case transcribing
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var transcript: String?
    @Published public private(set) var lastSavedURL: URL?
    @Published public private(set) var errorMessage: String?

    private let recorder: any Recording
    private let transcriber: Transcriber

    public init(recorder: any Recording, transcriber: Transcriber) {
        self.recorder = recorder
        self.transcriber = transcriber
    }

    public static func makeDefault() -> DictationCoordinator {
        DictationCoordinator(recorder: AudioRecorder(), transcriber: .makeDefault())
    }

    /// Idle → start recording. Recording → stop, then transcribe the WAV.
    /// Taps during transcription are ignored.
    public func toggle() async {
        switch phase {
        case .transcribing:
            return

        case .idle:
            errorMessage = nil
            transcript = nil
            lastSavedURL = nil
            await recorder.start()
            guard recorder.isRecording else {
                errorMessage = recorder.lastError ?? "Couldn't start recording."
                return
            }
            phase = .recording

        case .recording:
            guard let url = await recorder.stop() else {
                errorMessage = recorder.lastError ?? "No audio captured."
                phase = .idle
                return
            }
            lastSavedURL = url
            phase = .transcribing
            await transcriber.transcribe(wavURL: url)
            transcript = transcriber.transcript
            errorMessage = transcriber.lastError
            phase = .idle
        }
    }
}
