import XCTest
@testable import MurmurCore

final class HistoryStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var storeURL: URL { dir.appendingPathComponent("history.json") }

    // MARK: Append / order / cap

    @MainActor
    func testAppendInsertsNewestFirst() {
        let store = HistoryStore(storeURL: nil)
        store.append(mode: .dictate, text: "first")
        store.append(mode: .dictate, text: "second")
        XCTAssertEqual(store.records.map(\.text), ["second", "first"],
                       "index 0 must be the most recent dictation")
    }

    @MainActor
    func testAppendRecordsModeLabelAndWordCount() {
        let store = HistoryStore(storeURL: nil)
        store.append(mode: .dictate, text: "hello world")
        store.append(mode: .translate, text: "bonjour")
        store.append(mode: .ask, text: "the answer")
        XCTAssertEqual(store.records.map(\.mode), ["ask", "translate", "dictate"])
        XCTAssertEqual(store.records.map(\.wordCount), [2, 1, 2])
    }

    @MainActor
    func testCapDropsOldestAtTwoHundred() {
        let store = HistoryStore(storeURL: nil)
        for i in 1...(HistoryStore.capacity + 5) {
            store.append(mode: .dictate, text: "entry \(i)")
        }
        XCTAssertEqual(store.records.count, HistoryStore.capacity)
        XCTAssertEqual(store.records.first?.text, "entry 205", "newest survives")
        XCTAssertEqual(store.records.last?.text, "entry 6", "entries 1–5 dropped (oldest first)")
    }

    // MARK: Persistence

    @MainActor
    func testAppendPersistsAndReloads() {
        let store = HistoryStore(storeURL: storeURL)
        store.append(mode: .dictate, text: "persist me")
        store.append(mode: .translate, text: "moi aussi")

        let reloaded = HistoryStore(storeURL: storeURL)
        XCTAssertEqual(reloaded.records, store.records,
                       "a fresh store on the same URL sees identical records")
    }

    @MainActor
    func testClearEmptiesAndPersists() {
        let store = HistoryStore(storeURL: storeURL)
        store.append(mode: .dictate, text: "soon gone")
        store.clear()
        XCTAssertTrue(store.records.isEmpty)

        let reloaded = HistoryStore(storeURL: storeURL)
        XCTAssertTrue(reloaded.records.isEmpty, "the wipe must survive relaunch")
    }

    @MainActor
    func testMissingOrCorruptFileLoadsEmpty() throws {
        XCTAssertTrue(HistoryStore(storeURL: storeURL).records.isEmpty, "no file ⇒ empty")
        try Data("not json".utf8).write(to: storeURL)
        XCTAssertTrue(HistoryStore(storeURL: storeURL).records.isEmpty, "corrupt file ⇒ empty, no crash")
    }

    @MainActor
    func testNilStoreURLIsInMemoryOnly() {
        let store = HistoryStore(storeURL: nil)
        store.append(mode: .dictate, text: "ephemeral")
        XCTAssertEqual(store.records.count, 1, "nil URL still works in memory")
    }

    // MARK: Word counting (CJK-aware)

    func testWordCountLatin() {
        XCTAssertEqual(HistoryStore.wordCount(of: "hello world"), 2)
        XCTAssertEqual(HistoryStore.wordCount(of: "  spaced   out  "), 2)
        XCTAssertEqual(HistoryStore.wordCount(of: "one"), 1)
        XCTAssertEqual(HistoryStore.wordCount(of: ""), 0)
        XCTAssertEqual(HistoryStore.wordCount(of: "   "), 0)
    }

    func testWordCountCJKCharactersCountIndividually() {
        XCTAssertEqual(HistoryStore.wordCount(of: "今天開會"), 4,
                       "whitespace splitting would say 1 — each CJK char is a word")
        XCTAssertEqual(HistoryStore.wordCount(of: "今天 開會"), 4, "spacing must not change the count")
        XCTAssertEqual(HistoryStore.wordCount(of: "こんにちは"), 5, "kana counts per character too")
    }

    func testWordCountCodeMixed() {
        // The app's primary use case: CJK utterances with embedded Latin terms.
        XCTAssertEqual(HistoryStore.wordCount(of: "今天 deploy gbrain 到 prod"), 6,
                       "2 CJK + 3 Latin tokens + 1 CJK")
        XCTAssertEqual(HistoryStore.wordCount(of: "用gbrain開會"), 4,
                       "a CJK char terminates an abutting Latin token: 用 + gbrain + 開 + 會")
    }

    func testWordCountCJKPunctuationIsASeparator() {
        // CJK punctuation and fullwidth forms are separators, never tokens —
        // counting "。" as a word would inflate every Chinese sentence by one.
        XCTAssertEqual(HistoryStore.wordCount(of: "今天開會。"), 4,
                       "ideographic full stop must not count as a word")
        XCTAssertEqual(HistoryStore.wordCount(of: "跟 Bob 開會，下午三點"), 8,
                       "跟/Bob/開/會/下/午/三/點 — fullwidth comma separates, counts nothing")
    }

    func testWordCountPunctuationRidesItsToken() {
        // Punctuation is not whitespace and not CJK, so it rides the adjacent
        // token — matching how whitespace splitting treats "minutes."
        XCTAssertEqual(HistoryStore.wordCount(of: "I'll be there in 10 minutes."), 6)
    }

    // MARK: Stats

    func testEstMinutesSavedFormula() {
        // 600 words: 600/40 = 15 min typed, 600/150 = 4 min spoken ⇒ 11 saved.
        XCTAssertEqual(HistoryStore.estMinutesSaved(words: 600), 11.0, accuracy: 0.0001)
        XCTAssertEqual(HistoryStore.estMinutesSaved(words: 0), 0.0, "no words ⇒ nothing saved")
        XCTAssertGreaterThanOrEqual(HistoryStore.estMinutesSaved(words: 1), 0.0, "floored at 0")
    }

    @MainActor
    func testStatsAggregateAcrossRecords() {
        let store = HistoryStore(storeURL: nil)
        store.append(mode: .dictate, text: "hello world")          // 2 words
        store.append(mode: .translate, text: "今天 deploy gbrain") // 2 + 2 = 4 words
        let stats = store.stats
        XCTAssertEqual(stats.dictations, 2)
        XCTAssertEqual(stats.words, 6)
        XCTAssertEqual(stats.estMinutesSaved, HistoryStore.estMinutesSaved(words: 6))
    }

    @MainActor
    func testStatsEmptyStore() {
        let stats = HistoryStore(storeURL: nil).stats
        XCTAssertEqual(stats.dictations, 0)
        XCTAssertEqual(stats.words, 0)
        XCTAssertEqual(stats.estMinutesSaved, 0.0)
    }
}
