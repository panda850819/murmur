import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The thin LLM seam. macOS enhance/cleanup and (later) the keyboard's
/// translate/edit behaviors all attach here. Sendable so it can cross the
/// actor boundary into `DictationCoordinator`.
public protocol LLMEnhancing: Sendable {
    /// Clean up dictated speech-to-text. Returns the cleaned text, same
    /// language and script. Throws on transport/decode failure — callers treat
    /// enhance as best-effort and fall back to the raw transcript.
    func enhance(_ text: String) async throws -> String
}

/// Groq connection settings. Key is resolved from `GROQ_API_KEY` for dogfood;
/// nil when unset so the app degrades to pure on-device, no cloud hop.
public struct GroqConfig: Sendable {
    public var apiKey: String
    public var chatModel: String
    public var transcribeModel: String
    public var baseURL: URL

    public init(
        apiKey: String,
        chatModel: String = "llama-3.3-70b-versatile",
        transcribeModel: String = "whisper-large-v3-turbo",
        baseURL: URL = URL(string: "https://api.groq.com/openai/v1")!
    ) {
        self.apiKey = apiKey
        self.chatModel = chatModel
        self.transcribeModel = transcribeModel
        self.baseURL = baseURL
    }

    /// Resolve from the environment. `nil` (not a crash) when the key is
    /// missing or empty — that is the signal to stay on-device-only.
    public static func fromEnvironment(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> GroqConfig? {
        guard let key = env["GROQ_API_KEY"], !key.isEmpty else { return nil }
        return GroqConfig(apiKey: key)
    }
}

public enum GroqError: Error, Equatable {
    case http(status: Int, body: String)
    case emptyResponse
    case decode(String)
}

/// Groq-backed chat (enhance) + audio transcription (cloud STT fallback).
/// An `actor` to be `Sendable` for both protocol conformances; the HTTP work
/// itself is stateless, the actor just satisfies isolation.
public actor GroqClient {
    private let config: GroqConfig
    private let session: URLSession

    public init(config: GroqConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: Chat (enhance / later translate+edit)

    private static let cleanupSystemPrompt = """
    You clean up dictated speech-to-text. Fix punctuation, capitalization, and \
    obvious transcription slips. Remove filler words (um, uh, like). Preserve the \
    original meaning, language, and script exactly. Do not translate. Do not \
    convert between Traditional and Simplified Chinese. Output only the cleaned \
    text, with no preamble, quotes, or commentary.
    """

    public func enhance(_ text: String) async throws -> String {
        try await chat(system: Self.cleanupSystemPrompt, user: text)
    }

    /// One-shot chat completion. The shared primitive translate/edit reuse.
    public func chat(system: String, user: String) async throws -> String {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encodeChatBody(model: config.chatModel, system: system, user: user)

        let (data, response) = try await session.data(for: request)
        try Self.throwIfHTTPError(response, data)
        return try Self.decodeChatContent(data)
    }

    // MARK: Transcription (Whisper cloud fallback)

    /// Upload a recorded WAV to Groq's Whisper endpoint. Used only as the
    /// fallback when on-device WhisperKit is unavailable or throws.
    public func transcribe(wavURL: URL) async throws -> String {
        let audio = try Data(contentsOf: wavURL)
        let boundary = "murmur-\(UUID().uuidString)"
        var request = URLRequest(url: config.baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.encodeTranscriptionBody(
            audio: audio,
            filename: wavURL.lastPathComponent,
            model: config.transcribeModel,
            boundary: boundary
        )

        let (data, response) = try await session.data(for: request)
        try Self.throwIfHTTPError(response, data)
        return try Self.decodeTranscriptionText(data)
    }
}

extension GroqClient: LLMEnhancing {}
extension GroqClient: Transcribing {}

// MARK: - Pure helpers (network-free, unit-testable)

extension GroqClient {
    static func throwIfHTTPError(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw GroqError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            )
        }
    }

    static func encodeChatBody(model: String, system: String, user: String) throws -> Data {
        let body = ChatRequest(
            model: model,
            temperature: 0.2,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user),
            ]
        )
        return try JSONEncoder().encode(body)
    }

    /// Parse the chat completion choice text. Trims surrounding whitespace.
    static func decodeChatContent(_ data: Data) throws -> String {
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw GroqError.decode("chat response: \(error.localizedDescription)")
        }
        guard let content = decoded.choices.first?.message.content else {
            throw GroqError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func encodeTranscriptionBody(
        audio: Data,
        filename: String,
        model: String,
        boundary: String
    ) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("json\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(audio)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }

    /// Groq audio transcription with `response_format=json` returns `{ "text": ... }`.
    static func decodeTranscriptionText(_ data: Data) throws -> String {
        let decoded: TranscriptionResponse
        do {
            decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        } catch {
            throw GroqError.decode("transcription response: \(error.localizedDescription)")
        }
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Wire types

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let temperature: Double
    let messages: [Message]
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private struct TranscriptionResponse: Decodable {
    let text: String
}
