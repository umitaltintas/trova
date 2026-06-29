import XCTest
@testable import TrovaCore

final class ToolAgentTests: XCTestCase {

    private final class Counter { var n = 0 }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func store() throws -> IndexStore {
        let store = try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-agent-\(UUID().uuidString).sqlite"))
        try store.upsert([MessageRecord(
            id: "1", messageID: nil, accountID: "A", mailbox: "INBOX", filePath: "/tmp/1",
            fromName: "Ali", fromAddress: "ali@x.com", toField: nil, ccField: nil,
            subject: "Kira sözleşmesi", date: Date(), snippet: "kira sözleşmeniz doluyor",
            body: "Daire kira sözleşmeniz bu ay doluyor, yenileyin.", indexedAt: Date(),
            threadKey: "s:kira sözleşmesi", parserVersion: 1)])
        return store
    }

    /// Ajan: ara (search_mail) → oku (read_mail) → yanıtla. Üç turlu döngü.
    func testAgentSearchReadAnswerLoop() throws {
        let counter = Counter()
        MockURLProtocol.handler = { request in
            counter.n += 1
            let message: [String: Any]
            switch counter.n {
            case 1:
                message = ["role": "assistant", "content": NSNull(), "tool_calls": [
                    ["id": "c1", "type": "function",
                     "function": ["name": "search_mail", "arguments": "{\"query\":\"kira\"}"]]]]
            case 2:
                message = ["role": "assistant", "content": NSNull(), "tool_calls": [
                    ["id": "c2", "type": "function",
                     "function": ["name": "read_mail", "arguments": "{\"handle\":\"m1\"}"]]]]
            default:
                message = ["role": "assistant", "content": "Kira maili m1 içinde bulundu."]
            }
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": message]]])
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, data)
        }

        let llm = OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"),
            session: session())
        let agent = ToolAgent(store: try store(), embedder: nil, llm: llm)

        var seen: [AgentStep.Kind] = []
        let run = try agent.run("kira sözleşmem ne zaman doluyor?") { seen.append($0.kind) }

        XCTAssertEqual(run.answer, "Kira maili m1 içinde bulundu.")
        XCTAssertEqual(run.cited.map(\.id), ["1"])              // okunan mail kaynak oldu
        XCTAssertEqual(seen, [.search, .read, .answer])         // adım sırası
        XCTAssertEqual(counter.n, 3)                            // 3 LLM turu
    }
}
