import XCTest
@testable import TrovaCore

final class ThreadSummarizerTests: XCTestCase {

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func client(returning content: String) -> OpenRouterClient {
        MockURLProtocol.handler = { request in
            let data = try JSONSerialization.data(withJSONObject:
                ["choices": [["message": ["role": "assistant", "content": content]]]])
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, data)
        }
        return OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"),
            session: session())
    }

    private let entries = [
        ThreadEntry(from: "Ali", date: Date(timeIntervalSince1970: 0), body: "Sözleşme taslağını ekledim."),
        ThreadEntry(from: "Veli", date: Date(timeIntervalSince1970: 86_400), body: "İmzaladım, teşekkürler."),
    ]

    func testSummarizeReturnsModelOutput() throws {
        let summarizer = ThreadSummarizer(llm: client(returning: "## Özet\nSözleşme imzalandı."))
        let result = try summarizer.summarize(entries)
        XCTAssertTrue(result.contains("Sözleşme imzalandı."))
    }

    func testEmptyReturnsFriendlyMessageWithoutLLM() throws {
        // Boş girdi LLM'e gitmeden dostça mesaj döndürmeli (handler kurulmamış olsa da çağrılmamalı).
        let summarizer = ThreadSummarizer(llm: client(returning: "OLMAMALI"))
        XCTAssertEqual(try summarizer.summarize([]), "Özetlenecek mesaj yok.")
    }

    func testBuildPromptIncludesSendersBodiesAndOrder() {
        let prompt = ThreadSummarizer.buildPrompt(entries)
        XCTAssertTrue(prompt.contains("[1] Kimden: Ali"))
        XCTAssertTrue(prompt.contains("[2] Kimden: Veli"))
        XCTAssertTrue(prompt.contains("Sözleşme taslağını ekledim."))
        XCTAssertTrue(prompt.contains("İmzaladım, teşekkürler."))
    }

    func testBuildPromptHandlesEmptyBody() {
        let prompt = ThreadSummarizer.buildPrompt([ThreadEntry(from: "X", date: nil, body: "   ")])
        XCTAssertTrue(prompt.contains("(boş)"))
        XCTAssertTrue(prompt.contains("Tarih: ?"))
    }
}
