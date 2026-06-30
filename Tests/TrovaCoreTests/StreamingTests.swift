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

    // MARK: - Saf SSE tool_call biriktirici (StreamAccumulator)

    /// (a) Yalnız içerik akışı → parçalar birleşir, tool yok.
    func testAccumulatorMergesContentOnly() {
        var acc = OpenRouterClient.StreamAccumulator()
        XCTAssertEqual(acc.consume(line: #"data: {"choices":[{"delta":{"content":"Mer"}}]}"#), "Mer")
        XCTAssertEqual(acc.consume(line: #"data: {"choices":[{"delta":{"content":"haba"}}]}"#), "haba")
        let resp = acc.response()
        XCTAssertEqual(resp.content, "Merhaba")
        XCTAssertTrue(resp.toolCalls.isEmpty)
        XCTAssertNil(resp.rawAssistantMessage["tool_calls"])
    }

    /// (b) tool_call 3 parçaya bölünmüş: id+name ilk chunk, arguments fragmanları sonraki chunk'larda.
    func testAccumulatorAssemblesSplitToolCall() {
        var acc = OpenRouterClient.StreamAccumulator()
        _ = acc.consume(line: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"search_mail","arguments":""}}]}}]}"#)
        _ = acc.consume(line: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"query\":\"ki"}}]}}]}"#)
        _ = acc.consume(line: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ra\"}"}}]}}]}"#)
        let resp = acc.response()
        XCTAssertEqual(resp.toolCalls.count, 1)
        XCTAssertEqual(resp.toolCalls[0].id, "c1")
        XCTAssertEqual(resp.toolCalls[0].name, "search_mail")
        XCTAssertEqual(resp.toolCalls[0].arguments, #"{"query":"kira"}"#)
        XCTAssertNil(resp.content)   // içerik gelmedi → nil
        // rawAssistantMessage history'ye aynen eklenebilir (assistant + tool_calls) olmalı.
        XCTAssertEqual(resp.rawAssistantMessage["role"] as? String, "assistant")
        XCTAssertNotNil(resp.rawAssistantMessage["tool_calls"])
    }

    /// (c) finish_reason "tool_calls" vs "stop" ayrımı yakalanır.
    func testAccumulatorCapturesFinishReason() {
        var toolAcc = OpenRouterClient.StreamAccumulator()
        _ = toolAcc.consume(line: #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#)
        XCTAssertEqual(toolAcc.finishReason, "tool_calls")

        var stopAcc = OpenRouterClient.StreamAccumulator()
        _ = stopAcc.consume(line: #"data: {"choices":[{"delta":{"content":"bitti"},"finish_reason":"stop"}]}"#)
        XCTAssertEqual(stopAcc.finishReason, "stop")
    }

    /// (d) `[DONE]` sonlandırıcı + data olmayan satırlar güvenle yok sayılır.
    func testAccumulatorHandlesDoneSentinel() {
        var acc = OpenRouterClient.StreamAccumulator()
        XCTAssertFalse(acc.isDone)
        XCTAssertNil(acc.consume(line: "data: [DONE]"))
        XCTAssertTrue(acc.isDone)
        XCTAssertNil(acc.consume(line: ": keep-alive"))
        XCTAssertNil(acc.consume(line: ""))
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
