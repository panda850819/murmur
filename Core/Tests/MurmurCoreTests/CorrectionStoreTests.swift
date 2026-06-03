import XCTest
@testable import MurmurCore

private struct StubTermSource: TermSource {
    let terms: [Term]
    func load() -> [Term] { terms }
}

@MainActor
final class CorrectionStoreTests: XCTestCase {
    private func freshURL() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("murmur-store-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent("corrections.json")
    }

    private func makeStore(terms: [String] = [], url: URL?) -> CorrectionStore {
        CorrectionStore(
            termSource: StubTermSource(terms: terms.map(Term.init)),
            storeURL: url,
            isRealWord: { _ in false }   // deterministic; no host spell-checker
        )
    }

    override func tearDown() {
        super.tearDown()
    }

    func testCaptureAddsPairAndCorrects() {
        let store = makeStore(url: freshURL())
        XCTAssertTrue(store.captureCorrection(heard: "gbrand", intended: "gbrain"))
        XCTAssertEqual(store.pairs.count, 1)
        XCTAssertEqual(store.correct("the gbrand thing"), "the gbrain thing")
    }

    func testCaptureRejectsEmptyOrEqual() {
        let store = makeStore(url: freshURL())
        XCTAssertFalse(store.captureCorrection(heard: "  ", intended: "x"))
        XCTAssertFalse(store.captureCorrection(heard: "x", intended: ""))
        XCTAssertFalse(store.captureCorrection(heard: "Yei", intended: "yei"))  // equal, case-insensitive
        XCTAssertTrue(store.pairs.isEmpty)
    }

    func testCapturedIntendedAlsoFeedsFuzzyTerms() {
        // The captured `intended` ("Hermes") becomes a fuzzy term, so a *near*
        // mishearing ("hermies") is corrected even though only "xx"→"Hermes"
        // was taught.
        let store = makeStore(url: freshURL())
        XCTAssertTrue(store.captureCorrection(heard: "xx", intended: "Hermes"))
        XCTAssertEqual(store.correct("ask hermies about it"), "ask Hermes about it")
    }

    func testLastWinsPerHeard() {
        let store = makeStore(url: freshURL())
        XCTAssertTrue(store.captureCorrection(heard: "gbrand", intended: "gbrain"))
        XCTAssertTrue(store.captureCorrection(heard: "GBRAND", intended: "gBrain2"))
        XCTAssertEqual(store.pairs.count, 1, "same heard (case-insensitive) replaces, not appends")
        XCTAssertEqual(store.correct("gbrand"), "gBrain2")
    }

    func testGbrainTermsDriveCorrection() {
        let store = makeStore(terms: ["gbrain", "Sommet"], url: freshURL())
        XCTAssertEqual(store.correct("gbrand and sommet"), "gbrain and Sommet")
    }

    func testCapturedCasingBeatsStaleBakedCasing() {
        // gbrain baked a lowercase "hermes"; the user later taught "Hermes".
        // The captured (fresher) casing must win for near-misses too.
        let store = makeStore(terms: ["hermes"], url: freshURL())
        XCTAssertTrue(store.captureCorrection(heard: "zz", intended: "Hermes"))
        XCTAssertEqual(store.correct("ask hermies about it"), "ask Hermes about it")
    }

    func testUnwritablePathStillCorrectsInMemory() throws {
        // storeURL's parent is an existing regular FILE, so createDirectory in
        // persist() throws. The "best-effort, never crash" contract: capture
        // still succeeds and correction still applies this session.
        let blocker = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("murmur-blocker-\(UUID().uuidString)")
        try "x".write(to: blocker, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let store = makeStore(url: blocker.appendingPathComponent("nested/corrections.json"))
        XCTAssertTrue(store.captureCorrection(heard: "gbrand", intended: "gbrain"))
        XCTAssertEqual(store.correct("gbrand"), "gbrain")
    }

    func testPersistenceRoundTripAcrossInstances() {
        let url = freshURL()
        let first = makeStore(url: url)
        XCTAssertTrue(first.captureCorrection(heard: "gbrand", intended: "gbrain"))

        // A brand-new store at the same path must see the persisted corpus.
        let second = makeStore(url: url)
        XCTAssertEqual(second.pairs, [CorrectionPair(heard: "gbrand", intended: "gbrain")])
        XCTAssertEqual(second.correct("gbrand"), "gbrain")
    }

    func testNilStoreURLStillCorrectsInMemory() {
        let store = makeStore(url: nil)
        XCTAssertTrue(store.captureCorrection(heard: "gbrand", intended: "gbrain"))
        XCTAssertEqual(store.correct("gbrand"), "gbrain", "missing path must not break in-session correction")
    }

    func testLatinTokenSplitting() {
        XCTAssertEqual(
            CorrectionStore.latinTokens(in: "Sommet Labs 中文 v2 end"),
            ["Sommet", "Labs", "v", "end"]
        )
        XCTAssertTrue(CorrectionStore.latinTokens(in: "中文標點。").isEmpty)
    }
}
