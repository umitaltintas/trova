import XCTest
import GRDB
@testable import TrovaCore

/// Trova-yerel "Yıldızlı" (pin) koleksiyonu (Faz 14) için testler: pin/unpin/isPinned/pinnedIDs/
/// pinnedCount round-trip, çift pin idempotent, `pinnedOnly` süzgeci (browse + search) ve
/// migration v14'ün additive olduğu (mevcut veri korunur). Anahtar `message.id`'dir (path-hash),
/// Apple Mail bayraklarından (iter 21 salt-okunur) BAĞIMSIZ — kullanıcı Trova içinde yazar.
final class PinnedTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-pin-\(UUID().uuidString).sqlite"))
    }

    private func rec(_ id: String, body: String = "fatura", date: Date) -> MessageRecord {
        MessageRecord(id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: "INBOX",
                      filePath: "/tmp/\(id)", fromName: "Ali", fromAddress: "ali@x.com",
                      toField: nil, ccField: nil, subject: "S\(id)", date: date,
                      snippet: String(body.prefix(40)), body: body, indexedAt: Date())
    }

    /// v14 göçü sonrası `pinned` tablosu bulunmalı.
    func testV14CreatesPinnedTable() throws {
        let store = try makeStore()
        let tables = try store.dbQueue.read { db in
            try String.fetchAll(db, sql:
                "SELECT name FROM sqlite_master WHERE type='table' AND name='pinned'")
        }
        XCTAssertEqual(tables, ["pinned"], "pinned tablosu oluşturulmalı")
    }

    /// pin/unpin/isPinned round-trip + pinnedIDs/pinnedCount tutarlı.
    func testPinUnpinRoundTrip() throws {
        let store = try makeStore()
        XCTAssertFalse(try store.isPinned(id: "m1"))
        XCTAssertEqual(try store.pinnedCount(), 0)

        try store.pin(id: "m1")
        try store.pin(id: "m2")
        XCTAssertTrue(try store.isPinned(id: "m1"))
        XCTAssertTrue(try store.isPinned(id: "m2"))
        XCTAssertEqual(try store.pinnedIDs(), ["m1", "m2"])
        XCTAssertEqual(try store.pinnedCount(), 2)

        try store.unpin(id: "m1")
        XCTAssertFalse(try store.isPinned(id: "m1"))
        XCTAssertEqual(try store.pinnedIDs(), ["m2"])
        XCTAssertEqual(try store.pinnedCount(), 1)
    }

    /// Aynı id'yi iki kez yıldızlamak tek satır kalır (idempotent upsert).
    func testDoublePinIsIdempotent() throws {
        let store = try makeStore()
        try store.pin(id: "m1", at: Date().addingTimeInterval(-1000))
        try store.pin(id: "m1", at: Date())   // upsert → pinnedAt güncellenir, satır çoğalmaz
        XCTAssertEqual(try store.pinnedCount(), 1)
        XCTAssertEqual(try store.pinnedIDs(), ["m1"])
    }

    /// Boş/yalnız boşluk id atlanır (kayıt oluşmaz).
    func testBlankIDIgnored() throws {
        let store = try makeStore()
        try store.pin(id: "   ")
        XCTAssertEqual(try store.pinnedCount(), 0)
    }

    /// `pinnedOnly` süzgeci yalnız yıldızlı mailleri döndürür (browse — arama metni yok).
    func testPinnedOnlyBrowseFilter() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            rec("a", date: now),
            rec("b", date: now.addingTimeInterval(-10)),
            rec("c", date: now.addingTimeInterval(-20)),
        ])
        try store.pin(id: "b")
        let hits = try store.browse(SearchFilter(pinnedOnly: true), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["b"], "yalnız yıldızlı mail")
    }

    /// FTS aramasında da `pinnedOnly` süzgeci uygulanır.
    func testPinnedOnlyInSearch() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            rec("1", body: "yıllık rapor", date: now),
            rec("2", body: "yıllık rapor", date: now.addingTimeInterval(-10)),
        ])
        try store.pin(id: "2")
        let hits = try store.search(query: "rapor", filter: SearchFilter(pinnedOnly: true), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["2"])
    }

    /// Toplu pin/unpin round-trip: çok sayıda id tek transaction'da yıldızlanır/kaldırılır.
    func testPinManyUnpinManyRoundTrip() throws {
        let store = try makeStore()
        try store.pinMany(ids: ["a", "b", "c"])
        XCTAssertEqual(try store.pinnedIDs(), ["a", "b", "c"])
        XCTAssertEqual(try store.pinnedCount(), 3)

        try store.unpinMany(ids: ["a", "c"])
        XCTAssertEqual(try store.pinnedIDs(), ["b"])
        XCTAssertEqual(try store.pinnedCount(), 1)
    }

    /// Toplu pin idempotent: zaten yıldızlı id'leri yeniden pinlemek satır çoğaltmaz.
    func testPinManyIsIdempotent() throws {
        let store = try makeStore()
        try store.pin(id: "a")
        try store.pinMany(ids: ["a", "a", "b"])   // "a" tekrar + parti içi kopya
        XCTAssertEqual(try store.pinnedCount(), 2)
        XCTAssertEqual(try store.pinnedIDs(), ["a", "b"])
    }

    /// Boş liste güvenlidir; boş/yalnız boşluk id'ler atlanır (kayıt oluşmaz).
    func testPinManyEmptyAndBlankSafe() throws {
        let store = try makeStore()
        try store.pinMany(ids: [])             // boş liste → no-op
        try store.pinMany(ids: ["   ", ""])    // yalnız boşluk → atlanır
        XCTAssertEqual(try store.pinnedCount(), 0)
        try store.unpinMany(ids: [])           // boş unpin → güvenli
        try store.unpinMany(ids: ["yok"])      // yıldızlı olmayan → etkisiz
        XCTAssertEqual(try store.pinnedCount(), 0)
    }

    /// Migration v14 additive: yeni tablo eklense de mevcut `message` verisi korunur.
    func testMigrationAdditivePreservesMessages() throws {
        let store = try makeStore()
        try store.upsert([rec("m1", date: Date()), rec("m2", date: Date())])
        XCTAssertEqual(try store.count(), 2)
        try store.pin(id: "m1")
        XCTAssertEqual(try store.pinnedCount(), 1)
        XCTAssertEqual(try store.count(), 2)   // mesaj verisi bozulmadı
    }
}
