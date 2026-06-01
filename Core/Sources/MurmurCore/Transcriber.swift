import Foundation
import WhisperKit

/// Turns a recorded WAV into text. Protocol seam so tests inject a fake
/// instead of downloading (~140 MB) and running a Core ML model.
public protocol Transcribing: Sendable {
    func transcribe(wavURL: URL) async throws -> String
}

/// WhisperKit-backed `Transcribing`. An `actor` so the lazy model load runs
/// exactly once even under concurrent calls. The model is fetched into
/// `downloadBase` on first use; later calls reuse the loaded instance.
public actor WhisperKitTranscriber: Transcribing {
    private let modelName: String
    private let downloadBase: URL?
    private var whisperKit: WhisperKit?
    private var loadTask: Task<WhisperKit, Swift.Error>?

    public init(modelName: String = "openai_whisper-base", downloadBase: URL? = nil) {
        self.modelName = modelName
        self.downloadBase = downloadBase
    }

    public func transcribe(wavURL: URL) async throws -> String {
        let kit = try await loadedModel()
        // detectLanguage:true is required — WhisperKit's default decode prefills
        // the English language token when language is nil and detection is off
        // (default detectLanguage resolves to !usePrefillPrompt == false), which
        // makes non-English speech come out as an English translation.
        let options = DecodingOptions(task: .transcribe, detectLanguage: true)
        let results = try await kit.transcribe(audioPath: wavURL.path, decodeOptions: options)
        return results
            .map { ScriptNormalizer.normalize($0.text, language: $0.language) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Loads the model once. The in-flight `Task` is cached so concurrent
    /// callers awaiting across the `await WhisperKit(...)` suspension point
    /// share a single download instead of each starting their own.
    private func loadedModel() async throws -> WhisperKit {
        if let whisperKit { return whisperKit }
        if let loadTask { return try await loadTask.value }

        let modelName = self.modelName
        let downloadBase = self.downloadBase
        let task = Task {
            try await WhisperKit(WhisperKitConfig(model: modelName, downloadBase: downloadBase))
        }
        loadTask = task
        do {
            let kit = try await task.value
            whisperKit = kit
            loadTask = nil
            return kit
        } catch {
            loadTask = nil
            throw error
        }
    }
}

/// `@MainActor` view model the SwiftUI layer binds to. Owns a `Transcribing`
/// engine and exposes transcribe state. Idempotent — a call while one is in
/// flight is a no-op (matches `AudioRecorder.start/stop`).
@MainActor
public final class Transcriber: ObservableObject {
    @Published public private(set) var isTranscribing: Bool = false
    @Published public private(set) var transcript: String?
    @Published public private(set) var lastError: String?

    private let engine: any Transcribing

    public init(engine: any Transcribing) {
        self.engine = engine
    }

    public func transcribe(wavURL: URL) async {
        guard !isTranscribing else { return }
        isTranscribing = true
        transcript = nil
        lastError = nil
        defer { isTranscribing = false }
        do {
            transcript = try await engine.transcribe(wavURL: wavURL)
        } catch {
            lastError = "Transcribe failed: \(error.localizedDescription)"
        }
    }
}

public extension Transcriber {
    /// Default wiring: WhisperKit `base`, model cache under the app's
    /// Application Support container (sandbox-redirected at runtime).
    static func makeDefault() -> Transcriber {
        let modelsDir = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Murmur", isDirectory: true)
        .appendingPathComponent("Models", isDirectory: true)
        var resolvedBase = modelsDir
        if let modelsDir {
            do {
                try FileManager.default.createDirectory(
                    at: modelsDir,
                    withIntermediateDirectories: true
                )
            } catch {
                // Can't create our dir — hand WhisperKit nil so it uses its
                // own default cache instead of a path that doesn't exist.
                resolvedBase = nil
            }
        }
        let onDevice = WhisperKitTranscriber(downloadBase: resolvedBase)
        // Wrap in the cloud fallback only when a Groq key is present; otherwise
        // stay pure on-device (no network, no cloud hop).
        if let groq = GroqConfig.fromEnvironment() {
            return Transcriber(engine: FallbackTranscriber(
                primary: onDevice,
                fallback: GroqClient(config: groq)
            ))
        }
        return Transcriber(engine: onDevice)
    }
}
