import AVFoundation
import Foundation

/// Writes Float32 PCM samples to a 16 kHz mono `.wav` file via `AVAudioFile`.
///
/// Sprint 3 goal-L0-b: WhisperKit's native input format — Sprint 4 transcribe
/// can load the file with `AudioProcessor.loadAudioAsFloatArray` without
/// resampling or channel mixing.
public enum WAVWriter {
    public static let sampleRate: Double = 16_000
    public static let channelCount: AVAudioChannelCount = 1

    public enum Error: Swift.Error, CustomStringConvertible {
        case formatUnavailable
        case bufferAllocationFailed
        case applicationSupportUnavailable

        public var description: String {
            switch self {
            case .formatUnavailable: return "AVAudioFormat init failed for 16 kHz mono Float32."
            case .bufferAllocationFailed: return "AVAudioPCMBuffer allocation failed."
            case .applicationSupportUnavailable: return "Application Support directory unavailable."
            }
        }
    }

    /// Write `samples` to the given URL (or a timestamped path under Application Support).
    /// Returns the URL written.
    public static func write(samples: [Float], at url: URL? = nil) throws -> URL {
        let target = try url ?? makeTimestampedURL()
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else { throw Error.formatUnavailable }

        do {
            let file = try AVAudioFile(forWriting: target, settings: format.settings)
            let frameChunk = 4096
            var idx = 0
            while idx < samples.count {
                let end = Swift.min(idx + frameChunk, samples.count)
                let frames = AVAudioFrameCount(end - idx)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
                    throw Error.bufferAllocationFailed
                }
                buffer.frameLength = frames
                guard let dst = buffer.floatChannelData?[0] else {
                    throw Error.bufferAllocationFailed
                }
                samples.withUnsafeBufferPointer { src in
                    dst.update(from: src.baseAddress!.advanced(by: idx), count: end - idx)
                }
                try file.write(from: buffer)
                idx = end
            }
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return target
    }

    /// `~/Library/Application Support/Murmur/Recordings/<timestamp>.wav`. Inside a
    /// sandboxed app this resolves to the container's redirected Application Support.
    public static func makeTimestampedURL(now: Date = Date()) throws -> URL {
        let appSupport: URL
        do {
            appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw Error.applicationSupportUnavailable
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        return appSupport
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent("\(stamp).wav")
    }
}
