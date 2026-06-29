import XCTest
@testable import TrovaCore

/// Sahte yanıt döndüren URLProtocol — gerçek ağ/anahtar olmadan sağlayıcı mantığını test eder.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class APIEmbeddingProviderTests: XCTestCase {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func provider(dimension: Int = 3) -> APIEmbeddingProvider {
        APIEmbeddingProvider(
            config: .init(baseURL: URL(string: "https://api.test/v1")!,
                          apiKey: "test-key", model: "test-model", dimension: dimension),
            session: makeSession())
    }

    func testParsesAndOrdersBatchByIndex() throws {
        // Sıra karışık (index 1 önce) döner; sağlayıcı index'e göre geri dizmeli.
        MockURLProtocol.handler = { request in
            // İstek gövdesi doğru mu?
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let json = """
            {"data":[
              {"index":1,"embedding":[0.4,0.5,0.6]},
              {"index":0,"embedding":[0.1,0.2,0.3]}
            ]}
            """
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }

        let vectors = try provider().embedBatch(["ilk", "ikinci"])
        XCTAssertEqual(vectors.count, 2)
        XCTAssertEqual(vectors[0], [0.1, 0.2, 0.3])   // index 0
        XCTAssertEqual(vectors[1], [0.4, 0.5, 0.6])   // index 1
    }

    func testHTTPErrorSurfaces() {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"error":"invalid key"}"#.utf8))
        }
        XCTAssertThrowsError(try provider().embed("x")) { error in
            guard case EmbeddingError.http(let status, _) = error else {
                return XCTFail("HTTP hatası bekleniyordu, gelen: \(error)")
            }
            XCTAssertEqual(status, 401)
        }
    }

    func testFactoryFromEnvironment() {
        let openai = EmbeddingFactory.fromEnvironment([
            "EIDX_EMBED_PROVIDER": "openai", "OPENAI_API_KEY": "k",
        ])
        XCTAssertEqual(openai?.dimension, 1536)

        let voyage = EmbeddingFactory.fromEnvironment([
            "EIDX_EMBED_PROVIDER": "voyage", "VOYAGE_API_KEY": "k", "EIDX_EMBED_DIM": "1024",
        ])
        XCTAssertEqual(voyage?.dimension, 1024)

        // OpenRouter: LLM ile aynı OPENROUTER_API_KEY'i kullanır.
        let openrouter = EmbeddingFactory.fromEnvironment([
            "EIDX_EMBED_PROVIDER": "openrouter", "OPENROUTER_API_KEY": "k",
        ])
        XCTAssertEqual(openrouter?.dimension, 1536)

        XCTAssertNil(EmbeddingFactory.fromEnvironment(["EIDX_EMBED_PROVIDER": "openai"]))  // anahtar yok
        XCTAssertNil(EmbeddingFactory.fromEnvironment([:]))                                 // yapılandırma yok
    }
}
