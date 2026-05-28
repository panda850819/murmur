import XCTest
@testable import MurmurCore

/// Deterministic — no model, no audio. The eval harness is a no-op for this
/// pass on the current fixtures (base already emits Traditional), so these
/// tests are the proof that the conversion fires and is correctly gated; the
/// eval gate only proves it does not regress correct Chinese output.
final class ScriptNormalizerTests: XCTestCase {
    // MARK: gated normalize(_:language:) — the path the transcriber uses

    func testChineseIsConverted() {
        XCTAssertEqual(ScriptNormalizer.normalize("点开会吃饭", language: "zh"), "點開會吃飯")
    }

    /// Regression guard: detectLanguage:true also yields ja/ko, whose kanji
    /// must NOT be Hans→Hant rewritten. This is a real gate test, not
    /// incidentally true: 会→會 DOES transform, so removing the gate (calling
    /// toTraditional unconditionally) would turn this input into 東京で會議…
    /// and fail the assertion.
    func testJapaneseIsPreserved() {
        let ja = "東京で会議をします"
        XCTAssertEqual(ScriptNormalizer.normalize(ja, language: "ja"), ja)
    }

    /// Cantonese (yue) is written Chinese — a Traditional writer wants it
    /// Traditional too, so it IS normalized (unlike ja/ko).
    func testCantoneseIsConverted() {
        XCTAssertEqual(ScriptNormalizer.normalize("点开会", language: "yue"), "點開會")
    }

    func testNonChineseLanguageIsUntouched() {
        // Even Han-looking text is left alone when the detected language isn't Chinese.
        XCTAssertEqual(ScriptNormalizer.normalize("点开会", language: "en"), "点开会")
    }

    // MARK: toTraditional — pure unconditional conversion

    func testSimplifiedBecomesTraditional() {
        XCTAssertEqual(ScriptNormalizer.toTraditional("点开会吃饭"), "點開會吃飯")
    }

    func testTraditionalIsUnchanged() {
        let trad = "今天天氣不錯 五點半開會 訊息傳出去了"
        XCTAssertEqual(ScriptNormalizer.toTraditional(trad), trad)
    }

    /// Locks in the verified ICU behavior on one-to-many ambiguous chars:
    /// it resolves them by context rather than mangling correct Traditional.
    func testAmbiguousOneToManyResolvesCorrectly() {
        XCTAssertEqual(ScriptNormalizer.toTraditional("干杯"), "乾杯")
        XCTAssertEqual(ScriptNormalizer.toTraditional("面条"), "麵條")
        XCTAssertEqual(ScriptNormalizer.toTraditional("头发"), "頭髮")
        XCTAssertEqual(ScriptNormalizer.toTraditional("皇后"), "皇后") // empress, not 皇後
    }

    func testIdempotent() {
        let once = ScriptNormalizer.toTraditional("头发干净皇后")
        XCTAssertEqual(ScriptNormalizer.toTraditional(once), once)
    }

    func testAsciiAndNumeralsUntouched() {
        let mixed = "這個 PR 我等等 review 完再 merge 進 main"
        XCTAssertEqual(ScriptNormalizer.toTraditional(mixed), mixed)
        XCTAssertEqual(ScriptNormalizer.toTraditional("下午3點 5.5開會"), "下午3點 5.5開會")
    }
}
