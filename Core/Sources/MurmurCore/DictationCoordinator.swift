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

    /// 翻譯 mode's output language (M3a). Settable so the SwiftUI layer can
    /// bind it to the target-language Picker.
    @Published public var targetLanguage: String = "English (US)"

    private let recorder: any Recording
    private let transcriber: Transcriber
    private let paster: any Pasting
    private let enhancer: (any LLMEnhancing)?
    private let chatter: (any LLMChatting)?

    /// On-device proper-noun correction (A'). Applied to the raw transcript
    /// before enhance/paste. Settable so the SwiftUI layer can inject the shared
    /// `CorrectionStore` it also drives the capture UI (C) from. `nil` → the
    /// transcript passes through uncorrected.
    public var corrector: (any TextCorrecting)?

    /// Ask-mode's view of "what's selected right now". Settable so the app
    /// layer can inject the AX-backed reader. `nil` → questions are answered
    /// without reference text.
    public var selectionReader: (any SelectionReading)?

    /// True when an LLM enhancer is wired (i.e. a Groq key was present). The UI
    /// hides the clean-up toggle when this is false.
    public var canEnhance: Bool { enhancer != nil }

    /// True when translate/ask are wired (same Groq-key signal as `canEnhance`,
    /// but through the chat seam). The UI dims the chord hints when false.
    public var canChat: Bool { chatter != nil }

    public init(
        recorder: any Recording,
        transcriber: Transcriber,
        paster: any Pasting,
        enhancer: (any LLMEnhancing)? = nil,
        chatter: (any LLMChatting)? = nil,
        corrector: (any TextCorrecting)? = nil
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.paster = paster
        self.enhancer = enhancer
        self.chatter = chatter
        self.corrector = corrector
    }

    public static func makeDefault() -> DictationCoordinator {
        #if os(macOS)
        let paster: any Pasting = ClipboardPaster()
        #else
        let paster: any Pasting = NoopPaster()
        #endif
        // One client behind both seams so enhance and translate/ask share the
        // connection config (and a future self-hosted swap is one edit).
        let groq = GroqConfig.fromEnvironment().map { GroqClient(config: $0) }
        return DictationCoordinator(
            recorder: AudioRecorder(),
            transcriber: .makeDefault(),
            paster: paster,
            enhancer: groq,
            chatter: groq
        )
    }

    /// Idle → start recording. Recording → stop, then transcribe the WAV and
    /// run the `mode` flow (dictate / translate / ask) on the transcript.
    /// `mode` only matters on the stopping call — the chord is resolved by the
    /// hotkey monitor at release (a mid-hold `/` upgrades dictate → ask).
    /// Taps during transcription are ignored.
    public func toggle(mode: DictationMode = .dictate) async {
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
                let output: String?
                switch mode {
                case .dictate:
                    let cleaned = await enhanced(
                        corrected,
                        glossary: activeCorrector?.glossaryTerms ?? [],
                        isRealWord: activeCorrector?.isRealWord ?? { _ in false }
                    )
                    output = activeCorrector?.correct(cleaned) ?? cleaned
                case .translate:
                    output = await translated(
                        corrected,
                        glossary: activeCorrector?.glossaryTerms ?? [],
                        isRealWord: activeCorrector?.isRealWord ?? { _ in false }
                    )
                case .ask:
                    output = await answered(corrected)
                }
                if let text = output {
                    transcript = text
                    if !paster.paste(text) {
                        errorMessage = "Couldn't auto-paste. Enable Accessibility for "
                            + "Murmur: System Settings ▸ Privacy & Security ▸ "
                            + "Accessibility. (Transcript is on the clipboard — ⌘V "
                            + "to paste manually.)"
                    }
                } else {
                    // Ask failed — show the question, paste nothing (an answer
                    // didn't happen; the question is not a substitute).
                    transcript = corrected
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
    private func enhanced(_ raw: String, glossary: [String], isRealWord: (String) -> Bool) async -> String {
        guard enhanceEnabled, let enhancer else { return raw }
        // B': the LLM gets murmur's proper-noun glossary (passed in from the
        // caller's captured corrector so A' and B' share one source this
        // dictation), narrowed to only the terms actually named in THIS utterance
        // so entities the speaker never said are never disclosed to the cloud
        // (pre-M6 privacy gate). `raw` is already the A'-corrected transcript,
        // the right match target; `isRealWord` is A's own guard, reused so the
        // filter agrees with A' on which tokens are ordinary words. An empty
        // result ⇒ the enhancer falls back to the base prompt, byte-identical to
        // no-glossary.
        let relevant = GlossaryRelevanceFilter.relevant(
            transcript: raw, glossary: glossary, isRealWord: isRealWord
        )
        do {
            let result = try await enhancer.enhance(raw, glossary: relevant)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty, SanityFilter.isClean(result) else { return raw }
            return result
        } catch {
            return raw
        }
    }

    /// 翻譯 mode. Degrades to the (A'-corrected) source transcript when no
    /// chatter is wired, the call throws, or the result is empty/unsane —
    /// the user's words still land in the document, with an error note saying
    /// they landed untranslated. Never returns nil: translate always pastes.
    private func translated(_ source: String, glossary: [String], isRealWord: (String) -> Bool) async -> String {
        guard let chatter else {
            errorMessage = "Translate needs a Groq key (GROQ_API_KEY). Pasted the raw transcript."
            return source
        }
        // Same B' privacy gate as enhance: only utterance-relevant proper
        // nouns ride along to keep their spellings across the language hop.
        let relevant = GlossaryRelevanceFilter.relevant(
            transcript: source, glossary: glossary, isRealWord: isRealWord
        )
        do {
            let result = try await chatter.translate(source, to: targetLanguage, glossary: relevant)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty, SanityFilter.isClean(result) else {
                errorMessage = "Translation came back malformed — pasted the raw transcript."
                return source
            }
            return result
        } catch {
            errorMessage = "Translation failed — pasted the raw transcript."
            return source
        }
    }

    /// 詢問 mode. Returns the answer to paste, or nil on failure — unlike
    /// translate there is no useful degraded output (pasting the question
    /// where an answer was expected is worse than pasting nothing).
    private func answered(_ question: String) async -> String? {
        guard let chatter else {
            errorMessage = "Ask needs a Groq key (GROQ_API_KEY)."
            return nil
        }
        let selection = selectionReader?.selectedText()
        do {
            let result = try await chatter.answer(question, about: selection)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty, SanityFilter.isClean(result) else {
                errorMessage = "Answer came back malformed."
                return nil
            }
            return result
        } catch {
            errorMessage = "Ask failed — check the network and try again."
            return nil
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
