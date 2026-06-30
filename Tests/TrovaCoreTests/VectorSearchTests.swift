import XCTest
@testable import TrovaCore

final class VectorSearchTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-vec-\(UUID().uuidString).sqlite"))
    }

    private func message(_ id: String) -> MessageRecord {
        MessageRecord(
            id: id, messageID: nil, accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: nil, fromAddress: nil, toField: nil,
            ccField: nil, subject: "konu \(id)", date: nil, snippet: "snip \(id)",
            body: "gövde \(id)", indexedAt: Date())
    }

    func testVectorStoreRoundTripAndSearch() throws {
        let store = try makeStore()
        try store.upsert([message("1"), message("2"), message("3")])
        try store.upsertVectors([
            ("1", [1, 0, 0]),
            ("2", [0, 1, 0]),
            ("3", [0.9, 0.1, 0]),
        ])

        XCTAssertEqual(try store.vectorCount(), 3)

        let results = try store.vectorSearch(query: [1, 0, 0], limit: 2)
        XCTAssertEqual(results.map(\.id), ["1", "3"])           // en yakın iki
        XCTAssertGreaterThan(results[0].score, results[1].score)

        // Meta veri hidrasyonu
        let meta = try store.hits(forIDs: ["1", "3"])
        XCTAssertEqual(meta["1"]?.subject, "konu 1")
        XCTAssertEqual(meta.count, 2)
    }

    func testVectorUpsertReplaces() throws {
        let store = try makeStore()
        try store.upsert([message("1")])
        try store.upsertVectors([("1", [1, 0, 0])])
        try store.upsertVectors([("1", [0, 1, 0])])         // aynı id
        XCTAssertEqual(try store.vectorCount(), 1)
        let results = try store.vectorSearch(query: [0, 1, 0], limit: 1)
        let score = try XCTUnwrap(results.first?.score)
        XCTAssertEqual(score, 1, accuracy: 1e-5)
    }

    func testRRFPrefersConsistentlyTopRanked() {
        // "a" her iki listede de 1. sırada → en yüksek füzyon skoru almalı.
        let fused = RRF.fuse([["a", "b", "c"], ["a", "c", "b"]])
        XCTAssertEqual(fused.first?.id, "a")
        XCTAssertEqual(Set(fused.map(\.id)), ["a", "b", "c"])
    }

    func testRRFUnionOfRankings() {
        let fused = RRF.fuse([["a", "b"], ["c", "d"]])
        XCTAssertEqual(Set(fused.map(\.id)), ["a", "b", "c", "d"])
    }

    // MARK: - Benzer mailler (more-like-this)

    func testSimilarReturnsNearestInOrderExcludingSelf() throws {
        let store = try makeStore()
        try store.upsert([message("1"), message("2"), message("3"), message("4")])
        try store.upsertVectors([
            ("1", [1, 0, 0]),
            ("2", [0, 1, 0]),       // dik → en uzak
            ("3", [0.9, 0.1, 0]),   // "1"e en yakın
            ("4", [0.8, 0.2, 0]),   // "1"e ikinci yakın
        ])

        let hits = try store.similar(toMessageID: "1", limit: 5)
        XCTAssertEqual(hits.map(\.id), ["3", "4", "2"])              // doğru sırada
        XCTAssertFalse(hits.contains { $0.id == "1" })              // kendini elemez
        XCTAssertGreaterThan(hits[0].score, hits[1].score)          // skor = benzerlik, azalan
        XCTAssertEqual(hits[0].subject, "konu 3")                   // meta hidrasyonu
    }

    func testSimilarRespectsLimitAndExcludesSelf() throws {
        let store = try makeStore()
        try store.upsert([message("1"), message("2"), message("3"), message("4")])
        try store.upsertVectors([
            ("1", [1, 0, 0]),
            ("2", [0.9, 0.1, 0]),
            ("3", [0.8, 0.2, 0]),
            ("4", [0.7, 0.3, 0]),
        ])

        let hits = try store.similar(toMessageID: "1", limit: 2)
        XCTAssertEqual(hits.count, 2)                               // limit'e uyar
        XCTAssertFalse(hits.contains { $0.id == "1" })             // kendini katmaz
        XCTAssertEqual(hits.map(\.id), ["2", "3"])
    }

    func testSimilarEmptyWhenTargetHasNoVector() throws {
        let store = try makeStore()
        try store.upsert([message("1"), message("2")])
        try store.upsertVectors([("2", [1, 0, 0])])                 // "1" gömülü değil
        XCTAssertTrue(try store.similar(toMessageID: "1", limit: 5).isEmpty)
    }

    func testSimilarEmptyForUnknownMessage() throws {
        let store = try makeStore()
        try store.upsert([message("1")])
        try store.upsertVectors([("1", [1, 0, 0])])
        XCTAssertTrue(try store.similar(toMessageID: "yok", limit: 5).isEmpty)
    }
}
