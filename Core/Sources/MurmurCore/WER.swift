import Foundation

/// Scoring unit for transcription error rate.
///
/// English (and other space-delimited languages) score per whitespace
/// token — classic WER. Chinese / CJK has no word boundaries, so the unit
/// is the character: this computes CER, the standard ASR metric for zh.
/// Per-clip `Tokenization` lets a mixed-language fixture set score each
/// clip with the right unit instead of one wrong global choice.
public enum Tokenization: String, Codable, Sendable {
    case word
    case character
}

/// Edit distance plus the reference length it is measured against.
public struct WERResult: Sendable, Equatable {
    public let distance: Int
    public let referenceCount: Int

    public init(distance: Int, referenceCount: Int) {
        self.distance = distance
        self.referenceCount = referenceCount
    }

    /// distance / reference tokens. 0 = perfect. Can exceed 1 when the
    /// hypothesis is much longer than the reference (insertions).
    public var rate: Double {
        if referenceCount == 0 { return distance == 0 ? 0 : 1 }
        return Double(distance) / Double(referenceCount)
    }
}

public enum WER {
    /// Lowercase, drop punctuation + symbols (CJK included), collapse
    /// whitespace. Keeps refs/hyps comparable without penalizing casing
    /// or punctuation the speaker never voiced.
    public static func normalize(_ s: String) -> String {
        let cleaned = s.lowercased().unicodeScalars
            .filter {
                !CharacterSet.punctuationCharacters.contains($0)
                    && !CharacterSet.symbols.contains($0)
            }
            .map(Character.init)
        return String(cleaned)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    public static func tokens(_ s: String, _ mode: Tokenization) -> [String] {
        let n = normalize(s)
        switch mode {
        case .word:
            return n.split(separator: " ").map(String.init)
        case .character:
            return n.filter { !$0.isWhitespace }.map(String.init)
        }
    }

    /// Levenshtein over token arrays. O(ref*hyp) time, O(hyp) space.
    public static func score(
        reference: String,
        hypothesis: String,
        mode: Tokenization
    ) -> WERResult {
        let ref = tokens(reference, mode)
        let hyp = tokens(hypothesis, mode)
        if ref.isEmpty { return WERResult(distance: hyp.count, referenceCount: 0) }
        if hyp.isEmpty { return WERResult(distance: ref.count, referenceCount: ref.count) }

        var prev = Array(0...hyp.count)
        var curr = [Int](repeating: 0, count: hyp.count + 1)
        for i in 1...ref.count {
            curr[0] = i
            for j in 1...hyp.count {
                let cost = ref[i - 1] == hyp[j - 1] ? 0 : 1
                curr[j] = Swift.min(
                    prev[j] + 1,
                    Swift.min(curr[j - 1] + 1, prev[j - 1] + cost)
                )
            }
            swap(&prev, &curr)
        }
        return WERResult(distance: prev[hyp.count], referenceCount: ref.count)
    }
}
