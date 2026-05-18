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

@MainActor
private final class FakePaster: Pasting {
    private(set) var pasted: [String] = []
    var succeeds = true
    func paste(_ text: String) -> Bool {
        pasted.append(text)
        return succeeds
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
        engine: any Transcribing,
        paster: FakePaster? = nil
    ) -> DictationCoordinator {
        DictationCoordinator(
            recorder: recorder,
            transcriber: Transcriber(engine: engine),
            paster: paster ?? FakePaster()
        )
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

    @MainActor
    func testSuccessfulTranscriptIsPasted() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("hello world")),
            paster: paster
        )
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(paster.pasted, ["hello world"])
        XCTAssertNil(c.errorMessage)
    }

    @MainActor
    func testEmptyTranscriptIsNotPasted() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("")),
            paster: paster
        )
        await c.toggle()
        await c.toggle()
        XCTAssertTrue(paster.pasted.isEmpty, "empty transcript must not paste")
        XCTAssertNil(c.errorMessage)
    }

    @MainActor
    func testPasteRefusalSurfacesAccessibilityHint() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        paster.succeeds = false
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("hi")),
            paster: paster
        )
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(paster.pasted, ["hi"])
        XCTAssertEqual(c.transcript, "hi")
        XCTAssertNotNil(c.errorMessage)
        XCTAssertTrue(
            c.errorMessage?.contains("Accessibility") == true,
            "refused paste must point the user at Accessibility"
        )
    }

    @MainActor
    func testCancelStopsRecordingWithoutTranscribeOrPaste() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("should not run")),
            paster: paster
        )
        await c.toggle()                       // → recording
        XCTAssertEqual(c.phase, .recording)
        await c.cancel()                       // abort, no transcribe/paste
        XCTAssertEqual(c.phase, .idle)
        XCTAssertNil(c.transcript)
        XCTAssertTrue(paster.pasted.isEmpty)
    }

    @MainActor
    func testCancelWhileIdleIsNoOp() async {
        let rec = FakeRecorder()
        let c = makeCoordinator(recorder: rec, engine: FixedEngine(outcome: .text("x")))
        await c.cancel()
        XCTAssertEqual(c.phase, .idle)
    }

    /// A hotkey-cancel that lands while a transcribe is in flight must not
    /// corrupt it (mirrors `testToggleDuringTranscribingIsIgnored`).
    @MainActor
    func testCancelDuringTranscribingIsIgnored() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let gate = GateEngine()
        let paster = FakePaster()
        let c = makeCoordinator(recorder: rec, engine: gate, paster: paster)

        await c.toggle()                       // → recording
        let flow = Task { await c.toggle() }   // stop → transcribing (gated)
        await gate.waitUntilEntered()

        XCTAssertEqual(c.phase, .transcribing)
        await c.cancel()                       // must be ignored
        XCTAssertEqual(c.phase, .transcribing)

        await gate.release()
        await flow.value
        XCTAssertEqual(c.phase, .idle)
        XCTAssertEqual(c.transcript, "gated")
        XCTAssertEqual(paster.pasted, ["gated"])
    }
}
