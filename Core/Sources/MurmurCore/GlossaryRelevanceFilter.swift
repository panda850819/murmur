import Foundation

/// Utterance-relevance filter for the B' enhance glossary (pre-M6 privacy gate).
///
/// B' injects murmur's proper-noun glossary into the Groq enhance prompt so the
/// cloud pass has the right spellings as context. Sending the FULL glossary on
/// every call discloses every private entity murmur knows (people, holdings,
/// projects) to a third party even when the utterance names none of them. This
/// filter narrows the glossary to only the terms plausibly present in the
/// transcript, so an utterance that mentions no proper noun ships an empty
/// glossary — which `GroqClient.cleanupSystemPrompt` renders byte-identical to
/// the no-glossary base prompt. One filter collapses three axes: third-party
/// disclosure, prompt size, and the LLM's freedom to insert an unspoken name.
///
/// A term is kept when some Latin token in the transcript either:
///   - equals it (case-insensitive) — the name was actually spoken, or A' has
///     already canonicalized a misheard token to it; or
///   - is a fuzzy near-miss (within the length-scaled edit distance) AND is not
///     itself a real dictionary word.
///
/// The fuzzy arm reuses A's Damerau-Levenshtein and `editThreshold`, but scales
/// the tolerance by the SHORTER of token/term length. That clamp is the key
/// invariant: it keeps the filter no looser than A' (`ProperNounCorrector`,
/// which scales off the token length and floors fuzzy at 3 chars), so any token
/// the filter fuzzy-matches, A' would also have matched. A token or term shorter
/// than 3 chars therefore never fuzzy-matches (tolerance floors to 0) — only an
/// exact spoken match keeps such a term.
///
/// The real-word guard is the privacy brake. Without it, an ordinary English
/// word inside the fuzzy radius of a stored name would forward that private name
/// to the cloud even when no entity was spoken ("brain" → "gbrain", "summer" →
/// "Sommet"). So a token that is itself a dictionary word can only keep a term by
/// EXACT match (it was genuinely said), never by fuzzy proximity. This mirrors
/// A's own input guard: a real-word collision A' won't auto-correct on-device,
/// this filter won't disclose to the cloud either. The one-tap direct map (C) is
/// the escape hatch — once taught, A' rewrites the token to the canonical, which
/// then keeps the term by exact match.
///
/// Threat-model bound: the guard is `SystemDictionary.isRealWord` (NSSpellChecker),
/// whose verdict depends on the host's enabled spell-check languages. The
/// zero-disclosure guarantee therefore assumes the misheard form is a non-word to
/// the active dictionary; a foreign-language word within a term's fuzzy radius on
/// a host lacking that language can still slip. This is the same bound A' runs
/// under (it shares the guard); pinning murmur's own word list is a deferred
/// follow-up.
///
/// Fails CLOSED: a short, CJK-only, or token-poor transcript yields an empty
/// glossary (privacy-safe; A' still corrects names on-device).
enum GlossaryRelevanceFilter {
    /// The subset of `glossary` whose terms are present in `transcript` (exact)
    /// or a non-real-word fuzzy near-miss of some Latin token, preserving the
    /// glossary's first-seen order. `isRealWord` should be the SAME guard A' was
    /// built with so the layers stay consistent.
    static func relevant(
        transcript: String,
        glossary: [String],
        isRealWord: (String) -> Bool = SystemDictionary.isRealWord
    ) -> [String] {
        let tokens = CorrectionStore.latinTokens(in: transcript)
        guard !tokens.isEmpty else { return [] }   // fail closed: no Latin tokens
        let lowered = tokens.map { $0.lowercased() }
        return glossary.filter { term in
            let lower = term.lowercased()
            for (i, token) in lowered.enumerated() {
                // Exact (incl. an A'-canonicalized token): genuinely spoken and
                // already in the transcript text — always keep, any length.
                if token == lower { return true }
                // Fuzzy: only for a non-word token, tolerance clamped to the
                // shorter side so the filter stays no looser than A'. Guard the
                // original-case token, mirroring A's input guard.
                guard !isRealWord(tokens[i]) else { continue }
                let threshold = ProperNounCorrector.editThreshold(for: min(token.count, lower.count))
                guard threshold > 0 else { continue }   // either side < 3 ⇒ no fuzzy
                // |Δlength| is a lower bound on edit distance — skip the impossible.
                if abs(token.count - lower.count) > threshold { continue }
                if ProperNounCorrector.damerauLevenshtein(
                    token, lower, maxDistance: threshold
                ) <= threshold {
                    return true
                }
            }
            return false
        }
    }
}
