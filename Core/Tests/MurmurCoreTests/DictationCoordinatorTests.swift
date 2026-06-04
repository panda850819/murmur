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

private struct FixedEnhancer: LLMEnhancing {
    enum Outcome: Sendable { case text(String), fail }
    let outcome: Outcome
    func enhance(_ text: String, glossary: [String]) async throws -> String {
        switch outcome {
        case .text(let s): return s
        case .fail: throw FakeErr.boom
        }
    }
}

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

/// Records the text it was asked to enhance and returns it unchanged, so a test
/// can prove the enhancer ran on the ALREADY-CORRECTED transcript. An `actor`
/// (like `GateEngine`) rather than a `@unchecked Sendable` class, so the
/// recorded state is concurrency-safe without opting out of checking.
private actor EchoEnhancer: LLMEnhancing {
    private(set) var seen: [String] = []
    private(set) var seenGlossary: [[String]] = []
    func enhance(_ text: String, glossary: [String]) async throws -> String {
        seen.append(text)
        seenGlossary.append(glossary)
        return text
    }
}

/// Test double for the A' correction seam: substring replacement plus a record
/// of every input, so a test can assert what the corrector saw.
@MainActor
private final class FakeCorrector: TextCorrecting {
    private(set) var seen: [String] = []
    private let map: [String: String]
    let glossaryTerms: [String]
    let isRealWord: (String) -> Bool
    init(_ map: [String: String], glossary: [String] = [], realWords: Set<String> = []) {
        self.map = map
        self.glossaryTerms = glossary
        self.isRealWord = { realWords.contains($0.lowercased()) }
    }
    func correct(_ text: String) -> String {
        seen.append(text)
        return map.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
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
        paster: FakePaster? = nil,
        enhancer: (any LLMEnhancing)? = nil,
        corrector: (any TextCorrecting)? = nil
    ) -> DictationCoordinator {
        DictationCoordinator(
            recorder: recorder,
            transcriber: Transcriber(engine: engine),
            paster: paster ?? FakePaster(),
            enhancer: enhancer,
            corrector: corrector
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

    // MARK: Enhance (Groq clean-up)

    @MainActor
    func testNoEnhancerCanEnhanceFalse() {
        let c = makeCoordinator(recorder: FakeRecorder(), engine: FixedEngine(outcome: .text("x")))
        XCTAssertFalse(c.canEnhance)
    }

    @MainActor
    func testEnhancerPresentCanEnhanceTrue() {
        let c = makeCoordinator(
            recorder: FakeRecorder(),
            engine: FixedEngine(outcome: .text("x")),
            enhancer: FixedEnhancer(outcome: .text("y"))
        )
        XCTAssertTrue(c.canEnhance)
    }

    @MainActor
    func testEnhanceCleansTranscriptAndPastesCleaned() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("um i will be there in ten minutes")),
            paster: paster,
            enhancer: FixedEnhancer(outcome: .text("I'll be there in 10 minutes."))
        )
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(c.transcript, "I'll be there in 10 minutes.")
        XCTAssertEqual(paster.pasted, ["I'll be there in 10 minutes."])
    }

    @MainActor
    func testEnhanceDisabledKeepsRaw() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("raw text")),
            paster: paster,
            enhancer: FixedEnhancer(outcome: .text("ENHANCED"))
        )
        c.enhanceEnabled = false
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(c.transcript, "raw text")
        XCTAssertEqual(paster.pasted, ["raw text"])
    }

    @MainActor
    func testEnhanceFailureFallsBackToRaw() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("raw text")),
            paster: paster,
            enhancer: FixedEnhancer(outcome: .fail)
        )
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(c.transcript, "raw text", "enhance throw must not lose the transcript")
        XCTAssertEqual(paster.pasted, ["raw text"])
        XCTAssertNil(c.errorMessage)
    }

    @MainActor
    func testEnhanceFailingSanityFilterFallsBackToRaw() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("raw text")),
            paster: paster,
            enhancer: FixedEnhancer(outcome: .text("great work 🎉"))
        )
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(c.transcript, "raw text", "emoji output must be rejected, raw kept")
        XCTAssertEqual(paster.pasted, ["raw text"])
    }

    @MainActor
    func testEmptyEnhanceResultFallsBackToRaw() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("raw text")),
            paster: paster,
            enhancer: FixedEnhancer(outcome: .text("   "))
        )
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(c.transcript, "raw text")
        XCTAssertEqual(paster.pasted, ["raw text"])
    }

    @MainActor
    func testEmptyTranscriptSkipsEnhance() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("")),
            paster: paster,
            enhancer: FixedEnhancer(outcome: .text("SHOULD NOT APPEAR"))
        )
        await c.toggle()
        await c.toggle()
        XCTAssertTrue(paster.pasted.isEmpty, "empty transcript: no enhance, no paste")
        XCTAssertEqual(c.transcript, "")
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

    // MARK: Correction (A')

    @MainActor
    func testCorrectionAppliedWhenNoEnhancer() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let paster = FakePaster()
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("use gbrand here")),
            paster: paster,
            corrector: FakeCorrector(["gbrand": "gbrain"])
        )
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(c.transcript, "use gbrain here", "on-device correction applies with no enhancer")
        XCTAssertEqual(paster.pasted, ["use gbrain here"])
    }

    @MainActor
    func testCorrectionRunsOnRawBeforeEnhance() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let echo = EchoEnhancer()
        let corrector = FakeCorrector(["gbrand": "gbrain"])
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("ship gbrand")),
            enhancer: echo,
            corrector: corrector
        )
        await c.toggle()
        await c.toggle()
        let echoSeen = await echo.seen
        // A' runs on the RAW transcript first, then AGAIN on the enhanced output.
        XCTAssertEqual(corrector.seen, ["ship gbrand", "ship gbrain"],
                       "corrector sees the raw transcript, then the enhanced output")
        XCTAssertEqual(echoSeen, ["ship gbrain"], "enhancer sees the CORRECTED transcript")
        XCTAssertEqual(c.transcript, "ship gbrain")
    }

    @MainActor
    func testEnhanceGlossaryNarrowedToUtterance() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let echo = EchoEnhancer()
        // B' privacy gate: the corrector's glossary reaches the enhance call but
        // narrowed to terms the utterance actually names. A' corrects "gbrand" →
        // "gbrain"; the filter keeps it and drops the unsaid "Yei", so only the
        // spoken name crosses the wire.
        let corrector = FakeCorrector(["gbrand": "gbrain"], glossary: ["gbrain", "Yei"])
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("ship gbrand")),
            enhancer: echo,
            corrector: corrector
        )
        await c.toggle()
        await c.toggle()
        let seenGlossary = await echo.seenGlossary
        XCTAssertEqual(seenGlossary, [["gbrain"]],
                       "only the uttered name is injected; unsaid Yei is filtered out")
    }

    @MainActor
    func testEnhancerNotCalledWhenEnhanceDisabled() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let echo = EchoEnhancer()
        // A non-empty glossary is wired but enhance is OFF: the enhancer must
        // not be called at all. Asserts the `guard enhanceEnabled` in
        // enhanced() — a real logic flip (removing the guard) would record a
        // call here. (The no-corrector ⇒ empty-glossary path is the bare
        // `?? []` default, exercised implicitly by the FixedEnhancer tests.)
        let corrector = FakeCorrector(["gbrand": "gbrain"], glossary: ["gbrain", "Yei"])
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("ship gbrand")),
            enhancer: echo,
            corrector: corrector
        )
        c.enhanceEnabled = false
        await c.toggle()
        await c.toggle()
        let seenGlossary = await echo.seenGlossary
        XCTAssertTrue(seenGlossary.isEmpty, "enhancer must not run when enhance is disabled")
        XCTAssertEqual(c.transcript, "ship gbrain", "A' still applies deterministically")
    }

    @MainActor
    func testCorrectionReappliedAfterEnhanceCannotUndoIt() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        // Simulate Groq cleanup re-mangling a freshly-corrected name back to the
        // mishearing ("fix capitalization" gone wrong). The post-enhance A' pass
        // must restore it — the deterministic corrector gets the last word.
        let mangling = FixedEnhancer(outcome: .text("ship gbrand"))
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("ship gbrand")),
            enhancer: mangling,
            corrector: FakeCorrector(["gbrand": "gbrain"])
        )
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(c.transcript, "ship gbrain",
                       "post-enhance A' restores a name the enhancer re-mangled")
    }

    @MainActor
    func testCorrectionAppliedWithEnhanceDisabled() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("gbrand")),
            enhancer: FixedEnhancer(outcome: .text("ENHANCED")),
            corrector: FakeCorrector(["gbrand": "gbrain"])
        )
        c.enhanceEnabled = false
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(c.transcript, "gbrain", "correction still runs when enhance is off")
    }

    @MainActor
    func testNoCorrectorPassesTranscriptThrough() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("gbrand stays")),
            corrector: nil
        )
        await c.toggle()
        await c.toggle()
        XCTAssertEqual(c.transcript, "gbrand stays")
    }

    @MainActor
    func testEmptyTranscriptSkipsCorrection() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let corrector = FakeCorrector(["x": "y"])
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("")),
            corrector: corrector
        )
        await c.toggle()
        await c.toggle()
        XCTAssertTrue(corrector.seen.isEmpty, "empty transcript must not invoke the corrector")
    }

    // MARK: Glossary relevance filter (B' privacy gate)

    @MainActor
    func testNoProperNounUtteranceShipsEmptyGlossary() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let echo = EchoEnhancer()
        // The glossary is populated but the utterance names none of its entities.
        // Nothing private may cross the wire — the enhancer must receive [].
        let corrector = FakeCorrector([:], glossary: ["gbrain", "Yei", "Sommet"])
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("the meeting is at noon tomorrow")),
            enhancer: echo,
            corrector: corrector
        )
        await c.toggle()
        await c.toggle()
        let seenGlossary = await echo.seenGlossary
        XCTAssertEqual(seenGlossary, [[]],
                       "no proper noun said ⇒ no private entity disclosed to the cloud")
    }

    @MainActor
    func testMisheardNameFuzzyMatchesUnsaidTermsDropped() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let echo = EchoEnhancer()
        // A' does NOT fix it (empty map), so the filter itself must fuzzy-match
        // the misheard token "gbrand" to glossary "gbrain"; "Yei" is unsaid.
        let corrector = FakeCorrector([:], glossary: ["gbrain", "Yei"])
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("ship gbrand today")),
            enhancer: echo,
            corrector: corrector
        )
        await c.toggle()
        await c.toggle()
        let seenGlossary = await echo.seenGlossary
        XCTAssertEqual(seenGlossary, [["gbrain"]],
                       "misheard name fuzzy-matches and is kept; unsaid term filtered out")
    }

    @MainActor
    func testCommonWordsDoNotLeakPrivateNames() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let echo = EchoEnhancer()
        // End-to-end leak regression: ordinary English words ("train", "brain")
        // sit within the fuzzy radius of "gbrain". With A's real-word guard
        // shared into the filter, they must NOT drag the private name to Groq.
        let corrector = FakeCorrector([:], glossary: ["gbrain"], realWords: ["train", "my", "brain"])
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("train my brain")),
            enhancer: echo,
            corrector: corrector
        )
        await c.toggle()
        await c.toggle()
        let seenGlossary = await echo.seenGlossary
        XCTAssertEqual(seenGlossary, [[]],
                       "no entity spoken ⇒ common words near a term must not leak it")
    }

    @MainActor
    func testNoCorrectorShipsEmptyGlossary() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let echo = EchoEnhancer()
        // nil corrector ⇒ the glossary source is the `?? []` default; nothing can
        // reach the cloud regardless of what the utterance says.
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("ship gbrand today")),
            enhancer: echo,
            corrector: nil
        )
        await c.toggle()
        await c.toggle()
        let seenGlossary = await echo.seenGlossary
        XCTAssertEqual(seenGlossary, [[]],
                       "no corrector ⇒ empty glossary, nothing disclosed")
    }

    @MainActor
    func testFilterRunsOnTheACorrectedTranscript() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let echo = EchoEnhancer()
        // A direct-map pair whose heard form is far (edit distance > threshold)
        // from the canonical: only AFTER A' rewrites "zbrn" → "gbrain" does a
        // token match the term. Locks the invariant that the filter sees the
        // A'-corrected transcript, not the raw Whisper output (pre-A' "zbrn"
        // would not match and the term would be wrongly dropped).
        let corrector = FakeCorrector(["zbrn": "gbrain"], glossary: ["gbrain"])
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("ship zbrn today")),
            enhancer: echo,
            corrector: corrector
        )
        await c.toggle()
        await c.toggle()
        let seenGlossary = await echo.seenGlossary
        XCTAssertEqual(seenGlossary, [["gbrain"]],
                       "term reachable only via the A'-corrected token ⇒ filter runs post-A'")
    }

    @MainActor
    func testMultipleRelevantTermsSurviveThroughCoordinator() async {
        let rec = FakeRecorder()
        rec.stopURL = wav
        let echo = EchoEnhancer()
        // Two names spoken ⇒ both must reach the enhancer through the real call
        // path, in first-seen order (locks no truncation / reorder in the wiring).
        let corrector = FakeCorrector([:], glossary: ["gbrain", "Yei"])
        let c = makeCoordinator(
            recorder: rec,
            engine: FixedEngine(outcome: .text("ship gbrain and yei now")),
            enhancer: echo,
            corrector: corrector
        )
        await c.toggle()
        await c.toggle()
        let seenGlossary = await echo.seenGlossary
        XCTAssertEqual(seenGlossary, [["gbrain", "Yei"]],
                       "both spoken names survive the coordinator path in first-seen order")
    }

    func testRelevantGlossaryFuzzyExactAndFailClosed() {
        typealias F = GlossaryRelevanceFilter
        let words: Set<String> = ["the", "finance", "team", "met", "is", "what", "ox", "ran", "and", "now"]
        let real: (String) -> Bool = { words.contains($0.lowercased()) }
        // non-word mishearings fuzzy-match within the length-scaled threshold
        XCTAssertEqual(F.relevant(transcript: "ship gbrand today", glossary: ["gbrain"], isRealWord: real),
                       ["gbrain"], "non-word mishearing, distance 2 ≤ threshold(len 6)=2 ⇒ kept")
        XCTAssertEqual(F.relevant(transcript: "using hermies now", glossary: ["hermes"], isRealWord: real),
                       ["hermes"], "non-word mishearing, distance 1 ⇒ kept")
        // exact match kept regardless of length or real-word status
        XCTAssertEqual(F.relevant(transcript: "ship gbrain now", glossary: ["gbrain"], isRealWord: real),
                       ["gbrain"], "exact spoken match ⇒ kept")
        XCTAssertEqual(F.relevant(transcript: "what is ai", glossary: ["AI"], isRealWord: real),
                       ["AI"], "2-char term spoken exactly ⇒ kept")
        // far / unrelated term dropped
        XCTAssertEqual(F.relevant(transcript: "the finance team met", glossary: ["BlackRock"], isRealWord: real),
                       [], "no token near the term ⇒ dropped (not disclosed)")
        // 2-char term with no exact token ⇒ threshold floor blocks fuzzy
        XCTAssertEqual(F.relevant(transcript: "the ox ran", glossary: ["AI"], isRealWord: real),
                       [], "term under 3 chars floors threshold to 0 ⇒ no fuzzy match")
        // fail closed
        XCTAssertEqual(F.relevant(transcript: "", glossary: ["gbrain"], isRealWord: real),
                       [], "empty transcript fails closed")
        XCTAssertEqual(F.relevant(transcript: "今天 開會", glossary: ["gbrain", "Yei"], isRealWord: real),
                       [], "CJK-only utterance (no Latin tokens) fails closed")
        XCTAssertEqual(F.relevant(transcript: "ship gbrain and yei now", glossary: ["gbrain", "Yei"], isRealWord: real),
                       ["gbrain", "Yei"], "both names said ⇒ both kept, first-seen order preserved")
    }

    func testRelevantGlossaryRealWordGuardClosesTheLeak() {
        // The privacy brake: an ordinary word near a stored name must NOT pull
        // that name to the cloud (it's probably the common word), but a non-word
        // mishearing of the SAME name still matches, so recall is preserved.
        typealias F = GlossaryRelevanceFilter
        let words: Set<String> = ["read", "the", "sonnet", "i", "work", "at", "train", "my", "brain"]
        let real: (String) -> Bool = { words.contains($0.lowercased()) }
        XCTAssertEqual(F.relevant(transcript: "read the sonnet", glossary: ["Sommet"], isRealWord: real),
                       [], "real word 'sonnet' near 'Sommet' ⇒ dropped, no unspoken entity leaks")
        XCTAssertEqual(F.relevant(transcript: "i work at sommett", glossary: ["Sommet"], isRealWord: real),
                       ["Sommet"], "non-word mishearing 'sommett' (distance 1) ⇒ still matched and kept")
        XCTAssertEqual(F.relevant(transcript: "train my brain", glossary: ["gbrain"], isRealWord: real),
                       [], "real words 'train'/'brain' near 'gbrain' ⇒ dropped")
    }

    func testRealWordEntitySpokenExactlyIsKept() {
        // Recall half of the gate: a glossary term that is itself a real English
        // word (Bob, Axis, Nous) must STILL be kept when spoken exactly. The
        // exact-match arm runs BEFORE the real-word guard precisely for this;
        // reordering them would silently stop disclosing genuinely-named entities
        // and break C's escape hatch (A' canonicalizes a token → kept by exact).
        let words: Set<String> = ["call", "bob", "now", "the", "axis", "team", "job", "list"]
        let real: (String) -> Bool = { words.contains($0.lowercased()) }
        typealias F = GlossaryRelevanceFilter
        XCTAssertEqual(F.relevant(transcript: "call Bob now", glossary: ["Bob"], isRealWord: real),
                       ["Bob"], "real-word entity spoken exactly ⇒ kept (exact precedes the guard)")
        XCTAssertEqual(F.relevant(transcript: "the axis team", glossary: ["Axis"], isRealWord: real),
                       ["Axis"], "another real-word entity spoken exactly ⇒ kept")
        // Contrast: the same class of term as a real-word NEAR-MISS (not the name
        // spoken) is dropped — 'job' is a real word one edit from 'Bob'.
        XCTAssertEqual(F.relevant(transcript: "the job list", glossary: ["Bob"], isRealWord: real),
                       [], "real-word near-miss (the name was not spoken) ⇒ dropped")
    }

    func testRelevantGlossaryShortTokenDoesNotLeak() {
        // A short NON-word token must not fuzzy-pull a longer private term: the
        // tolerance is clamped to the shorter length, so "ye" (2 chars) can't
        // reach "Yei" (mirrors A's minFuzzyLength floor; closes the iter-2 leak).
        let real: (String) -> Bool = { _ in false }
        typealias F = GlossaryRelevanceFilter
        XCTAssertEqual(F.relevant(transcript: "ye now", glossary: ["Yei"], isRealWord: real),
                       [], "2-char non-word token ⇒ no fuzzy match to a 3-char term")
        XCTAssertEqual(F.relevant(transcript: "say yei now", glossary: ["Yei"], isRealWord: real),
                       ["Yei"], "the 3-char term spoken exactly is still kept")
    }

    func testRelevantGlossaryCodeMixedRealWordDoesNotLeak() {
        // Code-mixed dictation is the app's primary use case: a real English word
        // embedded in a CJK utterance must not leak a private term it sits near.
        let words: Set<String> = ["brain"]
        let real: (String) -> Bool = { words.contains($0.lowercased()) }
        typealias F = GlossaryRelevanceFilter
        XCTAssertEqual(F.relevant(transcript: "今天 brain 開會", glossary: ["gbrain"], isRealWord: real),
                       [], "real word 'brain' in a CJK utterance ⇒ 'gbrain' not leaked")
        XCTAssertEqual(F.relevant(transcript: "今天 gbrain 開會", glossary: ["gbrain"], isRealWord: real),
                       ["gbrain"], "the name actually said in a CJK utterance ⇒ kept")
    }
}
