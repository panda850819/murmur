import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// Deterministic, on-device proper-noun correction (A'). Runs a token-level
/// pass over the raw transcript:
///
///   1. exact, case-insensitive direct-map replacement (user-confirmed pairs)
///   2. canonical-casing fix for a token that already matches a term ("yei" → "Yei")
///   3. fuzzy (Damerau-Levenshtein) replacement of an unknown token that is a
///      near-miss for a known term ("gbrand" → "gbrain")
///
/// No cloud, no leak, no sentence rewrite: only whole Latin-script word tokens
/// are ever touched; whitespace, punctuation, digits, and CJK pass through
/// untouched. Over-correction is bounded by (a) a real-word guard, (b) a
/// minimum token length, and (c) a length-scaled edit-distance threshold.
///
/// A value type with no I/O — fully unit-testable by injecting `isRealWord`.
public struct ProperNounCorrector {
    /// lowercased `heard` → `intended` (exact, user-confirmed).
    private let directMap: [String: String]
    /// lowercased canonical → canonical (casing fix + fuzzy targets).
    private let termByLower: [String: String]
    /// Canonicals in first-seen order, for deterministic fuzzy tie-breaks.
    private let terms: [String]
    private let isRealWord: (String) -> Bool
    private let minFuzzyLength: Int

    public init(
        dictionary: CorrectionDictionary,
        minFuzzyLength: Int = 3,
        isRealWord: @escaping (String) -> Bool = { _ in false }
    ) {
        var direct: [String: String] = [:]
        for pair in dictionary.directMappings {
            let key = pair.heard.lowercased()
            guard !key.isEmpty else { continue }
            direct[key] = pair.intended      // last-wins on duplicate `heard`
        }
        self.directMap = direct

        var byLower: [String: String] = [:]
        var order: [String] = []
        for term in dictionary.terms {
            let canonical = term.canonical
            let lower = canonical.lowercased()
            guard !lower.isEmpty, byLower[lower] == nil else { continue }
            byLower[lower] = canonical
            order.append(canonical)
        }
        self.termByLower = byLower
        self.terms = order
        self.isRealWord = isRealWord
        self.minFuzzyLength = max(1, minFuzzyLength)
    }

    /// Correct every Latin-script word token in `text`, preserving all other
    /// characters (spacing, punctuation, digits, CJK) exactly.
    ///
    /// Call on the main actor when the default `SystemDictionary.isRealWord`
    /// guard is wired: it reaches `NSSpellChecker.shared`, which is main-thread
    /// AppKit. The shipping path satisfies this (the coordinator is
    /// `@MainActor`); a future off-main caller must inject its own `isRealWord`.
    public func correct(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var token = ""
        for ch in text {
            if ch.isLetter, ch.isASCII {
                token.append(ch)
            } else {
                if !token.isEmpty { result += corrected(token: token); token = "" }
                result.append(ch)
            }
        }
        if !token.isEmpty { result += corrected(token: token) }
        return result
    }

    private func corrected(token: String) -> String {
        let lower = token.lowercased()

        // 1. Direct map — exact, user-confirmed. Highest confidence, no guards:
        //    the user explicitly taught this replacement.
        if let intended = directMap[lower] { return intended }

        // Real words are never re-cased or fuzzy-matched. A term list sourced
        // from entity names inevitably contains generic words ("group",
        // "media", "capital"); imposing proper-noun casing on a real word the
        // speaker used as itself is over-correction. Guard the INPUT token only
        // — a misheard non-word ("hermies") still corrects toward a real-word
        // term ("Hermes"), because the guard fires on what was heard.
        guard !isRealWord(token) else { return token }

        // 2. Token already IS a (coined) term — normalize to canonical casing
        //    ("yei" → "Yei"). An exact match is intentional, not a near-miss.
        if let canonical = termByLower[lower] { return canonical }

        // 3. Fuzzy — only unknown, long-enough tokens. `editThreshold(..<3)==0`
        //    is the real floor; `minFuzzyLength` is the explicit knob on top.
        guard token.count >= minFuzzyLength else { return token }
        let threshold = Self.editThreshold(for: token.count)
        guard threshold > 0 else { return token }

        var bestTerm: String?
        var bestDist = Int.max
        for term in terms {
            let lowerTerm = term.lowercased()
            // |Δlength| is a lower bound on edit distance — skip the impossible.
            if abs(lowerTerm.count - lower.count) > threshold { continue }
            let d = Self.damerauLevenshtein(lower, lowerTerm, maxDistance: threshold)
            if d <= threshold, d < bestDist {
                bestDist = d
                bestTerm = term
                if d == 1 { break }  // best achievable at this scale; take it
            }
        }
        return bestTerm ?? token
    }

    /// Length-scaled tolerance: short coined tokens get 1 edit, longer ones 2.
    /// Tokens under 3 chars are never fuzzy-corrected (too ambiguous).
    static func editThreshold(for length: Int) -> Int {
        switch length {
        case ..<3: return 0
        case 3...5: return 1
        default: return 2
        }
    }

    /// Damerau-Levenshtein (optimal string alignment) with early-exit once the
    /// running row minimum exceeds `maxDistance`. OSA — which counts a single
    /// adjacent transposition as one edit — is enough here; adjacent swaps are
    /// a common slip ("hermies" → "hermes"). Operates on `Character`s.
    static func damerauLevenshtein(_ a: String, _ b: String, maxDistance: Int = .max) -> Int {
        let s = Array(a), t = Array(b)
        let n = s.count, m = t.count
        if n == 0 { return m }
        if m == 0 { return n }

        var prev2 = [Int](repeating: 0, count: m + 1)   // row i-2
        var prev = [Int](repeating: 0, count: m + 1)    // row i-1
        var curr = [Int](repeating: 0, count: m + 1)    // row i
        for j in 0...m { prev[j] = j }

        for i in 1...n {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...m {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                var v = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    v = min(v, prev2[j - 2] + 1)        // adjacent transposition
                }
                curr[j] = v
                if v < rowMin { rowMin = v }
            }
            if rowMin > maxDistance { return rowMin }   // can only grow — bail
            swap(&prev2, &prev)                          // rotate: prev2←prev,
            swap(&prev, &curr)                           // prev←curr, curr←free
        }
        return prev[m]
    }
}

/// System spell-checker bridge — the real-word guard for the fuzzy pass.
///
/// macOS only (NSSpellChecker). Other platforms report `false` (no token is
/// "real"), which is acceptable: the closed term list and the edit-distance
/// threshold still bound what the matcher will touch.
public enum SystemDictionary {
    public static func isRealWord(_ word: String) -> Bool {
        #if canImport(AppKit)
        guard !word.isEmpty else { return false }
        let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
        return range.location == NSNotFound  // nothing flagged ⇒ a real word
        #else
        return false
        #endif
    }
}
