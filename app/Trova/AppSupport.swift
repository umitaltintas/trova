import Foundation
import AppKit
import UniformTypeIdentifiers
import TrovaCore

/// Markdown çıktısını panoya kopyalar ya da .md dosyasına kaydeder.
enum Exporter {
    static func copy(_ markdown: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(markdown, forType: .string)
    }

    @MainActor
    static func save(_ markdown: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename(suggestedName)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? markdown.data(using: .utf8)?.write(to: url)
        }
    }

    /// CSV metnini bir .csv dosyasına kaydeder (NSSavePanel, virgülle ayrılmış değer türü).
    @MainActor
    static func saveCSV(_ text: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename(suggestedName, ext: "csv")
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            // CsvExporter zaten başa UTF-8 BOM koyuyor; metni olduğu gibi yaz.
            try? text.data(using: .utf8)?.write(to: url)
        }
    }

    /// Başlıktan güvenli bir dosya adı üretir (varsayılan `.md`, istenirse başka uzantı).
    static func safeFilename(_ base: String, ext: String = "md") -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? "trova-not" : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let mapped = source.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let safe = String(mapped).prefix(50).trimmingCharacters(in: .whitespaces)
        return "\(safe.isEmpty ? "trova-not" : safe).\(ext)"
    }
}

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
    static let diversify = "diversify"            // Sonuçları thread bazında çeşitlendir (varsayılan açık)
    static let queryExpansion = "queryExpansion"  // PRF sorgu genişletme (varsayılan kapalı)
    static let streamAnswers = "streamAnswers"    // Sor yanıtını canlı (token token) akıt (varsayılan AÇIK)
    static let indexAttachmentContent = "indexAttachmentContent"  // Ek İÇERİĞİNİ indeksle/ara (opt-in, varsayılan KAPALI)
    static let recentSearches = "trova.recentSearches"  // otomatik arama geçmişi ([String], en yeni başta)
}

/// Otomatik arama geçmişini UserDefaults'a okuyup yazan küçük yardımcı.
/// Çekirdek `RecentSearches` ile normalize ederek tutarlılığı garantiler.
enum RecentSearchesStore {
    /// Saklanan son sorguları (en yeni başta, normalize edilmiş) döndürür.
    static func load() -> [String] {
        let raw = UserDefaults.standard.stringArray(forKey: SettingsKeys.recentSearches) ?? []
        return RecentSearches(items: raw).items
    }

    /// Verilen listeyi normalize edip UserDefaults'a yazar.
    static func save(_ items: [String]) {
        let normalized = RecentSearches(items: items).items
        UserDefaults.standard.set(normalized, forKey: SettingsKeys.recentSearches)
    }
}

/// Çeşitlendirme ayarından thread başına izin verilen sonuç sayısını verir.
/// Anahtar hiç yazılmamışsa varsayılan AÇIK kabul edilir (yeni kurulumlarda da çeşitli sonuç).
enum Retrieval {
    static let perThread = 2
    static func maxPerThread() -> Int? {
        let d = UserDefaults.standard
        let enabled = d.object(forKey: SettingsKeys.diversify) == nil
            ? true : d.bool(forKey: SettingsKeys.diversify)
        return enabled ? perThread : nil
    }
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
