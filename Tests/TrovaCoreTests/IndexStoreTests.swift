import XCTest
@testable import TrovaCore

final class IndexStoreTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-test-\(UUID().uuidString).sqlite")
        return try IndexStore(path: path)
    }

    private func record(id: String, subject: String, body: String,
                        from: String = "Gönderen") -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@test>", accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id).emlx", fromName: from, fromAddress: "x@example.com",
            toField: "me@example.com", ccField: nil, subject: subject, date: Date(),
            snippet: String(body.prefix(100)), body: body, indexedAt: Date())
    }

    func testUpsertSearchAndCount() throws {
        let store = try makeStore()
        try store.upsert([
            record(id: "1", subject: "Kira sözleşmesi yenileme",
                   body: "Daire kira sözleşmeniz bu ay sonunda doluyor, lütfen yenileyin."),
            record(id: "2", subject: "Elektrik faturası",
                   body: "Bu ayki elektrik faturanız 250 TL olarak hesaplanmıştır."),
            record(id: "3", subject: "Toplantı notları",
                   body: "Yarınki proje toplantısı saat 14:00'te başlayacak."),
        ])

        XCTAssertEqual(try store.count(), 3)

        let kira = try store.search(query: "kira sözleşmesi", limit: 10)
        XCTAssertEqual(kira.first?.id, "1")

        let fatura = try store.search(query: "fatura", limit: 10)
        XCTAssertEqual(fatura.map(\.id), ["2"])
        XCTAssertTrue(fatura.first?.snippet.contains("«") ?? false, "snippet vurgusu bekleniyordu")

        let yok = try store.search(query: "uzaymekiği", limit: 10)
        XCTAssertTrue(yok.isEmpty)
    }

    func testUpsertReplacesExistingRow() throws {
        let store = try makeStore()
        try store.upsert([record(id: "1", subject: "İlk", body: "ilk gövde")])
        try store.upsert([record(id: "1", subject: "Güncel", body: "güncellenmiş gövde")])

        XCTAssertEqual(try store.count(), 1)  // aynı id → tek satır
        XCTAssertEqual(try store.search(query: "güncellenmiş", limit: 10).first?.id, "1")
        XCTAssertTrue(try store.search(query: "ilk gövde", limit: 10).isEmpty)  // FTS de güncellendi
    }

    /// upsert, yalnız gerçekten yeni (var olmayan id) satırların sayısını döndürür → "N yeni mail".
    func testUpsertReturnsNewlyInsertedCount() throws {
        let store = try makeStore()
        // Boş DB'ye N yeni mail → hepsi yeni.
        let inserted = try store.upsert([
            record(id: "1", subject: "a", body: "x"),
            record(id: "2", subject: "b", body: "y"),
            record(id: "3", subject: "c", body: "z"),
        ])
        XCTAssertEqual(inserted, 3)

        // Aynı kayıtları (değişmeden) tekrar yaz → hiçbiri yeni değil.
        let again = try store.upsert([
            record(id: "1", subject: "a", body: "x"),
            record(id: "2", subject: "b", body: "y"),
        ])
        XCTAssertEqual(again, 0)

        // Var olan bir kayıt değişirse: yeni sayılmaz (0) ama satır güncellenir.
        let changed = try store.upsert([record(id: "1", subject: "a2", body: "güncel gövde")])
        XCTAssertEqual(changed, 0)
        XCTAssertEqual(try store.count(), 3)  // hâlâ 3 satır
        XCTAssertEqual(try store.search(query: "güncel", limit: 10).first?.id, "1")

        // Karışık parti: 2 var + 2 yeni → yalnız 2 yeni sayılır.
        let mixed = try store.upsert([
            record(id: "2", subject: "b", body: "y"),
            record(id: "4", subject: "d", body: "w"),
            record(id: "3", subject: "c", body: "z"),
            record(id: "5", subject: "e", body: "v"),
        ])
        XCTAssertEqual(mixed, 2)
    }

    func testAccountCounts() throws {
        let store = try makeStore()
        try store.upsert([
            record(id: "1", subject: "a", body: "b"),
            record(id: "2", subject: "c", body: "d"),
        ])
        let counts = try store.accountCounts()
        XCTAssertEqual(counts.first?.account, "ACC")
        XCTAssertEqual(counts.first?.count, 2)
    }
}
