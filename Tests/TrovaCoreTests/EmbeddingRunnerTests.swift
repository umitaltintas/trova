import XCTest
@testable import TrovaCore

final class EmbeddingRunnerTests: XCTestCase {

    /// Deterministik sahte gömme sağlayıcısı (dim 3).
    struct MockEmbedder: EmbeddingProvider {
        let dimension = 3
        func embed(_ text: String) throws -> [Float] { [Float(text.count), 1, 0] }
    }

    private func store() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-run-\(UUID().uuidString).sqlite"))
    }

    private func msg(_ id: String, _ body: String) -> MessageRecord {
        MessageRecord(id: id, messageID: nil, accountID: "A", mailbox: "INBOX", filePath: "/tmp/\(id)",
                      fromName: nil, fromAddress: nil, toField: nil, ccField: nil, subject: "k",
                      date: nil, snippet: String(body.prefix(50)), body: body, indexedAt: Date())
    }

    func testChunkerShortAndEmpty() {
        XCTAssertEqual(TextChunker.chunks("kısa metin"), ["kısa metin"])
        XCTAssertEqual(TextChunker.chunks("   "), [])
    }

    func testChunkerLongTextHasOverlapAndCap() {
        let chunks = TextChunker.chunks(String(repeating: "a", count: 5000),
                                        size: 1500, overlap: 200, maxChunks: 6)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertLessThanOrEqual(chunks.count, 6)
        XCTAssertEqual(chunks.first?.count, 1500)
    }

    func testAverageNormalized() {
        XCTAssertEqual(EmbeddingRunner.averageNormalized([[1, 0, 0]]), [1, 0, 0])  // tek → olduğu gibi
        let avg = EmbeddingRunner.averageNormalized([[2, 0, 0], [4, 0, 0]])         // çok → normalize
        XCTAssertEqual(avg, [1, 0, 0])
    }

    func testRunEmbedsAllPendingIncludingLongChunked() throws {
        let store = try store()
        try store.upsert([
            msg("long", String(repeating: "x", count: 4000)),   // parçalanır
            msg("short", "kısa gövde"),
        ])
        let count = try EmbeddingRunner.run(store: store, embedder: MockEmbedder(), messageBatch: 10)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(try store.vectorCount(), 2)

        // İkinci kez çalıştırınca eksik kalmadığından 0 işler.
        XCTAssertEqual(try EmbeddingRunner.run(store: store, embedder: MockEmbedder()), 0)
    }

    /// `limit` yalnız o kadar eksik maili gömer (otomatik gömme dalgasının parti sınırı); kalanlar
    /// bir sonraki çağrıda gömülür. Böylece art arda bounded dalgalarla kapsam %100'e ulaşır.
    func testRunRespectsLimitAndResumesRemaining() throws {
        let store = try store()
        try store.upsert((0..<5).map { msg("m\($0)", "gövde \($0)") })

        // İlk dalga: en çok 2 göm.
        XCTAssertEqual(try EmbeddingRunner.run(store: store, embedder: MockEmbedder(), limit: 2), 2)
        XCTAssertEqual(try store.vectorCount(), 2)
        XCTAssertEqual(try store.messagesMissingVectorsCount(), 3)

        // İkinci dalga: kalan 3'ün 2'si.
        XCTAssertEqual(try EmbeddingRunner.run(store: store, embedder: MockEmbedder(), limit: 2), 2)
        XCTAssertEqual(try store.messagesMissingVectorsCount(), 1)

        // Üçüncü dalga: sınır kalan sayının üstünde → yalnız kalan 1 gömülür, sonra 0.
        XCTAssertEqual(try EmbeddingRunner.run(store: store, embedder: MockEmbedder(), limit: 400), 1)
        XCTAssertEqual(try store.messagesMissingVectorsCount(), 0)
        XCTAssertEqual(try store.vectorCount(), 5)
    }

    /// `messagesMissingVectorsCount`, gömülü mailleri düşerek yalnız eksikleri sayar.
    func testMissingVectorsCount() throws {
        let store = try store()
        try store.upsert([msg("a", "bir"), msg("b", "iki"), msg("c", "üç")])
        XCTAssertEqual(try store.messagesMissingVectorsCount(), 3)
        _ = try EmbeddingRunner.run(store: store, embedder: MockEmbedder(), limit: 1)
        XCTAssertEqual(try store.messagesMissingVectorsCount(), 2)
    }
}
