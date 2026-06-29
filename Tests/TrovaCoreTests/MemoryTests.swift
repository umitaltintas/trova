import XCTest
@testable import TrovaCore

/// Ajanın oturumlar arası kalıcı hafızası (agent_memory) için testler.
final class MemoryTests: XCTestCase {

    private final class Counter { var n = 0 }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-memory-\(UUID().uuidString).sqlite"))
    }

    func testSaveAndFetchRoundTrip() throws {
        let store = try makeStore()
        try store.saveMemory("Kullanıcı haber bültenlerini özetlemeyi sever")
        try store.saveMemory("Sık görüşülen kişi: Ali")
        let memories = try store.allMemories()
        XCTAssertEqual(memories.count, 2)
        XCTAssertEqual(Set(memories.map(\.text)),
            ["Kullanıcı haber bültenlerini özetlemeyi sever", "Sık görüşülen kişi: Ali"])
    }

    func testDuplicateNotDoubleSaved() throws {
        let store = try makeStore()
        try store.saveMemory("Aynı bilgi")
        try store.saveMemory("Aynı bilgi")
        try store.saveMemory("  Aynı bilgi  ")   // kırpıldıktan sonra aynı → eklenmez
        XCTAssertEqual(try store.memoryCount(), 1)
    }

    func testEmptyNotSaved() throws {
        let store = try makeStore()
        try store.saveMemory("")
        try store.saveMemory("   \n\t  ")
        XCTAssertEqual(try store.memoryCount(), 0)
    }

    func testClearEmpties() throws {
        let store = try makeStore()
        try store.saveMemory("bir")
        try store.saveMemory("iki")
        XCTAssertEqual(try store.memoryCount(), 2)
        try store.clearMemories()
        XCTAssertEqual(try store.memoryCount(), 0)
        XCTAssertTrue(try store.allMemories().isEmpty)
    }

    /// Ajan turu: model `remember` aracını çağırır, sonra yanıt verir.
    /// Tur sonunda bilgi SQLite'ta kalıcı olmalı.
    func testAgentRemembersFact() throws {
        let fact = "Kullanıcı haber bültenlerini her zaman özetlememi ister"
        let counter = Counter()
        MockURLProtocol.handler = { request in
            counter.n += 1
            let message: [String: Any]
            switch counter.n {
            case 1:
                message = ["role": "assistant", "content": NSNull(), "tool_calls": [
                    ["id": "c1", "type": "function",
                     "function": ["name": "remember",
                                  "arguments": "{\"fact\":\"\(fact)\"}"]]]]
            default:
                message = ["role": "assistant", "content": "Tamam, bunu hatırlayacağım."]
            }
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": message]]])
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, data)
        }

        let store = try makeStore()
        let llm = OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"),
            session: session())
        let agent = ToolAgent(store: store, embedder: nil, llm: llm)

        let run = try agent.run("Bundan sonra bültenleri özetle.")

        XCTAssertEqual(run.answer, "Tamam, bunu hatırlayacağım.")
        XCTAssertEqual(try store.memoryCount(), 1)
        XCTAssertEqual(try store.allMemories().first?.text, fact)
        XCTAssertEqual(counter.n, 2)
    }
}
