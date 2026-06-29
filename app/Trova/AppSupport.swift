import Foundation
import TrovaCore

enum AppPaths {
    /// CLI ile AYNI veritabanı — `trova` ve uygulama tek indeksi paylaşır.
    /// Eski `EmailIndexer/` klasörü varsa tek seferlik `Trova/`'ya taşınır.
    static var databaseURL: URL {
        TrovaPaths.defaultDatabaseURL()
    }
}

enum SettingsKeys {
    static let embedProvider = "embedProvider"   // local | openrouter | openai | voyage
    static let embedModel = "embedModel"
    static let embedDim = "embedDim"
    static let llmModel = "llmModel"
    static let reranking = "reranking"           // AI ile sonuçları yeniden sırala (varsayılan kapalı)
    static let verify = "verify"                  // Yanıt doğrulama / self-critique (varsayılan kapalı)
}

/// Ayarlardan + Keychain'den (yoksa ortam değişkenlerinden) sağlayıcı kurar.
enum Providers {
    static func embedder() -> EmbeddingProvider? {
        let defaults = UserDefaults.standard
        let provider = defaults.string(forKey: SettingsKeys.embedProvider) ?? "local"
        let key = Keychain.get(KeychainKeys.embedKey)
        let llmKey = Keychain.get(KeychainKeys.llmKey)   // OpenRouter tek anahtar
        let model = defaults.string(forKey: SettingsKeys.embedModel) ?? ""
        let dim = Int(defaults.string(forKey: SettingsKeys.embedDim) ?? "")

        switch provider {
        case "openai" where !key.isEmpty:
            return APIEmbeddingProvider(config: .init(
                baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: key,
                model: model.isEmpty ? "text-embedding-3-small" : model,
                dimension: dim ?? 1536, requestedDimensions: dim))
        case "voyage" where !key.isEmpty:
            return APIEmbeddingProvider(config: .init(
                baseURL: URL(string: "https://api.voyageai.com/v1")!, apiKey: key,
                model: model.isEmpty ? "voyage-3.5" : model, dimension: dim ?? 1024))
        case "openrouter":
            // Embedding anahtarı boşsa AI sekmesindeki OpenRouter anahtarını kullan.
            let orKey = key.isEmpty ? llmKey : key
            guard !orKey.isEmpty else { return nil }
            return APIEmbeddingProvider(config: .init(
                baseURL: URL(string: "https://openrouter.ai/api/v1")!, apiKey: orKey,
                model: model.isEmpty ? "openai/text-embedding-3-small" : model,
                dimension: dim ?? 1536, requestedDimensions: dim))
        default:
            return EmbeddingFactory.fromEnvironment() ?? (try? LocalEmbeddingProvider())
        }
    }

    static func llm() -> OpenRouterClient? {
        let defaults = UserDefaults.standard
        let key = Keychain.get(KeychainKeys.llmKey)
        let model = defaults.string(forKey: SettingsKeys.llmModel) ?? ""
        if !key.isEmpty {
            return OpenRouterClient(config: .init(
                baseURL: URL(string: "https://openrouter.ai/api/v1")!, apiKey: key,
                model: model.isEmpty ? "anthropic/claude-sonnet-4.6" : model))
        }
        return OpenRouterClient.fromEnvironment()
    }

    /// Reranking ayarı açıksa ve bir LLM istemcisi varsa LLM tabanlı yeniden sıralayıcı kurar.
    static func reranker() -> Reranker? {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.reranking),
              let llm = llm() else { return nil }
        return LLMReranker(llm: llm)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
