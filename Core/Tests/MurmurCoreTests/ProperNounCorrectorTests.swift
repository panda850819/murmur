import XCTest
@testable import MurmurCore

final class ProperNounCorrectorTests: XCTestCase {
    /// Builds a corrector with an explicit term/mapping set and a controlled
    /// real-word predicate, so tests never depend on the host spell-checker.
    private func makeCorrector(
        terms: [String] = [],
        mappings: [(String, String)] = [],
        realWords: Set<String> = []
    ) -> ProperNounCorrector {
        let dict = CorrectionDictionary(
            terms: terms.map(Term.init),
            directMappings: mappings.map { CorrectionPair(heard: $0.0, intended: $0.1) }
        )
        return ProperNounCorrector(dictionary: dict) { realWords.contains($0.lowercased()) }
    }

    // MARK: Pass-through

    func testEmptyStringUnchanged() {
        XCTAssertEqual(makeCorrector(terms: ["gbrain"]).correct(""), "")
    }

    func testNoDictionaryIsIdentity() {
        let c = ProperNounCorrector(dictionary: .empty)
        XCTAssertEqual(c.correct("hello gbrand world"), "hello gbrand world")
    }

    func testPunctuationDigitsAndCJKPreserved() {
        let c = makeCorrector(terms: ["gbrain"])
        // gbrand → gbrain, but the surrounding "我用 ... 跟 3 個 tool。" stays exact.
        XCTAssertEqual(c.correct("我用 gbrand 跟 3 個 tool。"), "我用 gbrain 跟 3 個 tool。")
    }

    // MARK: Direct map (C, user-confirmed)

    func testDirectMapExactReplacement() {
        let c = makeCorrector(mappings: [("gbrand", "gbrain")])
        XCTAssertEqual(c.correct("the gbrand thing"), "the gbrain thing")
    }

    func testDirectMapIsCaseInsensitiveOnHeard() {
        let c = makeCorrector(mappings: [("gbrand", "gbrain")])
        XCTAssertEqual(c.correct("GBRAND and Gbrand"), "gbrain and gbrain")
    }

    func testDirectMapFiresEvenForRealWords() {
        // User explicitly taught it: confidence overrides the real-word guard.
        let c = makeCorrector(mappings: [("brand", "Bond")], realWords: ["brand"])
        XCTAssertEqual(c.correct("the brand"), "the Bond")
    }

    func testDirectMapWinsOverFuzzy() {
        let c = makeCorrector(terms: ["gbrain"], mappings: [("gbrand", "GBRAIN-X")])
        XCTAssertEqual(c.correct("gbrand"), "GBRAIN-X")
    }

    // MARK: Casing normalization (exact term, coined)

    func testCoinedTermGetsCanonicalCasing() {
        let c = makeCorrector(terms: ["Yei", "Sommet"])
        XCTAssertEqual(c.correct("i use yei and SOMMET"), "i use Yei and Sommet")
    }

    func testRealWordIsNotRecasedTowardTerm() {
        // "media" is a real word the speaker used as itself; a term "Media"
        // must NOT force capitalization. This is the over-correction guard.
        let c = makeCorrector(terms: ["Media"], realWords: ["media"])
        XCTAssertEqual(c.correct("social media reach"), "social media reach")
    }

    // MARK: Fuzzy (A', edit-distance)

    func testFuzzyCorrectsNearMiss() {
        let c = makeCorrector(terms: ["gbrain"])
        XCTAssertEqual(c.correct("gbrand"), "gbrain")          // distance 2, len 6
    }

    func testFuzzyCorrectsTransposition() {
        let c = makeCorrector(terms: ["Hermes"])
        XCTAssertEqual(c.correct("hermies"), "Hermes")         // distance 1
    }

    func testFuzzyCorrectsSingleSubstitution() {
        let c = makeCorrector(terms: ["Anthropic"])
        XCTAssertEqual(c.correct("anthropik"), "Anthropic")
    }

    func testFuzzyLeavesFarTokensAlone() {
        let c = makeCorrector(terms: ["gbrain"])
        XCTAssertEqual(c.correct("keyboard"), "keyboard")      // far beyond threshold
    }

    func testRealWordTokenNeverFuzzyCorrected() {
        // "brand" is real; even though it's close to "gbrain", leave it.
        let c = makeCorrector(terms: ["gbrain"], realWords: ["brand"])
        XCTAssertEqual(c.correct("the brand new thing"), "the brand new thing")
    }

    func testShortTokensAreNotFuzzyCorrected() {
        // 2-char token below minFuzzyLength: never fuzzy-matched.
        let c = makeCorrector(terms: ["Go"])
        XCTAssertEqual(c.correct("gx"), "gx")
    }

    func testNearestTermWins() {
        let c = makeCorrector(terms: ["Morpho", "Murmur"])
        XCTAssertEqual(c.correct("murmer"), "Murmur")          // 1 from Murmur, far from Morpho
    }

    func testMultipleTokensCorrectedIndependently() {
        let c = makeCorrector(terms: ["gbrain", "Yei"], mappings: [("sumit", "Sommet")])
        XCTAssertEqual(
            c.correct("gbrand plus yei plus sumit"),
            "gbrain plus Yei plus Sommet"
        )
    }

    func testFuzzyTieBreakFavorsFirstDeclaredTerm() {
        // Two terms equidistant (1 edit) from "talk": the FIRST in declaration
        // order wins. Pins the documented "first-seen order" tie contract so a
        // future reorder/dedup-via-Set refactor can't silently flip the winner.
        let first = makeCorrector(terms: ["Talq", "Talx"])
        XCTAssertEqual(first.correct("talk"), "Talq")
        let swapped = makeCorrector(terms: ["Talx", "Talq"])
        XCTAssertEqual(swapped.correct("talk"), "Talx")
    }

    // MARK: Distance + threshold primitives

    func testDamerauLevenshteinBasics() {
        XCTAssertEqual(ProperNounCorrector.damerauLevenshtein("abc", "abc"), 0)
        XCTAssertEqual(ProperNounCorrector.damerauLevenshtein("", "abc"), 3)
        XCTAssertEqual(ProperNounCorrector.damerauLevenshtein("abc", ""), 3)
        XCTAssertEqual(ProperNounCorrector.damerauLevenshtein("ab", "ba"), 1)   // transposition
        XCTAssertEqual(ProperNounCorrector.damerauLevenshtein("gbrand", "gbrain"), 2)
        XCTAssertEqual(ProperNounCorrector.damerauLevenshtein("hermies", "hermes"), 1)
    }

    func testDamerauLevenshteinEarlyExitBoundsResult() {
        // With a max of 1, an actual distance of 2 must report > 1 (not a false low).
        XCTAssertGreaterThan(
            ProperNounCorrector.damerauLevenshtein("gbrand", "gbrain", maxDistance: 1), 1
        )
    }

    func testEditThresholdScaling() {
        XCTAssertEqual(ProperNounCorrector.editThreshold(for: 2), 0)
        XCTAssertEqual(ProperNounCorrector.editThreshold(for: 3), 1)
        XCTAssertEqual(ProperNounCorrector.editThreshold(for: 5), 1)
        XCTAssertEqual(ProperNounCorrector.editThreshold(for: 6), 2)
        XCTAssertEqual(ProperNounCorrector.editThreshold(for: 12), 2)
    }
}
