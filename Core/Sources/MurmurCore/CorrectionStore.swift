import Foundation

/// Owns the on-device correction state and is the `TextCorrecting` seam the
/// coordinator runs the raw transcript through (A' + C).
///
/// Two data sources, one model:
///   - gbrain terms, loaded once from a `TermSource` (the A+B hybrid: a runtime
///     file overriding a baked snapshot). Read-only here.
///   - the user's captured {heard → intended} corpus (C), persisted to
///     `corrections.json` and grown one tap at a time. Each captured pair feeds
///     BOTH the exact direct-map AND the fuzzy term list (its `intended` value
///     split into Latin tokens), so a taught word also catches future
///     near-misses, not just the exact mishearing.
@MainActor
public final class CorrectionStore: ObservableObject, TextCorrecting {
    /// Captured corrections, newest last. Published so the capture UI can show
    /// how many are stored.
    @Published public private(set) var pairs: [CorrectionPair]

    private let gbrainTerms: [Term]
    private let storeURL: URL?
    private let isRealWord: (String) -> Bool
    private var corrector: ProperNounCorrector

    public init(
        termSource: TermSource,
        storeURL: URL?,
        isRealWord: @escaping (String) -> Bool = SystemDictionary.isRealWord
    ) {
        let terms = termSource.load()
        let loaded = Self.loadPairs(from: storeURL)
        self.gbrainTerms = terms
        self.storeURL = storeURL
        self.isRealWord = isRealWord
        self.pairs = loaded
        self.corrector = Self.makeCorrector(
            gbrainTerms: terms, pairs: loaded, isRealWord: isRealWord
        )
    }

    public func correct(_ text: String) -> String {
        corrector.correct(text)
    }

    /// Persist a one-tap correction (C). Trims both sides; a pair with an empty
    /// side, or where `heard` equals `intended` case-insensitively, is ignored
    /// and `false` is returned. Rebuilds the live corrector so the next
    /// dictation benefits immediately, then writes through to disk.
    @discardableResult
    public func captureCorrection(heard: String, intended: String) -> Bool {
        let h = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let i = intended.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !i.isEmpty, h.lowercased() != i.lowercased() else { return false }

        pairs.removeAll { $0.heard.lowercased() == h.lowercased() }  // last-wins per `heard`
        pairs.append(CorrectionPair(heard: h, intended: i))
        corrector = Self.makeCorrector(
            gbrainTerms: gbrainTerms, pairs: pairs, isRealWord: isRealWord
        )
        persist()
        return true
    }

    // MARK: - Dictionary assembly

    private static func makeCorrector(
        gbrainTerms: [Term],
        pairs: [CorrectionPair],
        isRealWord: @escaping (String) -> Bool
    ) -> ProperNounCorrector {
        let capturedTerms = pairs
            .flatMap { latinTokens(in: $0.intended) }
            .map(Term.init)
        // Captured terms FIRST: the corrector dedupes first-wins on a
        // case-insensitive collision, so the user's freshly-taught casing
        // ("Hermes") beats a stale baked one ("hermes"). Mirrors
        // CompositeTermSource's fresher-source-wins intent.
        let dictionary = CorrectionDictionary(
            terms: capturedTerms + gbrainTerms,
            directMappings: pairs
        )
        return ProperNounCorrector(dictionary: dictionary, isRealWord: isRealWord)
    }

    /// Maximal runs of ASCII letters. "Sommet Labs" → ["Sommet", "Labs"].
    static func latinTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        for ch in text {
            if ch.isLetter, ch.isASCII {
                token.append(ch)
            } else if !token.isEmpty {
                tokens.append(token)
                token = ""
            }
        }
        if !token.isEmpty { tokens.append(token) }
        return tokens
    }

    // MARK: - Persistence

    private static func loadPairs(from url: URL?) -> [CorrectionPair] {
        guard
            let url,
            let data = try? Data(contentsOf: url),
            let pairs = try? JSONDecoder().decode([CorrectionPair].self, from: data)
        else { return [] }
        return pairs
    }

    private func persist() {
        guard let storeURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(pairs)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // Persistence is best-effort: an unwritable corpus must not crash
            // dictation. The in-memory correction still applies this session.
        }
    }
}

public extension CorrectionStore {
    /// Default wiring (A+B hybrid): a runtime term file overriding a baked
    /// snapshot, the corrections corpus under Application Support, and the
    /// system spell-checker as the real-word guard.
    static func makeDefault() -> CorrectionStore {
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("Murmur", isDirectory: true)

        let termSource = CompositeTermSource([
            JSONTermSource(url: support?.appendingPathComponent("gbrain-terms.json")), // B: runtime, wins
            JSONTermSource.bundled(),                                                  // A: baked snapshot
        ])
        return CorrectionStore(
            termSource: termSource,
            storeURL: support?.appendingPathComponent("corrections.json")
        )
    }
}
