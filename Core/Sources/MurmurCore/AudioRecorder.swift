import AVFoundation
import Foundation
import os

/// Records mic audio into a 16 kHz mono Float32 WAV.
///
/// Owns a **single, persistent `AVAudioEngine`** with the input tap
/// installed exactly once. It is never re-instantiated and never
/// `.reset()` — `start()`/`stop()` only toggle a capture flag and
/// `engine.start()` / `engine.stop()` on that one instance.
///
/// Why not WhisperKit's `AudioProcessor`: it builds a fresh `AVAudioEngine`
/// every `startRecordingLive()` and `engine.reset()`s it every
/// `stopRecording()`. Real dogfood (verified build) showed that lifecycle
/// degrades — stop/start churned the macOS audio HAL (failed ~2nd–3rd),
/// and pause/resume merely delayed it (`-10868` on resume at session #6).
/// A persistent engine with a once-installed tap removes that entire
/// failure class. WhisperKit is still used — for transcription only.
@MainActor
public final class AudioRecorder: ObservableObject {
    public static let hardCapSeconds: TimeInterval = 30

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var lastSavedURL: URL?
    @Published public private(set) var lastError: String?

    private let engine = AVAudioEngine()
    private var tapInstalled = false
    /// Gates whether the (always-installed) tap accumulates. Lock-guarded:
    /// the tap runs on a realtime audio thread, start/stop on @MainActor.
    private let capturing = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let captureBuffer = OSAllocatedUnfairLock<[Float]>(initialState: [])
    private var hardCapTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.panda.murmur", category: "audio")
    private var sessionCount = 0
    private var startedAt: Date?

    public init() {}

    public func start() async {
        guard !isRecording else { return }
        lastError = nil

        guard await Self.ensureMicPermission() else {
            lastError = "Microphone permission denied."
            return
        }

        sessionCount += 1
        let n = sessionCount

        do {
            try installTapIfNeeded()
            captureBuffer.withLock { $0.removeAll(keepingCapacity: true) }
            capturing.withLock { $0 = true }
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            capturing.withLock { $0 = false }
            let mic = Self.micStatusString()
            Self.log.error("session #\(n) start threw (mic=\(mic)): \(error.localizedDescription)")
            lastError = "Start failed [#\(n), engineStart, mic=\(mic)]: "
                + "\(error.localizedDescription)"
            return
        }

        startedAt = Date()
        isRecording = true
        Self.log.info("session #\(n) started")
        hardCapTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.hardCapSeconds * 1_000_000_000))
            } catch {
                return
            }
            await self?.stop()
        }
    }

    @discardableResult
    public func stop() async -> URL? {
        guard isRecording else { return nil }
        hardCapTask?.cancel()
        hardCapTask = nil

        // Stop accumulating BEFORE reading so no tap block races the read.
        capturing.withLock { $0 = false }
        isRecording = false
        // Persistent instance: stop the engine but never reset / re-create
        // it, and leave the tap installed — that is the whole point.
        engine.stop()

        let samples = captureBuffer.withLock { $0 }
        let n = sessionCount
        let ms = Int((startedAt.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
        Self.log.info("session #\(n) stopped after \(ms)ms; captured=\(samples.count) samples")

        guard !samples.isEmpty else {
            lastError = "No audio captured. [diag #\(n), \(ms)ms, \(samples.count) samples]"
            return nil
        }

        do {
            let url = try WAVWriter.write(samples: samples)
            lastSavedURL = url
            return url
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
            return nil
        }
    }

    /// Installs the input → 16 kHz-mono-Float32 tap exactly once. The
    /// closure captures only Sendable locks + the converter (used solely
    /// from the single tap thread), never the @MainActor `self`.
    private func installTapIfNeeded() throws {
        guard !tapInstalled else { return }

        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else {
            throw NSError(
                domain: "Murmur.AudioRecorder", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "input format unavailable"]
            )
        }
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000, channels: 1, interleaved: false
            ),
            let converter = AVAudioConverter(from: hwFormat, to: target)
        else {
            throw NSError(
                domain: "Murmur.AudioRecorder", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "converter setup failed"]
            )
        }

        let cap = capturing
        let buf = captureBuffer
        let ratio = target.sampleRate / hwFormat.sampleRate

        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { pcm, _ in
            guard cap.withLock({ $0 }) else { return }
            let outCap = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCap)
            else { return }
            var fed = false
            var convErr: NSError?
            converter.convert(to: out, error: &convErr) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return pcm
            }
            guard convErr == nil, let chan = out.floatChannelData, out.frameLength > 0
            else { return }
            let slice = Array(UnsafeBufferPointer(start: chan[0], count: Int(out.frameLength)))
            buf.withLock { $0.append(contentsOf: slice) }
        }
        tapInstalled = true
    }

    private static func ensureMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
        default:
            return false
        }
    }

    private static func micStatusString() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }
}
