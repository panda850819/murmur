import XCTest
@testable import MurmurCore

/// Exercises the real RMS path end-to-end through WAVWriter-produced files —
/// the same writer the recorder uses, so the detector is tested against the
/// exact on-disk format it will see in production (Float32 PCM, 16 kHz mono).
final class SilenceDetectorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-silence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 0.1 s of 440 Hz at the given peak amplitude (RMS ≈ amplitude / √2).
    private func toneSamples(amplitude: Float) -> [Float] {
        (0..<1600).map { i in
            amplitude * Float(sin(2.0 * Double.pi * 440.0 * Double(i) / WAVWriter.sampleRate))
        }
    }

    func testAllZeroSamplesAreSilent() throws {
        let url = try WAVWriter.write(
            samples: [Float](repeating: 0, count: 1600),
            at: dir.appendingPathComponent("silent.wav")
        )
        XCTAssertTrue(SilenceDetector.isSilent(wavURL: url))
    }

    func testToneIsNotSilent() throws {
        // RMS ≈ 0.35, far above the 0.005 default threshold.
        let url = try WAVWriter.write(
            samples: toneSamples(amplitude: 0.5),
            at: dir.appendingPathComponent("tone.wav")
        )
        XCTAssertFalse(SilenceDetector.isSilent(wavURL: url))
    }

    func testFaintNoiseBelowThresholdIsSilent() throws {
        // RMS ≈ 0.0007 — electrical noise floor territory, not speech.
        let url = try WAVWriter.write(
            samples: toneSamples(amplitude: 0.001),
            at: dir.appendingPathComponent("faint.wav")
        )
        XCTAssertTrue(SilenceDetector.isSilent(wavURL: url))
    }

    func testThresholdParameterIsRespected() throws {
        // The same audible tone flips verdict with the threshold, proving the
        // parameter is wired into the comparison and not shadowed.
        let url = try WAVWriter.write(
            samples: toneSamples(amplitude: 0.5),
            at: dir.appendingPathComponent("threshold.wav")
        )
        XCTAssertFalse(SilenceDetector.isSilent(wavURL: url, rmsThreshold: 0.005))
        XCTAssertTrue(SilenceDetector.isSilent(wavURL: url, rmsThreshold: 1.0))
    }

    func testZeroFrameFileIsSilent() throws {
        // Fully decoded with zero samples: an empty recording IS silence —
        // unlike the unreadable cases below, nothing here was unverifiable.
        let url = try WAVWriter.write(
            samples: [],
            at: dir.appendingPathComponent("empty.wav")
        )
        XCTAssertTrue(SilenceDetector.isSilent(wavURL: url), "zero frames, fully decoded ⇒ silent")
    }

    func testUnreadableFileIsNotSilent() {
        // "True" is reserved for verified silence. A file we can't even open
        // must NOT be called silent — that verdict would silently drop a real
        // dictation; the transcriber gets to fail loudly instead.
        let missing = dir.appendingPathComponent("does-not-exist.wav")
        XCTAssertFalse(SilenceDetector.isSilent(wavURL: missing),
                       "unreadable ⇒ not silent; let the transcriber surface the error")
    }

    func testGarbageFileIsNotSilent() throws {
        // Not a RIFF file at all — AVAudioFile refuses it. Same contract as
        // the missing file: undecodable ⇒ no silence claim.
        let url = dir.appendingPathComponent("garbage.wav")
        try Data("not a wav".utf8).write(to: url)
        XCTAssertFalse(SilenceDetector.isSilent(wavURL: url))
    }

    func testLongClipSpansMultipleReadChunks() throws {
        // 8000 frames > the 4096-frame read chunk: the RMS loop must keep
        // accumulating across reads, not stop after the first buffer.
        var samples = [Float](repeating: 0, count: 8000)
        // Energy only in the SECOND chunk — a loop that stopped early would
        // see pure silence and report true.
        for i in 5000..<6600 {
            samples[i] = 0.5 * Float(sin(2.0 * Double.pi * 440.0 * Double(i) / WAVWriter.sampleRate))
        }
        let url = try WAVWriter.write(samples: samples, at: dir.appendingPathComponent("long.wav"))
        XCTAssertFalse(SilenceDetector.isSilent(wavURL: url))
    }
}
