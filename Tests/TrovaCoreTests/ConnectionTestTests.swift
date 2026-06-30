import XCTest
@testable import TrovaCore

final class ConnectionTestTests: XCTestCase {

    // MARK: - Saf sınıflandırma (classify)

    func testClassifyHTTPCodes() {
        XCTAssertEqual(ConnectionTest.classify(statusCode: 200, errorDescription: nil), .ok)
        XCTAssertEqual(ConnectionTest.classify(statusCode: 201, errorDescription: nil), .ok)
        XCTAssertEqual(ConnectionTest.classify(statusCode: 401, errorDescription: "x"), .unauthorized)
        XCTAssertEqual(ConnectionTest.classify(statusCode: 403, errorDescription: "x"), .unauthorized)
        XCTAssertEqual(ConnectionTest.classify(statusCode: 404, errorDescription: "x"), .notFound)
        XCTAssertEqual(ConnectionTest.classify(statusCode: 500, errorDescription: "x"), .unknown)
        XCTAssertEqual(ConnectionTest.classify(statusCode: 429, errorDescription: nil), .unknown)
    }

    func testClassifyNetworkAndUnknownWithoutCode() {
        // Kod yok + ağ açıklaması → network.
        XCTAssertEqual(ConnectionTest.classify(statusCode: nil, errorDescription: "Ağ hatası: offline"), .network)
        XCTAssertEqual(ConnectionTest.classify(statusCode: nil,
                       errorDescription: "The Internet connection appears to be offline."), .network)
        // Kod yok + tanınmayan açıklama → unknown.
        XCTAssertEqual(ConnectionTest.classify(statusCode: nil, errorDescription: "tuhaf bir şey"), .unknown)
        XCTAssertEqual(ConnectionTest.classify(statusCode: nil, errorDescription: nil), .unknown)
    }

    // MARK: - Türkçe mesajlar (message) — servis adı dâhil

    func testMessagesAreTurkishAndIncludeService() {
        XCTAssertEqual(ConnectionTest.message(service: "LLM", status: .ok, detail: nil),
                       "LLM: Bağlantı başarılı")
        XCTAssertEqual(ConnectionTest.message(service: "LLM", status: .unauthorized, detail: nil),
                       "LLM: Geçersiz API anahtarı")
        XCTAssertEqual(ConnectionTest.message(service: "Embedding", status: .notFound, detail: nil),
                       "Embedding: Model/uç nokta bulunamadı")
        XCTAssertEqual(ConnectionTest.message(service: "Embedding", status: .network, detail: nil),
                       "Embedding: Ağa ulaşılamadı")
    }

    func testUnknownMessageCarriesRawDetail() {
        let msg = ConnectionTest.message(service: "LLM", status: .unknown, detail: "boom 500")
        XCTAssertTrue(msg.hasPrefix("LLM: Bilinmeyen hata"))
        XCTAssertTrue(msg.contains("boom 500"))
        // Detay yoksa ham ek olmadan sade mesaj.
        XCTAssertEqual(ConnectionTest.message(service: "LLM", status: .unknown, detail: nil),
                       "LLM: Bilinmeyen hata")
    }

    // MARK: - result(): bilinen hata tiplerinden durum çıkarımı (saf)

    func testResultFromKnownErrorTypes() {
        XCTAssertEqual(ConnectionTest.result(service: "Embedding", error: nil).status, .ok)
        XCTAssertEqual(ConnectionTest.result(service: "Embedding",
                       error: EmbeddingError.http(status: 401, body: "no")).status, .unauthorized)
        XCTAssertEqual(ConnectionTest.result(service: "Embedding",
                       error: EmbeddingError.http(status: 404, body: "no")).status, .notFound)
        XCTAssertEqual(ConnectionTest.result(service: "Embedding",
                       error: EmbeddingError.transport("offline")).status, .network)
    }

    func testStatusCodeParsingFromText() {
        XCTAssertEqual(ConnectionTest.statusCode(fromText: "HTTP 404: not found"), 404)
        XCTAssertEqual(ConnectionTest.statusCode(fromText: "HTTP 401: {\"error\":\"key\"}"), 401)
        XCTAssertNil(ConnectionTest.statusCode(fromText: "tamamen alakasız metin"))
    }

    // MARK: - Uçtan uca: OpenRouterClient.complete + result (MockURLProtocol)

    private func makeClient() -> OpenRouterClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!,
                          apiKey: "test-key", model: "test-model"),
            session: URLSession(configuration: config))
    }

    /// Bir bağlantı testinin app'teki akışını taklit eder: complete çağır, sonucu/hatayı sınıflandır.
    private func liveResult(_ client: OpenRouterClient) -> ConnectionResult {
        do {
            _ = try client.complete(messages: [ChatMessage(role: "user", content: "ping")])
            return ConnectionTest.result(service: "LLM", error: nil)
        } catch {
            return ConnectionTest.result(service: "LLM", error: error)
        }
    }

    func testEndToEndSuccessProducesOk() {
        MockURLProtocol.handler = { request in
            let json = #"{"choices":[{"message":{"role":"assistant","content":"pong"}}]}"#
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let result = liveResult(makeClient())
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.detail, "LLM: Bağlantı başarılı")
    }

    func testEndToEndUnauthorizedProducesUnauthorized() {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"error":"invalid key"}"#.utf8))
        }
        let result = liveResult(makeClient())
        XCTAssertEqual(result.status, .unauthorized)
        XCTAssertEqual(result.detail, "LLM: Geçersiz API anahtarı")
    }
}
