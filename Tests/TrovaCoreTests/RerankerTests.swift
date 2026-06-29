import XCTest
@testable import TrovaCore

final class RerankerTests: XCTestCase {

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// İçeriği sabit dönen bir OpenRouter istemcisi kurar (MockURLProtocol üzerinden).
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

    /// id'leri "1","2","3" olan üç sentetik aday (özgün sıra korunur).
    private func candidates() -> [SearchHit] {
        (1...3).map { index in
            SearchHit(id: "\(index)", subject: "Konu \(index)", fromName: "Gönderen \(index)",
                      fromAddress: "u\(index)@x.com", mailbox: "INBOX", date: Date(),
                      snippet: "özet \(index)", score: Double(3 - index))
        }
    }

    /// Model bir permütasyon ("2,3,1") döndürür → sonuçlar o sıraya göre yeniden dizilir.
    func testReordersByModelPermutation() throws {
        let reranker = LLMReranker(llm: client(returning: "2,3,1"))
        let result = try reranker.rerank(query: "kira", candidates: candidates(), topK: 3)
        XCTAssertEqual(result.map(\.id), ["2", "3", "1"])
    }

    /// topK sınırı uygulanır (permütasyonun ilk K'sı).
    func testRespectsTopK() throws {
        let reranker = LLMReranker(llm: client(returning: "2,3,1"))
        let result = try reranker.rerank(query: "kira", candidates: candidates(), topK: 2)
        XCTAssertEqual(result.map(\.id), ["2", "3"])
    }

    /// Bozuk/anlamsız çıktı ("banana") → adaylar olduğu gibi (özgün sıra) döner.
    func testMalformedOutputFallsBack() throws {
        let reranker = LLMReranker(llm: client(returning: "banana"))
        let result = try reranker.rerank(query: "kira", candidates: candidates(), topK: 3)
        XCTAssertEqual(result.map(\.id), ["1", "2", "3"])
    }

    /// Eksik numara ("3") → atlananlar özgün sırayla sona eklenir (hiç aday kaybolmaz).
    func testOmittedCandidatesAppended() throws {
        let reranker = LLMReranker(llm: client(returning: "3"))
        let result = try reranker.rerank(query: "kira", candidates: candidates(), topK: 3)
        XCTAssertEqual(result.map(\.id), ["3", "1", "2"])
    }
}
