import XCTest
@testable import MurmurCore

final class SanityFilterTests: XCTestCase {
    func testPlainEnglishPasses() {
        XCTAssertTrue(SanityFilter.isClean("I'll be there in about 10 minutes."))
    }

    func testTraditionalChinesePasses() {
        XCTAssertTrue(SanityFilter.isClean("我大約 10 分鐘後就到。"))
    }

    func testDigitsAndCommonPunctuationPass() {
        XCTAssertTrue(SanityFilter.isClean("Item #1: $4.50 (50% off) — wait, no dash; use 2*3=6!"))
    }

    func testNewlinesAndTabsPass() {
        XCTAssertTrue(SanityFilter.isClean("line one\nline two\tindented\r\n"))
    }

    func testEmojiRejected() {
        XCTAssertFalse(SanityFilter.isClean("great work 🎉"))
        XCTAssertEqual(SanityFilter.firstViolation(in: "ok 👍")?.value, 0x1F44D)
    }

    func testBoxDrawingRejected() {
        XCTAssertFalse(SanityFilter.isClean("┌──────┐"))
    }

    func testBlockElementsRejected() {
        XCTAssertFalse(SanityFilter.isClean("progress ▰▰▱▱"))
    }

    func testDingbatsRejected() {
        XCTAssertFalse(SanityFilter.isClean("check ✓ then ✗"))
    }

    func testControlCharacterRejected() {
        XCTAssertFalse(SanityFilter.isClean("bell\u{0007}here"))
    }

    func testVariationSelectorRejected() {
        // Heart + emoji variation selector → emoji presentation.
        XCTAssertFalse(SanityFilter.isClean("love \u{2764}\u{FE0F}"))
    }

    func testZeroWidthJoinerRejected() {
        XCTAssertFalse(SanityFilter.isClean("a\u{200D}b"))
    }

    func testEmptyStringIsClean() {
        XCTAssertTrue(SanityFilter.isClean(""))
        XCTAssertNil(SanityFilter.firstViolation(in: ""))
    }
}
