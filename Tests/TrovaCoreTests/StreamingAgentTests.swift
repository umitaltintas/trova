import XCTest
@testable import TrovaCore

/// Akışlı (streaming) ajan döngüsünün uçtan uca testi: MockURLProtocol her tur için SSE yanıtı
/// döndürür; ara turlar tool_call (search_mail → read_mail) akıtır, son tur nihai yanıtı token
/// token akıtır. `runStreaming`'in delta'ları SIRAYLA ilettiğini ve `AgentRun`'ın `run()` ile
/// aynı sonucu (answer + cited) ürettiğini doğrular.
final class StreamingAgentTests: XCTestCase {

    private final class Counter { var n = 0 }

    /// onAnswerDelta @Sendable olduğundan thread-güvenli sıralı toplayıcı.
    private final class DeltaBox: @unchecked Sendable {
        private let lock = NSLock()
        private var parts: [String] = []
        func append(_ s: String) { lock.lock(); parts.append(s); lock.unlock() }
        func all() -> [String] { lock.lock(); defer { lock.unlock() }; return parts }
        func joined() -> String { all().joined() }
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func store() throws -> IndexStore {
        let store = try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-stream-\(UUID().uuidString).sqlite"))
        try store.upsert([MessageRecord(
            id: "1", messageID: nil, accountID: "A", mailbox: "INBOX", filePath: "/tmp/1",
            fromName: "Ali", fromAddress: "ali@x.com", toField: nil, ccField: nil,
            subject: "Kira sözleşmesi", date: Date(), snippet: "kira sözleşmeniz doluyor",
            body: "Daire kira sözleşmeniz bu ay doluyor, yenileyin.", indexedAt: Date(),
            threadKey: "s:kira sözleşmesi", parserVersion: 1)])
        return store
    }

    /// SSE gövdesi: satırlar + `[DONE]` sonlandırıcı, satır sonlarıyla.
    private func sse(_ lines: [String]) -> Data {
        Data((lines + ["data: [DONE]"]).joined(separator: "\n").appending("\n").utf8)
    }

    func testStreamingAgentSearchReadAnswer() async throws {
        // Tur 1: search_mail tool_call (id+name ilk chunk, arguments fragmanı sonraki chunk'ta).
        let body1 = sse([
            #"data: {"choices":[{"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"search_mail","arguments":""}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"query\":\"kira\"}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        ])
        // Tur 2: read_mail tool_call (m1'i oku → kaynak/cited olur).
        let body2 = sse([
            #"data: {"choices":[{"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"c2","type":"function","function":{"name":"read_mail","arguments":"{\"handle\":\"m1\"}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        ])
        // Tur 3: nihai yanıt iki içerik parçası hâlinde akar.
        let body3 = sse([
            #"data: {"choices":[{"delta":{"content":"Kira "}}]}"#,
            #"data: {"choices":[{"delta":{"content":"maili m1 içinde bulundu."}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
        ])

        let counter = Counter()
        MockURLProtocol.handler = { request in
            counter.n += 1
            let body = counter.n == 1 ? body1 : (counter.n == 2 ? body2 : body3)
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, body)
        }

        let llm = OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"),
            session: session())
        let agent = ToolAgent(store: try store(), embedder: nil, llm: llm)

        let box = DeltaBox()
        let run = try await agent.runStreaming("kira sözleşmem ne zaman doluyor?") { box.append($0) }

        XCTAssertEqual(run.answer, "Kira maili m1 içinde bulundu.")
        XCTAssertEqual(run.cited.map(\.id), ["1"])                     // okunan mail kaynak oldu
        XCTAssertEqual(box.all(), ["Kira ", "maili m1 içinde bulundu."]) // delta'lar SIRAYLA aktı
        XCTAssertEqual(box.joined(), run.answer)                        // akan metin == nihai yanıt
        XCTAssertEqual(counter.n, 3)                                    // 3 LLM turu
    }
}
