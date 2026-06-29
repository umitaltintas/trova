import Foundation

public enum EmbeddingError: Error, CustomStringConvertible {
    case http(status: Int, body: String)
    case badResponse(String)
    case transport(String)

    public var description: String {
        switch self {
        case let .http(status, body): return "HTTP \(status): \(body.prefix(300))"
        case let .badResponse(s): return "Beklenmeyen yanıt: \(s.prefix(300))"
        case let .transport(s): return "Ağ hatası: \(s)"
        }
    }
}

public struct APIEmbeddingConfig: Sendable {
    public var baseURL: URL          // örn. https://api.openai.com/v1
    public var apiKey: String
    public var model: String
    public var dimension: Int        // depolanacak/doğrulanacak vektör boyutu
    public var requestedDimensions: Int?   // OpenAI text-embedding-3 'dimensions' parametresi
    public var inputType: String?    // Voyage 'input_type' (opsiyonel)

    public init(baseURL: URL, apiKey: String, model: String, dimension: Int,
                requestedDimensions: Int? = nil, inputType: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.dimension = dimension
        self.requestedDimensions = requestedDimensions
        self.inputType = inputType
    }
}

/// OpenAI-uyumlu bir `/embeddings` uç noktası üzerinden gömme üretir.
/// OpenAI, Voyage ve aynı yanıt şeklini (`data[].embedding`) sunan sağlayıcılarla çalışır.
/// Ağ çağrısı CLI için senkron (DispatchSemaphore) yapılır; protokol senkron kalır.
public final class APIEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    public let dimension: Int
    private let config: APIEmbeddingConfig
    private let session: URLSession

    public init(config: APIEmbeddingConfig, session: URLSession = .shared) {
        self.config = config
        self.dimension = config.dimension
        self.session = session
    }

    public func embed(_ text: String) throws -> [Float] {
        guard let first = try embedBatch([text]).first else {
            throw EmbeddingError.badResponse("boş sonuç")
        }
        return first
    }

    public func embedBatch(_ texts: [String]) throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        // Boş metinler API'lerce reddedilebilir → tek boşlukla koru. Token sınırı için kırp.
        let inputs = texts.map { $0.isEmpty ? " " : String($0.prefix(8000)) }

        var payload: [String: Any] = ["model": config.model, "input": inputs]
        if let dims = config.requestedDimensions { payload["dimensions"] = dims }
        if let type = config.inputType { payload["input_type"] = type }

        let url = config.baseURL.appendingPathComponent("embeddings")
        let data: Data
        do {
            data = try SyncHTTP.postJSON(
                session: session, url: url, bearer: config.apiKey,
                body: try JSONSerialization.data(withJSONObject: payload))
        } catch let HTTPClientError.http(status, body) {
            throw EmbeddingError.http(status: status, body: body)
        } catch let HTTPClientError.transport(message) {
            throw EmbeddingError.transport(message)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw EmbeddingError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        if let error = root["error"] {
            throw EmbeddingError.badResponse("\(error)")
        }
        guard let items = root["data"] as? [[String: Any]] else {
            throw EmbeddingError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }

        // 'index' alanına göre giriş sırasına geri diz.
        let ordered = items.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
        return try ordered.map { item in
            guard let raw = item["embedding"] as? [Any] else {
                throw EmbeddingError.badResponse("embedding alanı yok")
            }
            return raw.map { Float(($0 as? NSNumber)?.doubleValue ?? 0) }
        }
    }
}

/// Ortam değişkenlerinden embedding sağlayıcısı kurar.
///
///   EIDX_EMBED_PROVIDER = openai | voyage | openrouter | custom
///   OPENAI_API_KEY / VOYAGE_API_KEY / OPENROUTER_API_KEY / EIDX_EMBED_API_KEY
///   EIDX_EMBED_MODEL, EIDX_EMBED_DIM, EIDX_EMBED_BASE_URL (custom için)
public enum EmbeddingFactory {
    public static func fromEnvironment(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> APIEmbeddingProvider? {
        let dim = env["EIDX_EMBED_DIM"].flatMap(Int.init)

        switch (env["EIDX_EMBED_PROVIDER"] ?? "").lowercased() {
        case "openai":
            guard let key = env["OPENAI_API_KEY"] ?? env["EIDX_EMBED_API_KEY"] else { return nil }
            return APIEmbeddingProvider(config: .init(
                baseURL: url(env["EIDX_EMBED_BASE_URL"], "https://api.openai.com/v1"),
                apiKey: key,
                model: env["EIDX_EMBED_MODEL"] ?? "text-embedding-3-small",
                dimension: dim ?? 1536,
                requestedDimensions: dim))   // OpenAI boyut küçültmeyi destekler

        case "openrouter":
            // OpenRouter OpenAI-uyumlu /embeddings sunar → embedding + LLM tek anahtar.
            guard let key = env["OPENROUTER_API_KEY"] ?? env["EIDX_EMBED_API_KEY"] else { return nil }
            return APIEmbeddingProvider(config: .init(
                baseURL: url(env["EIDX_EMBED_BASE_URL"], "https://openrouter.ai/api/v1"),
                apiKey: key,
                model: env["EIDX_EMBED_MODEL"] ?? "openai/text-embedding-3-small",
                dimension: dim ?? 1536,
                requestedDimensions: dim))

        case "voyage":
            guard let key = env["VOYAGE_API_KEY"] ?? env["EIDX_EMBED_API_KEY"] else { return nil }
            return APIEmbeddingProvider(config: .init(
                baseURL: url(env["EIDX_EMBED_BASE_URL"], "https://api.voyageai.com/v1"),
                apiKey: key,
                model: env["EIDX_EMBED_MODEL"] ?? "voyage-3.5",
                dimension: dim ?? 1024))

        case "custom":
            guard let key = env["EIDX_EMBED_API_KEY"], let base = env["EIDX_EMBED_BASE_URL"],
                  let baseURL = URL(string: base) else { return nil }
            return APIEmbeddingProvider(config: .init(
                baseURL: baseURL, apiKey: key,
                model: env["EIDX_EMBED_MODEL"] ?? "embedding",
                dimension: dim ?? 1536))

        default:
            return nil
        }
    }

    private static func url(_ value: String?, _ fallback: String) -> URL {
        URL(string: value ?? fallback) ?? URL(string: fallback)!
    }
}
