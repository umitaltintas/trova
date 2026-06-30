import Foundation
import ArgumentParser
import TrovaCore

@main
struct Trova: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trova",
        abstract: "Apple Mail yerel deposunu indeksler ve arar.",
        subcommands: [Doctor.self, Index.self, Embed.self, Search.self, Ask.self, Agent.self, Accounts.self],
        defaultSubcommand: Doctor.self)
}

extension SearchMode: ExpressibleByArgument {}

/// Varsayılan veritabanı: ~/Library/Application Support/Trova/index.sqlite
/// (eski `EmailIndexer/` klasörü varsa tek seferlik taşınır — bkz. TrovaPaths.)
func defaultDBPath() -> URL {
    TrovaPaths.defaultDatabaseURL()
}

func resolveStore(_ dbOption: String?) throws -> IndexStore {
    let url = dbOption.map { URL(fileURLWithPath: $0) } ?? defaultDBPath()
    return try IndexStore(path: url)
}

/// Embedding sağlayıcısı seçer: env'de API yapılandırılmışsa onu, yoksa yerel modeli.
/// Etiket stderr'e yazılır (hangi sağlayıcının kullanıldığı görünür).
func makeEmbedder(announce: Bool = true) -> EmbeddingProvider? {
    if let api = EmbeddingFactory.fromEnvironment() {
        if announce { FileHandle.standardError.write(Data("Embedding: API (boyut=\(api.dimension))\n".utf8)) }
        return api
    }
    if let local = try? LocalEmbeddingProvider() {
        if announce { FileHandle.standardError.write(Data("Embedding: yerel NLContextualEmbedding (boyut=\(local.dimension))\n".utf8)) }
        return local
    }
    return nil
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension Trova {
    struct Doctor: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Erişim ve depo durumunu kontrol eder.")

        func run() throws {
            if let root = MailStore.locate() {
                print("✓ Mail deposu bulundu: \(root.path)")
                let sample = MailStore.discoverMessages(root: root, limit: 1)
                if sample.isEmpty {
                    print("⚠︎ Depo var ama .emlx okunamadı — Full Disk Access gerekebilir.")
                } else {
                    print("✓ Okuma erişimi çalışıyor.")
                }
            } else if !MailStore.canAccess() {
                print("✗ ~/Library/Mail okunamıyor — Full Disk Access gerekli.")
                print("  Sistem Ayarları → Gizlilik ve Güvenlik → Full Disk Access")
                print("  → çalıştırdığınız terminal uygulamasını ekleyip açın.")
            } else {
                print("✗ Mail deposu (V<n>) yok. Apple Mail kurulu ve en az bir kez çalışmış mı?")
            }
            print("DB yolu: \(defaultDBPath().path)")
        }
    }

    struct Index: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mailleri indeksler.")
        @Option(name: .long, help: "Azami mail sayısı (test için).") var limit: Int?
        @Option(name: .long, help: "Veritabanı yolu.") var db: String?

        func run() throws {
            guard let root = MailStore.locate(), MailStore.canAccess() else {
                throw ValidationError("Mail deposuna erişilemiyor. Önce `trova doctor` çalıştırın.")
            }
            let store = try resolveStore(db)
            print("İndeksleniyor… (\(root.lastPathComponent))")
            let result = try Indexer.run(store: store, root: root, limit: limit) { processed, total in
                FileHandle.standardError.write(Data("\r\(processed)/\(total) işlendi…".utf8))
            }
            print("\nBitti: \(result.inserted) yeni · \(result.duplicates) kopya · \(result.skipped) atlandı · \(result.failed) hata · \(result.processed) toplam.")
            print("Veritabanındaki kayıt: \(try store.count())")
        }
    }

    struct Embed: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Eksik mailler için anlamsal gömme üretir (yerel veya API).")
        @Option(name: .long, help: "İstek/grup başına mail sayısı.") var batch: Int = 48
        @Flag(name: .long, help: "Mevcut vektörleri silip baştan üretir (sağlayıcı değişiminde).")
        var reset = false
        @Option(name: .long, help: "Veritabanı yolu.") var db: String?

        func run() throws {
            let store = try resolveStore(db)
            guard let embedder = makeEmbedder() else {
                throw ValidationError("Embedding sağlayıcısı yok: yerel model yüklenemedi ve API ayarlanmadı.")
            }
            if reset { try store.clearVectors() }

            print("Gömülüyor (boyut=\(embedder.dimension), uzun mailler parçalanır)…")
            let count = try EmbeddingRunner.run(store: store, embedder: embedder, messageBatch: max(1, batch)) {
                processed, total in
                FileHandle.standardError.write(Data("\r\(processed)/\(total)…".utf8))
            }
            print(count == 0 ? "Tüm mailler zaten gömülü." : "\nBitti. İşlenen: \(count) · toplam vektör: \(try store.vectorCount())")
        }
    }

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Arama: fts (anahtar kelime), semantic (anlamsal) veya hybrid.")
        @Argument(help: "Arama sorgusu.") var query: [String] = []
        @Option(name: .long, help: "Sonuç sayısı.") var limit: Int = 10
        @Option(name: .long, help: "Mod: fts | semantic | hybrid") var mode: SearchMode = .hybrid
        @Option(name: .long, help: "Veritabanı yolu.") var db: String?

        func run() throws {
            let store = try resolveStore(db)
            let q = query.joined(separator: " ")
            guard !q.isEmpty else { throw ValidationError("Bir arama sorgusu girin.") }

            // Anlamsal/hibrit için gömme sağlayıcısını yükle; yoksa FTS'e düş.
            var embedder: EmbeddingProvider?
            if mode != .fts {
                embedder = makeEmbedder()
                if embedder == nil {
                    FileHandle.standardError.write(Data("⚠︎ Gömme sağlayıcısı yok; FTS'e düşülüyor.\n".utf8))
                }
            }
            let searcher = Searcher(store: store, embedder: embedder)
            let hits = try searcher.search(q, mode: mode, limit: limit)
            guard !hits.isEmpty else { print("Sonuç yok: \(q)"); return }

            for (i, hit) in hits.enumerated() {
                let date = hit.date.map { ISO8601DateFormatter().string(from: $0) } ?? "—"
                print("\(i + 1). [\(hit.mailbox)] \(hit.subject ?? "(konu yok)")")
                print("   \(hit.fromName ?? hit.fromAddress ?? "—")  ·  \(date)")
                if !hit.snippet.isEmpty { print("   \(hit.snippet)") }
            }
        }
    }

    struct Ask: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Doğal dil sorusu: ilgili mailleri bul, sırala ve özetle (OpenRouter).")
        @Argument(help: "Soru.") var question: [String] = []
        @Option(name: .long, help: "LLM'e gönderilecek aday sayısı.") var candidates: Int = 30
        @Option(name: .long, help: "Gösterilecek sonuç sayısı.") var top: Int = 8
        @Option(name: .long, help: "Veritabanı yolu.") var db: String?

        func run() throws {
            let q = question.joined(separator: " ")
            guard !q.isEmpty else { throw ValidationError("Bir soru girin.") }
            guard let llm = OpenRouterClient.fromEnvironment() else {
                throw ValidationError("""
                    OPENROUTER_API_KEY ayarlı değil.
                      export OPENROUTER_API_KEY=...
                      export EIDX_LLM_MODEL=anthropic/claude-sonnet-4.6   # opsiyonel
                    """)
            }
            let store = try resolveStore(db)
            let agent = MailAgent(store: store, embedder: makeEmbedder(announce: false), llm: llm)
            FileHandle.standardError.write(Data("Model: \(llm.model) · aday getiriliyor…\n".utf8))
            let answer = try agent.ask(q, candidateCount: candidates, topK: top)

            print("\n\(answer.summary)\n")
            guard !answer.ranked.isEmpty else { return }
            for (i, item) in answer.ranked.enumerated() {
                let date = item.hit.date.map { ISO8601DateFormatter().string(from: $0) } ?? "—"
                let pct = String(format: "%.0f%%", item.relevance * 100)
                print("\(i + 1). [\(item.hit.mailbox)] \(item.hit.subject ?? "(konu yok)")  (\(pct))")
                print("   \(item.hit.fromName ?? item.hit.fromAddress ?? "—")  ·  \(date)")
                if !item.reason.isEmpty { print("   → \(item.reason)") }
            }
        }
    }

    struct Agent: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Çok adımlı ajan: arar, mail okur, yeniden arar, sonra yanıtlar (OpenRouter).")
        @Argument(help: "Soru.") var question: [String] = []
        @Option(name: .long, help: "Azami adım sayısı.") var steps: Int = 8
        @Option(name: .long, help: "Veritabanı yolu.") var db: String?

        func run() throws {
            let q = question.joined(separator: " ")
            guard !q.isEmpty else { throw ValidationError("Bir soru girin.") }
            guard let llm = OpenRouterClient.fromEnvironment() else {
                throw ValidationError("OPENROUTER_API_KEY ayarlı değil.")
            }
            let store = try resolveStore(db)
            let agent = ToolAgent(store: store, embedder: makeEmbedder(announce: false),
                                  llm: llm, maxSteps: steps)
            let run = try agent.run(q) { step in
                FileHandle.standardError.write(Data("· \(step.kind.rawValue): \(step.detail)\n".utf8))
            }
            print("\n\(run.answer)")
            if !run.cited.isEmpty {
                print("\nKaynaklar:")
                for hit in run.cited { print("  - \(hit.subject ?? "(konu yok)")") }
            }
        }
    }

    struct Accounts: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Hesap bazında kayıt sayısı.")
        @Option(name: .long, help: "Veritabanı yolu.") var db: String?

        func run() throws {
            let store = try resolveStore(db)
            let counts = try store.accountCounts()
            guard !counts.isEmpty else { print("Henüz kayıt yok. `trova index` çalıştırın."); return }
            for entry in counts { print("\(entry.count)\t\(entry.account)") }
        }
    }
}
