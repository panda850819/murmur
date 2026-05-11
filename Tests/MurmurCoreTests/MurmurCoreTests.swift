import XCTest
@testable import MurmurCore

final class MurmurCoreTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(Murmur.version.isEmpty)
    }

    func testWhisperKitSymbolReachable() {
        XCTAssertFalse(Murmur.whisperKitReachable().isEmpty)
    }
}
