import XCTest
@testable import MurmurCore

@MainActor
private final class FakeRecorder: Recording {
    var isRecording = false
    var lastError: String?
    var startSucceeds = true
    var stopURL: URL?

    func start() async {
        if startSucceeds {
            isRecording = true
            lastError = nil
        } else {
            isRecording = false
            lastError = "permission denied"
        }
    }

    func stop() async -> URL? {
        isRecording = false
        return stopURL
    }
}

private enum FakeErr: Error { case boom }

private struct FixedEngine: Transcribing {
    enum Outcome: Sendable { case text(String), fail }
    let outcome: Outcome
    func transcribe(wavURL: URL) async throws -> String {
        switch outcome {
        case .text(let s): return s
        case .fail: throw FakeErr.boom
        }
    }
}

/// Suspends in `transcribe` until `release()`; `waitUntilEntered()` lets the
/// test deterministically observe the `.transcribing` phase.
private actor GateEngine: Transcribing {
    private var releaseCont: CheckedContinuation<Void, Never>?
    private var enteredCont: CheckedContinuation<Void, Never>?
    private var entered = false
    private(set) var calls = 0

    func transcribe(wavURL: URL) async throws -> String {
        calls += 1
        entered = true
        enteredCont?.resume()
        enteredCont = nil
        await withCheckedContinuation { releaseCont = $0 }
        return "gated"
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredCont = $0 }
    }

    func release() {
        releaseCont?.resume()
        releaseCont = nil
    }

    func callCount() -> Int { calls }
}

final class DictationCoordinatorTests: XCTestCase {
    private let wav = URL(fileURLWithPath: "/tmp/murmur-coordinator-test.wav")

    @MainActor
    private func makeCoordinator(
        recorder: FakeRecorder,
        engine: any Transcribing
    ) -> DictationCoordinator {
        DictationCoordinator(recorder: recorder, transcriber: Transcriber(engine: engine))
    }

    @MainActor
    func testIdleToggleStartsRecording() async {
        let rec = FakeRecorder()
        let c = makeCoordinator(recorder: rec, engine: FixedEngine(outcome: .text("x")))
        await c.toggle()
        XCTAssertEqual(c.phase, .recording)
        XCTAssertNil(c.errorMessage)
    }

    @MainActor
    func testStartFailureStaysIdleWithError() async {
        let rec = FakeRecorder()
        rec.startSucceeds = false
        let c = makeCoordinator(recorder: rec, engine: FixedEngine(outcome: .text("x")))
        await c.toggle()
        XCTAssertEqual(c.phase, .idle)
        XCTAssertEqual(c.errorMessage, "permission denied")
    }

    @MainActor
    func testFullRoundTripProducesTranscript() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let c = makeCoordinator(recorder: rec, engine: FixedEngine(outcome: .text("hello")))
        await c.toggle()                       // → recording
        await c.toggle()                       // stop → transcribe → idle
        XCTAssertEqual(c.phase, .idle)
        XCTAssertEqual(c.transcript, "hello")
        XCTAssertEqual(c.lastSavedURL, wav)
        XCTAssertNil(c.errorMessage)
    }

    @MainActor
    func testStopWithNoAudioSkipsTranscribe() async {
        let rec = FakeRecorder()
        rec.stopURL = nil
        rec.lastError = "No audio captured."
        let c = makeCoordinator(recorder: rec, engine: FixedEngine(outcome: .fail))
        await c.toggle()                       // → recording
        await c.toggle()                       // stop returns nil
        XCTAssertEqual(c.phase, .idle)
        XCTAssertEqual(c.errorMessage, "No audio captured.")
        XCTAssertNil(c.transcript)
    }

    @MainActor
    func testTranscribeFailureSurfacesError() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let c = makeCoordinator(recorder: rec, engine: FixedEngine(outcome: .fail))
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(c.phase, .idle)
        XCTAssertNil(c.transcript)
        XCTAssertNotNil(c.errorMessage)
    }

    @MainActor
    func testToggleDuringTranscribingIsIgnored() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let gate = GateEngine()
        let c = makeCoordinator(recorder: rec, engine: gate)

        await c.toggle()                       // → recording
        let flow = Task { await c.toggle() }   // stop → transcribing (suspends in gate)
        await gate.waitUntilEntered()

        XCTAssertEqual(c.phase, .transcribing)
        await c.toggle()                       // must be ignored
        let calls = await gate.callCount()
        XCTAssertEqual(calls, 1, "tap during transcription must not re-enter the engine")

        await gate.release()
        await flow.value
        XCTAssertEqual(c.phase, .idle)
        XCTAssertEqual(c.transcript, "gated")
    }
}
