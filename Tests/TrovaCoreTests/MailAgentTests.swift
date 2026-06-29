import XCTest
@testable import TrovaCore

final class MailAgentTests: XCTestCase {

    private func hit(_ id: String, _ subject: String) -> SearchHit {
        SearchHit(id: id, subject: subject, fromName: "X", fromAddress: "x@y.z",
                  mailbox: "INBOX", date: nil, snippet: "snippet \(subject)", score: 0)
    }

    func testParseAnswerMapsRefsAndSortsByRelevance() throws {
        let candidates = [hit("a", "Kira"), hit("b", "Fatura"), hit("c", "Maç")]
        let content = """
        İşte sonuç:
        ```json
        {"summary":"İki ilgili mail bulundu.",
         "results":[{"ref":2,"relevance":0.6,"reason":"fatura"},
                    {"ref":1,"relevance":0.95,"reason":"kira sözleşmesi"}]}
        ```
        """
        let answer = try MailAgent.parseAnswer(content, candidates: candidates)
        XCTAssertEqual(answer.summary, "İki ilgili mail bulundu.")
        XCTAssertEqual(answer.ranked.map(\.hit.id), ["a", "b"])   // relevance'a göre sıralı
        XCTAssertEqual(answer.ranked.first?.reason, "kira sözleşmesi")
    }

    func testParseAnswerIgnoresOutOfRangeRefs() throws {
        let candidates = [hit("a", "Kira")]
        let content = #"{"summary":"x","results":[{"ref":5,"relevance":1,"reason":"yok"},{"ref":1,"relevance":0.5,"reason":"var"}]}"#
        let answer = try MailAgent.parseAnswer(content, candidates: candidates)
        XCTAssertEqual(answer.ranked.map(\.hit.id), ["a"])        // ref 5 atılır
    }

    func testExtractJSONStripsProse() {
        let raw = "Tabii, işte:\n{\"summary\":\"ok\",\"results\":[]}\nUmarım yardımcı olur."
        XCTAssertEqual(MailAgent.extractJSON(raw), "{\"summary\":\"ok\",\"results\":[]}")
    }

    func testBuildPromptNumbersCandidates() {
        let prompt = MailAgent.buildPrompt(question: "kira", candidates: [hit("a", "Kira sözleşmesi")], topK: 5)
        XCTAssertTrue(prompt.contains("Soru: kira"))
        XCTAssertTrue(prompt.contains("[1] Konu: Kira sözleşmesi"))
    }
}

final class OpenRouterClientTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testCompleteParsesContent() throws {
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url!.absoluteString.hasSuffix("/chat/completions"))
            let json = #"{"choices":[{"message":{"role":"assistant","content":"merhaba"}}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(json.utf8))
        }
        let client = OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"),
            session: session())
        let out = try client.complete(messages: [.init(role: "user", content: "selam")])
        XCTAssertEqual(out, "merhaba")
    }

    func testFromEnvironment() {
        XCTAssertNil(OpenRouterClient.fromEnvironment([:]))
        let client = OpenRouterClient.fromEnvironment([
            "OPENROUTER_API_KEY": "k", "EIDX_LLM_MODEL": "openai/gpt-4o-mini",
        ])
        XCTAssertEqual(client?.model, "openai/gpt-4o-mini")
    }
}
