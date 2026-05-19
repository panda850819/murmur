import XCTest
@testable import MurmurCore

/// Deterministic — no model, no audio. These pin the scoring math so a
/// later regression in normalization/edit-distance is caught for free.
final class WERTests: XCTestCase {
    func testIdenticalIsZero() {
        let r = WER.score(reference: "hello world", hypothesis: "hello world", mode: .word)
        XCTAssertEqual(r.rate, 0)
    }

    func testCaseAndPunctuationNormalizedAway() {
        let r = WER.score(
            reference: "Hello, World!",
            hypothesis: "hello world",
            mode: .word
        )
        XCTAssertEqual(r.rate, 0)
    }

    func testOneWordSubstitution() {
        let r = WER.score(
            reference: "the quick brown fox",
            hypothesis: "the slow brown fox",
            mode: .word
        )
        XCTAssertEqual(r.distance, 1)
        XCTAssertEqual(r.referenceCount, 4)
        XCTAssertEqual(r.rate, 0.25, accuracy: 1e-9)
    }

    func testChineseUsesCharacterCER() {
        // 1 of 6 characters wrong → CER 1/6. Whitespace WER would be 1/1
        // (no spaces), which is why zh must score per character.
        let r = WER.score(
            reference: "今天天氣很好",
            hypothesis: "今天天氣不好",
            mode: .character
        )
        XCTAssertEqual(r.distance, 1)
        XCTAssertEqual(r.referenceCount, 6)
        XCTAssertEqual(r.rate, 1.0 / 6.0, accuracy: 1e-9)
    }

    func testEmptyHypothesisIsFullError() {
        let r = WER.score(reference: "今天天氣", hypothesis: "", mode: .character)
        XCTAssertEqual(r.distance, 4)
        XCTAssertEqual(r.referenceCount, 4)
        XCTAssertEqual(r.rate, 1.0, accuracy: 1e-9)
    }

    func testEmptyReferenceWithSpuriousHypothesis() {
        let r = WER.score(reference: "", hypothesis: "noise noise", mode: .word)
        XCTAssertEqual(r.referenceCount, 0)
        XCTAssertEqual(r.rate, 1)
    }

    func testManifestCodableRoundTrip() throws {
        let m = EvalManifest(clips: [
            EvalClip(
                id: "zh-short-01",
                file: "zh-short-01.wav",
                reference: "今天天氣很好",
                tokenization: .character,
                source: "iphone-voicememo",
                notes: "Bug #1 case: short Chinese clip"
            )
        ])
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(EvalManifest.self, from: data)
        XCTAssertEqual(back.clips.first?.tokenization, .character)
        XCTAssertEqual(back.clips.first?.id, "zh-short-01")
    }
}
