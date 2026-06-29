import XCTest
@testable import TrovaCore

/// Yanıt doğrulama (self-critique) akışını test eder: ajan ara → oku → yanıtla,
/// ardından `verify: true` ise ek bir doğrulama çağrısı yapılır.
final class VerifierTests: XCTestCase {

    private final class Counter { var n = 0 }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func store() throws -> IndexStore {
        let store = try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-verify-\(UUID().uuidString).sqlite"))
        try store.upsert([MessageRecord(
            id: "1", messageID: nil, accountID: "A", mailbox: "INBOX", filePath: "/tmp/1",
            fromName: "Ali", fromAddress: "ali@x.com", toField: nil, ccField: nil,
            subject: "Kira sözleşmesi", date: Date(), snippet: "kira sözleşmeniz doluyor",
            body: "Daire kira sözleşmeniz bu ay doluyor, yenileyin.", indexedAt: Date(),
            threadKey: "s:kira sözleşmesi", parserVersion: 1)])
        return store
    }

    private func llm(_ session: URLSession) -> OpenRouterClient {
        OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"),
            session: session)
    }

    /// Asistan mesajı için choices sarmalayıcısı üretir.
    private func reply(_ message: [String: Any], for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": message]]])
        return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                httpVersion: nil, headerFields: nil)!, data)
    }

    private func searchCall() -> [String: Any] {
        ["role": "assistant", "content": NSNull(), "tool_calls": [
            ["id": "c1", "type": "function",
             "function": ["name": "search_mail", "arguments": "{\"query\":\"kira\"}"]]]]
    }

    private func readCall() -> [String: Any] {
        ["role": "assistant", "content": NSNull(), "tool_calls": [
            ["id": "c2", "type": "function",
             "function": ["name": "read_mail", "arguments": "{\"handle\":\"m1\"}"]]]]
    }

    /// verify=true: ara → oku → yanıtla → doğrula. 4. tur "grounded" döndürür.
    func testVerifyGrounded() throws {
        let counter = Counter()
        MockURLProtocol.handler = { request in
            counter.n += 1
            switch counter.n {
            case 1: return try self.reply(self.searchCall(), for: request)
            case 2: return try self.reply(self.readCall(), for: request)
            case 3: return try self.reply(["role": "assistant", "content": "Kira sözleşmen bu ay doluyor (m1)."], for: request)
            default: return try self.reply(["role": "assistant",
                "content": "{\"verdict\":\"grounded\",\"issues\":[]}"], for: request)
            }
        }
        let agent = ToolAgent(store: try store(), embedder: nil, llm: llm(session()))

        let run = try agent.run("kira sözleşmem ne zaman doluyor?", verify: true)

        XCTAssertEqual(run.cited.map(\.id), ["1"])
        XCTAssertEqual(run.verification?.verdict, .grounded)
        XCTAssertEqual(run.verification?.issues, [])
        XCTAssertEqual(counter.n, 4)   // 3 ajan turu + 1 doğrulama çağrısı
    }

    /// verify=false: hiç doğrulama çağrısı yapılmaz, verification nil olur.
    func testVerifyDisabledReturnsNil() throws {
        let counter = Counter()
        MockURLProtocol.handler = { request in
            counter.n += 1
            switch counter.n {
            case 1: return try self.reply(self.searchCall(), for: request)
            case 2: return try self.reply(self.readCall(), for: request)
            default: return try self.reply(["role": "assistant", "content": "Kira maili m1 içinde."], for: request)
            }
        }
        let agent = ToolAgent(store: try store(), embedder: nil, llm: llm(session()))

        let run = try agent.run("kira sözleşmem ne zaman doluyor?", verify: false)

        XCTAssertNil(run.verification)
        XCTAssertEqual(counter.n, 3)   // doğrulama çağrısı yapılmadı
    }

    /// Doğrulayıcı geçersiz JSON döndürürse nazikçe .unknown verdict döner.
    func testMalformedVerifierJSON() throws {
        let counter = Counter()
        MockURLProtocol.handler = { request in
            counter.n += 1
            switch counter.n {
            case 1: return try self.reply(self.searchCall(), for: request)
            case 2: return try self.reply(self.readCall(), for: request)
            case 3: return try self.reply(["role": "assistant", "content": "Kira maili m1 içinde."], for: request)
            default: return try self.reply(["role": "assistant", "content": "bu bir json değil"], for: request)
            }
        }
        let agent = ToolAgent(store: try store(), embedder: nil, llm: llm(session()))

        let run = try agent.run("kira sözleşmem ne zaman doluyor?", verify: true)

        XCTAssertEqual(run.verification?.verdict, .unknown)
        XCTAssertEqual(counter.n, 4)
    }
}
