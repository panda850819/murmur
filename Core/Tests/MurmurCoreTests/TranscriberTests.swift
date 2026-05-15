import XCTest
@testable import MurmurCore

private enum FakeError: Error { case boom }

/// Deterministic `Transcribing` — returns a fixed string or throws.
private struct FakeTranscriber: Transcribing {
    enum Outcome: Sendable { case text(String), failure }
    let outcome: Outcome
    func transcribe(wavURL: URL) async throws -> String {
        switch outcome {
        case .text(let s): return s
        case .failure: throw FakeError.boom
        }
    }
}

/// Suspends inside `transcribe` until `release()` so the in-flight guard can
/// be observed.
private actor GateEngine: Transcribing {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0

    func transcribe(wavURL: URL) async throws -> String {
        calls += 1
        await withCheckedContinuation { self.continuation = $0 }
        return "gated"
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func callCount() -> Int { calls }
}

final class TranscriberTests: XCTestCase {
    private let wav = URL(fileURLWithPath: "/tmp/murmur-transcriber-test.wav")

    @MainActor
    func testSuccessPublishesTrimmedTranscriptAndClearsBusy() async {
        let t = Transcriber(engine: FakeTranscriber(outcome: .text("hello world")))
        await t.transcribe(wavURL: wav)
        XCTAssertEqual(t.transcript, "hello world")
        XCTAssertNil(t.lastError)
        XCTAssertFalse(t.isTranscribing)
    }

    @MainActor
    func testFailureSetsErrorAndLeavesTranscriptNil() async {
        let t = Transcriber(engine: FakeTranscriber(outcome: .failure))
        await t.transcribe(wavURL: wav)
        XCTAssertNil(t.transcript)
        XCTAssertNotNil(t.lastError)
        XCTAssertFalse(t.isTranscribing)
    }

    @MainActor
    func testSuccessAfterFailureClearsPriorError() async {
        let t = Transcriber(engine: FakeTranscriber(outcome: .failure))
        await t.transcribe(wavURL: wav)
        XCTAssertNotNil(t.lastError)

        let ok = Transcriber(engine: FakeTranscriber(outcome: .text("recovered")))
        await ok.transcribe(wavURL: wav)
        XCTAssertEqual(ok.transcript, "recovered")
        XCTAssertNil(ok.lastError)
    }

    @MainActor
    func testInFlightCallIsNoOp() async {
        let gate = GateEngine()
        let t = Transcriber(engine: gate)

        let first = Task { await t.transcribe(wavURL: wav) }
        while await gate.callCount() == 0 { await Task.yield() }

        XCTAssertTrue(t.isTranscribing)
        await t.transcribe(wavURL: wav)  // in-flight → guard returns immediately
        let calls = await gate.callCount()
        XCTAssertEqual(calls, 1, "second call must not reach the engine")

        await gate.release()
        await first.value
        XCTAssertFalse(t.isTranscribing)
        XCTAssertEqual(t.transcript, "gated")
    }
}
