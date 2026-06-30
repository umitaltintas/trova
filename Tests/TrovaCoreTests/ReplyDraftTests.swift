import XCTest
@testable import TrovaCore

final class ReplyDraftTests: XCTestCase {

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - Saf mesaj/istem kurulumu

    func testMessagesIncludeSystemPromptAndUser() {
        let messages = ReplyDraft.messages(from: "Ali", subject: "Toplantı", body: "Yarın uygun musunuz?")
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.role, "system")
        XCTAssertEqual(messages.first?.content, ReplyDraft.systemPrompt)
        XCTAssertEqual(messages.last?.role, "user")
    }

    func testUserMessageIncludesSenderSubjectAndBody() {
        let prompt = ReplyDraft.buildPrompt(from: "Ali Veli", subject: "Sözleşme", body: "Taslağı ekledim.")
        XCTAssertTrue(prompt.contains("Gönderen: Ali Veli"))
        XCTAssertTrue(prompt.contains("Konu: Sözleşme"))
        XCTAssertTrue(prompt.contains("Taslağı ekledim."))
    }

    func testLongBodyIsTrimmed() {
        let long = String(repeating: "a", count: 10_000)
        let prompt = ReplyDraft.buildPrompt(from: "X", subject: "K", body: long)
        // Gövde 4000 karaktere kırpılmalı: ham gövdenin tamamı istemde yer almaz.
        XCTAssertLessThan(prompt.count, long.count)
        XCTAssertFalse(prompt.contains(String(repeating: "a", count: 4001)))
        XCTAssertTrue(prompt.contains(String(repeating: "a", count: 4000)))
    }

    func testEmptyFieldsAreSafe() {
        let prompt = ReplyDraft.buildPrompt(from: nil, subject: "   ", body: "   ")
        XCTAssertTrue(prompt.contains("Gönderen: ?"))
        XCTAssertTrue(prompt.contains("Konu: (konu yok)"))
        XCTAssertTrue(prompt.contains("(gövde yok)"))
    }

    // MARK: - completeStreaming ile uçtan uca taslak akışı (MockURLProtocol)

    func testStreamingProducesDraftEndToEnd() async throws {
        let body = [
            #"data: {"choices":[{"delta":{"content":"Merhaba Ali,"}}]}"#,
            #"data: {"choices":[{"delta":{"content":" teşekkürler."}}]}"#,
            "data: [DONE]",
        ].joined(separator: "\n") + "\n"

        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(body.utf8))
        }
        let client = OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"),
            session: session())

        let messages = ReplyDraft.messages(from: "Ali", subject: "Toplantı", body: "Yarın uygun musunuz?")
        let draft = try await client.completeStreaming(messages: messages) { _ in }
        XCTAssertEqual(draft, "Merhaba Ali, teşekkürler.")
    }
}
