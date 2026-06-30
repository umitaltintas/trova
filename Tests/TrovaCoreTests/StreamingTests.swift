import XCTest
@testable import TrovaCore

final class StreamingTests: XCTestCase {

    // MARK: - Saf SSE satır ayrıştırma

    func testParsesContentDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"Merhaba"}}]}"#
        XCTAssertEqual(OpenRouterClient.streamEvent(fromLine: line), .content("Merhaba"))
    }

    func testParsesDone() {
        XCTAssertEqual(OpenRouterClient.streamEvent(fromLine: "data: [DONE]"), .done)
    }

    func testIgnoresNonDataLines() {
        XCTAssertEqual(OpenRouterClient.streamEvent(fromLine: ""), .ignore)
        XCTAssertEqual(OpenRouterClient.streamEvent(fromLine: ": keep-alive"), .ignore)
    }

    func testIgnoresDeltaWithoutContent() {
        // Rol/araç delta'ları (içerik yok) atlanır.
        let line = #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#
        XCTAssertEqual(OpenRouterClient.streamEvent(fromLine: line), .ignore)
    }

    // MARK: - completeStreaming (MockURLProtocol ile uçtan uca)

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testStreamingAccumulatesAndCallsDelta() async throws {
        let body = [
            #"data: {"choices":[{"delta":{"content":"Mer"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"haba"}}]}"#,
            "data: [DONE]",
        ].joined(separator: "\n") + "\n"

        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(body.utf8))
        }
        let client = OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"),
            session: session())

        let box = DeltaBox()
        let full = try await client.completeStreaming(
            messages: [.init(role: "user", content: "selam")]) { box.append($0) }

        XCTAssertEqual(full, "Merhaba")
        XCTAssertEqual(box.joined(), "Merhaba")
    }

    /// onDelta @Sendable olduğundan thread-güvenli küçük bir toplayıcı.
    private final class DeltaBox: @unchecked Sendable {
        private let lock = NSLock()
        private var parts: [String] = []
        func append(_ s: String) { lock.lock(); parts.append(s); lock.unlock() }
        func joined() -> String { lock.lock(); defer { lock.unlock() }; return parts.joined() }
    }
}
