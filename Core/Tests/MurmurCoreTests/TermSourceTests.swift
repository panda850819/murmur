import XCTest
@testable import MurmurCore

final class TermSourceTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("murmur-termsrc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func writeJSON(_ contents: String, _ name: String) -> URL {
        let url = tmp.appendingPathComponent(name)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testLoadsTermsFromValidFile() {
        let url = writeJSON(#"{"version":1,"terms":["gbrain","Yei","Sommet"]}"#, "a.json")
        XCTAssertEqual(
            JSONTermSource(url: url).load(),
            [Term("gbrain"), Term("Yei"), Term("Sommet")]
        )
    }

    func testTrimsAndDropsBlankTerms() {
        let url = writeJSON(#"{"version":1,"terms":["  gbrain  ","","   ","Yei"]}"#, "b.json")
        XCTAssertEqual(JSONTermSource(url: url).load(), [Term("gbrain"), Term("Yei")])
    }

    func testNilURLYieldsEmpty() {
        XCTAssertTrue(JSONTermSource(url: nil).load().isEmpty)
    }

    func testMissingFileYieldsEmpty() {
        let url = tmp.appendingPathComponent("does-not-exist.json")
        XCTAssertTrue(JSONTermSource(url: url).load().isEmpty)
    }

    func testMalformedJSONYieldsEmpty() {
        let url = writeJSON("{ not valid json", "c.json")
        XCTAssertTrue(JSONTermSource(url: url).load().isEmpty)
    }

    func testCompositeUnionsWithFirstSourceWinningOnCollision() {
        // Runtime file (first) overrides the bundled snapshot's casing on a
        // case-insensitive collision, while snapshot-only terms still survive.
        let runtime = writeJSON(#"{"version":1,"terms":["YEI","gbrain"]}"#, "runtime.json")
        let bundled = writeJSON(#"{"version":1,"terms":["yei","Sommet"]}"#, "bundled.json")
        let composite = CompositeTermSource([
            JSONTermSource(url: runtime),
            JSONTermSource(url: bundled),
        ])
        let loaded = composite.load()
        XCTAssertEqual(loaded, [Term("YEI"), Term("gbrain"), Term("Sommet")])
        XCTAssertFalse(loaded.contains(Term("yei")), "lowercase dup must be dropped")
    }

    func testCompositeWithAllEmptySourcesIsEmpty() {
        let composite = CompositeTermSource([
            JSONTermSource(url: nil),
            JSONTermSource(url: tmp.appendingPathComponent("nope.json")),
        ])
        XCTAssertTrue(composite.load().isEmpty)
    }
}
