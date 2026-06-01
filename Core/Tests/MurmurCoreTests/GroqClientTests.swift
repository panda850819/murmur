import XCTest
@testable import MurmurCore

final class GroqClientTests: XCTestCase {
    // MARK: Config resolution

    func testConfigFromEnvironmentPresent() {
        let cfg = GroqConfig.fromEnvironment(["GROQ_API_KEY": "gsk_test"])
        XCTAssertEqual(cfg?.apiKey, "gsk_test")
    }

    func testConfigMissingKeyIsNil() {
        XCTAssertNil(GroqConfig.fromEnvironment([:]))
    }

    func testConfigEmptyKeyIsNil() {
        XCTAssertNil(GroqConfig.fromEnvironment(["GROQ_API_KEY": ""]))
    }

    // MARK: Chat response decode (pure helper)

    func testDecodeChatContentTrims() throws {
        let json = #"""
        {"choices":[{"message":{"role":"assistant","content":"  cleaned text  "}}]}
        """#.data(using: .utf8)!
        XCTAssertEqual(try GroqClient.decodeChatContent(json), "cleaned text")
    }

    func testDecodeChatContentEmptyChoicesThrows() {
        let json = #"{"choices":[]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try GroqClient.decodeChatContent(json)) { error in
            XCTAssertEqual(error as? GroqError, .emptyResponse)
        }
    }

    func testDecodeChatContentMalformedThrows() {
        let json = #"{"unexpected":true}"#.data(using: .utf8)!
        XCTAssertThrowsError(try GroqClient.decodeChatContent(json))
    }

    // MARK: Transcription response decode (pure helper)

    func testDecodeTranscriptionText() throws {
        let json = #"{"text":"  hello world  "}"#.data(using: .utf8)!
        XCTAssertEqual(try GroqClient.decodeTranscriptionText(json), "hello world")
    }

    // MARK: Multipart body shape

    func testTranscriptionBodyContainsModelAndFile() {
        let audio = Data([0x52, 0x49, 0x46, 0x46])  // "RIFF"
        let body = GroqClient.encodeTranscriptionBody(
            audio: audio,
            filename: "rec.wav",
            model: "whisper-large-v3-turbo",
            boundary: "B"
        )
        let asString = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(asString.contains("name=\"model\""))
        XCTAssertTrue(asString.contains("whisper-large-v3-turbo"))
        XCTAssertTrue(asString.contains("filename=\"rec.wav\""))
        XCTAssertTrue(asString.contains("--B--"), "must terminate with closing boundary")
    }

    // MARK: Chat body shape

    func testChatBodyEncodesSystemAndUserMessages() throws {
        let data = try GroqClient.encodeChatBody(model: "m", system: "sys", user: "usr")
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["model"] as? String, "m")
        let messages = obj?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.first?["role"] as? String, "system")
        XCTAssertEqual(messages?.first?["content"] as? String, "sys")
        XCTAssertEqual(messages?.last?["role"] as? String, "user")
        XCTAssertEqual(messages?.last?["content"] as? String, "usr")
    }

    // MARK: HTTP error mapping

    func testThrowIfHTTPErrorOnNon2xx() {
        let url = URL(string: "https://api.groq.com")!
        let resp = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try GroqClient.throwIfHTTPError(resp, Data("unauthorized".utf8))) { error in
            XCTAssertEqual(error as? GroqError, .http(status: 401, body: "unauthorized"))
        }
    }

    func testThrowIfHTTPErrorPassesOn2xx() throws {
        let url = URL(string: "https://api.groq.com")!
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertNoThrow(try GroqClient.throwIfHTTPError(resp, Data()))
    }
}
