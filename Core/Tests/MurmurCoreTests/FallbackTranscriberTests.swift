import XCTest
@testable import MurmurCore

private enum StubErr: Error { case primary, fallback }

/// Records call order and returns/throws on demand.
private actor SpyEngine: Transcribing {
    enum Outcome: Sendable { case text(String), fail(StubErr) }
    private let outcome: Outcome
    private(set) var calls = 0

    init(_ outcome: Outcome) { self.outcome = outcome }

    func transcribe(wavURL: URL) async throws -> String {
        calls += 1
        switch outcome {
        case .text(let s): return s
        case .fail(let e): throw e
        }
    }

    func callCount() -> Int { calls }
}

final class FallbackTranscriberTests: XCTestCase {
    private let wav = URL(fileURLWithPath: "/tmp/murmur-fallback-test.wav")

    func testPrimarySuccessSkipsFallback() async throws {
        let primary = SpyEngine(.text("on-device"))
        let fallback = SpyEngine(.text("cloud"))
        let t = FallbackTranscriber(primary: primary, fallback: fallback)

        let result = try await t.transcribe(wavURL: wav)
        XCTAssertEqual(result, "on-device")
        let primaryCalls = await primary.callCount()
        let fallbackCalls = await fallback.callCount()
        XCTAssertEqual(primaryCalls, 1)
        XCTAssertEqual(fallbackCalls, 0, "primary success must not touch the cloud")
    }

    func testPrimaryThrowUsesFallback() async throws {
        let primary = SpyEngine(.fail(.primary))
        let fallback = SpyEngine(.text("cloud"))
        let t = FallbackTranscriber(primary: primary, fallback: fallback)

        let result = try await t.transcribe(wavURL: wav)
        XCTAssertEqual(result, "cloud")
        let fallbackCalls = await fallback.callCount()
        XCTAssertEqual(fallbackCalls, 1)
    }

    func testEmptyPrimaryResultDoesNotFallback() async throws {
        // Silence is a valid empty result, not a failure — no cloud hop.
        let primary = SpyEngine(.text(""))
        let fallback = SpyEngine(.text("cloud"))
        let t = FallbackTranscriber(primary: primary, fallback: fallback)

        let result = try await t.transcribe(wavURL: wav)
        XCTAssertEqual(result, "")
        let fallbackCalls = await fallback.callCount()
        XCTAssertEqual(fallbackCalls, 0)
    }

    func testBothThrowPropagatesFallbackError() async {
        let primary = SpyEngine(.fail(.primary))
        let fallback = SpyEngine(.fail(.fallback))
        let t = FallbackTranscriber(primary: primary, fallback: fallback)

        do {
            _ = try await t.transcribe(wavURL: wav)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? StubErr, .fallback)
        }
    }
}
