import AVFoundation
import XCTest
@testable import MurmurCore

final class WAVWriterTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wavwriter-\(UUID().uuidString).wav")
    }

    override func tearDown() {
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        tempURL = nil
        super.tearDown()
    }

    func testWritesAt16kHzMonoFloat32PCM() throws {
        let n = 16_000  // 1 second
        let samples: [Float] = (0..<n).map { i in
            Float(sin(2 * .pi * 440 * Double(i) / 16_000))
        }
        let url = try WAVWriter.write(samples: samples, at: tempURL)
        XCTAssertEqual(url, tempURL)

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.length, AVAudioFramePosition(n))
    }

    func testRoundTripPreservesSamples() throws {
        let samples: [Float] = (0..<2048).map { i in Float(i) / 2048.0 }
        _ = try WAVWriter.write(samples: samples, at: tempURL)

        let file = try AVAudioFile(forReading: tempURL)
        guard
            let pcmFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: pcmFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            )
        else {
            XCTFail("Failed to allocate read buffer.")
            return
        }
        try file.read(into: buffer)
        XCTAssertEqual(Int(buffer.frameLength), samples.count)

        let channel = buffer.floatChannelData![0]
        for i in stride(from: 0, to: samples.count, by: 256) {
            XCTAssertEqual(channel[i], samples[i], accuracy: 1e-4)
        }
    }

    func testEmptyInputProducesEmptyWAV() throws {
        let url = try WAVWriter.write(samples: [], at: tempURL)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, 0)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
    }

    func testWritesAcrossMultipleChunkBoundaries() throws {
        // 100_000 samples = ~24 internal 4096-frame chunks; verifies chunked
        // write path produces a file whose length matches the input exactly.
        let n = 100_000
        let samples: [Float] = (0..<n).map { Float($0 % 1024) / 1024.0 }
        _ = try WAVWriter.write(samples: samples, at: tempURL)

        let file = try AVAudioFile(forReading: tempURL)
        XCTAssertEqual(file.length, AVAudioFramePosition(n))
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
    }

    func testFailedWriteDoesNotLeavePartialFile() throws {
        // Pointing at a path whose parent cannot be created (a regular file
        // standing in for the parent dir) forces AVAudioFile init to throw
        // after target.deletingLastPathComponent() refuses to be a dir.
        let parentBlocker = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wavwriter-blocker-\(UUID().uuidString)")
        try Data("not a dir".utf8).write(to: parentBlocker)
        defer { try? FileManager.default.removeItem(at: parentBlocker) }
        let nested = parentBlocker.appendingPathComponent("nested.wav")

        XCTAssertThrowsError(try WAVWriter.write(samples: [0.0, 0.1], at: nested))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path))
    }

    func testMakeTimestampedURLLivesUnderApplicationSupport() throws {
        let url = try WAVWriter.makeTimestampedURL()
        XCTAssertEqual(url.pathExtension, "wav")
        XCTAssertTrue(url.path.contains("/Murmur/Recordings/"), "got: \(url.path)")
    }
}
