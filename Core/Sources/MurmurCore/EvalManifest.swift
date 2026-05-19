import Foundation

/// One eval clip: an Apple-device-native recording plus the verbatim
/// ground-truth of what was spoken. Recorded by a human (see
/// docs/eval/RECORDING-KIT.md); never synthesized.
public struct EvalClip: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    /// wav filename, relative to the manifest's own directory.
    public let file: String
    /// exactly what was spoken, verbatim.
    public let reference: String
    /// scoring unit: zh clips → .character (CER), en → .word.
    public let tokenization: Tokenization
    /// provenance only (e.g. "iphone-voicememo", "macbook-mic"); not scored.
    public let source: String
    public let notes: String?

    public init(
        id: String,
        file: String,
        reference: String,
        tokenization: Tokenization,
        source: String,
        notes: String? = nil
    ) {
        self.id = id
        self.file = file
        self.reference = reference
        self.tokenization = tokenization
        self.source = source
        self.notes = notes
    }
}

public struct EvalManifest: Codable, Sendable {
    public let clips: [EvalClip]

    public init(clips: [EvalClip]) { self.clips = clips }
}

/// The comparable release artifact: per-clip + aggregate WER for a model.
/// BRIEF Quality gate #1 = a new release's overall WER must not exceed
/// the previous baseline.
public struct EvalBaseline: Codable, Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public let id: String
        public let wer: Double
        public let referenceCount: Int

        public init(id: String, wer: Double, referenceCount: Int) {
            self.id = id
            self.wer = wer
            self.referenceCount = referenceCount
        }
    }

    public let model: String
    public let generatedAt: String
    public let overallWER: Double
    public let entries: [Entry]

    public init(
        model: String,
        generatedAt: String,
        overallWER: Double,
        entries: [Entry]
    ) {
        self.model = model
        self.generatedAt = generatedAt
        self.overallWER = overallWER
        self.entries = entries
    }
}
