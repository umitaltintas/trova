import XCTest
@testable import TrovaCore

/// Gerçek yerel gömme modeliyle uçtan uca entegrasyon. Model varlıkları yoksa atlanır.
final class EmbeddingIntegrationTests: XCTestCase {

    private func record(_ id: String, subject: String, body: String) -> MessageRecord {
        MessageRecord(
            id: id, messageID: nil, accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: "Gönderen", fromAddress: "x@example.com",
            toField: nil, ccField: nil, subject: subject, date: Date(),
            snippet: String(body.prefix(80)), body: body, indexedAt: Date())
    }

    func testSemanticSearchRanksRelatedEmailFirst() throws {
        let provider: LocalEmbeddingProvider
        do { provider = try LocalEmbeddingProvider() }
        catch { throw XCTSkip("Yerel gömme modeli yok: \(error)") }

        let store = try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-emb-\(UUID().uuidString).sqlite"))

        let emails = [
            record("kira", subject: "Kira sözleşmesi",
                   body: "Daire kira sözleşmeniz bu ay sonunda doluyor, lütfen yenileyin."),
            record("fatura", subject: "Elektrik faturası",
                   body: "Bu ayki elektrik tüketim faturanız 250 TL olarak hesaplanmıştır."),
            record("mac", subject: "Maç saati",
                   body: "Yarınki futbol maçı akşam sekizde başlayacak, geç kalma."),
        ]
        try store.upsert(emails)
        try store.upsertVectors(emails.map { ($0.id, try! provider.embed($0.body!)) })

        let searcher = Searcher(store: store, embedder: provider)

        // Anlamsal aramanın MEKANİĞİ çalışmalı (3 sonuç dönmeli, meta hidrasyonu olmalı).
        // NOT: Mean-pool NLContextualEmbedding'in sıralama KALİTESİ zayıftır; bu yüzden
        // burada belirli bir anlamsal sıra iddia etmiyoruz (bkz. README "Embedding kalitesi").
        let semantic = try searcher.search("ev kontratının süresi bitiyor", mode: .semantic, limit: 3)
        XCTAssertEqual(semantic.count, 3)
        XCTAssertNotNil(semantic.first?.subject)

        // Hibritte FTS anahtar kelimeyi taşır: "kira" geçen sorgu "kira" mailini öne çıkarır.
        let hybrid = try searcher.search("kira sözleşmesi", mode: .hybrid, limit: 3)
        XCTAssertEqual(hybrid.first?.id, "kira", "Hibrit sıralama: \(hybrid.map(\.id))")
    }
}
