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

    /// Groq LLM clean-up toggle (BRIEF MVP: optional, default on). Only takes
    /// effect when an `enhancer` is wired; see `canEnhance`.
    @Published public var enhanceEnabled: Bool = true

    private let recorder: any Recording
    private let transcriber: Transcriber
    private let paster: any Pasting
    private let enhancer: (any LLMEnhancing)?

    /// On-device proper-noun correction (A'). Applied to the raw transcript
    /// before enhance/paste. Settable so the SwiftUI layer can inject the shared
    /// `CorrectionStore` it also drives the capture UI (C) from. `nil` → the
    /// transcript passes through uncorrected.
    public var corrector: (any TextCorrecting)?

    /// True when an LLM enhancer is wired (i.e. a Groq key was present). The UI
    /// hides the clean-up toggle when this is false.
    public var canEnhance: Bool { enhancer != nil }

    public init(
        recorder: any Recording,
        transcriber: Transcriber,
        paster: any Pasting,
        enhancer: (any LLMEnhancing)? = nil,
        corrector: (any TextCorrecting)? = nil
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.paster = paster
        self.enhancer = enhancer
        self.corrector = corrector
    }

    public static func makeDefault() -> DictationCoordinator {
        #if os(macOS)
        let paster: any Pasting = ClipboardPaster()
        #else
        let paster: any Pasting = NoopPaster()
        #endif
        let enhancer: (any LLMEnhancing)? = GroqConfig.fromEnvironment().map {
            GroqClient(config: $0)
        }
        return DictationCoordinator(
            recorder: AudioRecorder(),
            transcriber: .makeDefault(),
            paster: paster,
            enhancer: enhancer
        )
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
            errorMessage = transcriber.lastError
            if errorMessage == nil, let rawTranscript = transcriber.transcript, !rawTranscript.isEmpty {
                // A': deterministic proper-noun correction. Runs on the raw
                // transcript BEFORE enhance, then AGAIN on the enhanced output —
                // Groq's cleanup ("fix capitalization … obvious slips") can
                // re-mangle a freshly-corrected coined name, so the deterministic
                // pass gets the last word. The prompt also asks Groq to leave
                // proper nouns alone, but that is best-effort; this second pass is
                // the hard guarantee. With enhance off (or no Groq key) it is an
                // idempotent no-op on already-correct text.
                // Capture the corrector once: `corrector` is a public var the
                // SwiftUI layer can swap, and there is an `await` (the enhance
                // hop) between the two A' passes. Binding it here guarantees A'
                // and B's glossary are sourced from the SAME instance for this
                // whole dictation, even if the property is reassigned mid-flight.
                let activeCorrector = corrector
                let corrected = activeCorrector?.correct(rawTranscript) ?? rawTranscript
                let cleaned = await enhanced(corrected, glossary: activeCorrector?.glossaryTerms ?? [])
                let text = activeCorrector?.correct(cleaned) ?? cleaned
                transcript = text
                if !paster.paste(text) {
                    errorMessage = "Couldn't auto-paste. Enable Accessibility for "
                        + "Murmur: System Settings ▸ Privacy & Security ▸ "
                        + "Accessibility. (Transcript is on the clipboard — ⌘V "
                        + "to paste manually.)"
                }
            } else {
                transcript = transcriber.transcript
            }
            phase = .idle
        }
    }

    /// Best-effort Groq clean-up. Returns the raw transcript unchanged when
    /// enhance is off, no enhancer is wired, the call throws, or the result is
    /// empty or trips the sanity filter. Enhance never blocks the paste.
    private func enhanced(_ raw: String, glossary: [String]) async -> String {
        guard enhanceEnabled, let enhancer else { return raw }
        // B': the LLM gets murmur's proper-noun glossary (passed in from the
        // caller's captured corrector so A' and B' share one source this
        // dictation). Empty ⇒ the enhancer falls back to the base prompt.
        do {
            let result = try await enhancer.enhance(raw, glossary: glossary)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty, SanityFilter.isClean(result) else { return raw }
            return result
        } catch {
            return raw
        }
    }

    /// Hotkey-cancel: the trigger turned into a real modifier chord
    /// (e.g. Right⌘+C) or was too brief to be intentional. Stop recording,
    /// drop the clip, no transcribe, no paste. No-op unless recording.
    public func cancel() async {
        guard phase == .recording else { return }
        _ = await recorder.stop()
        phase = .idle
    }
}
