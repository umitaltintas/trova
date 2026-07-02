import XCTest
import GRDB
@testable import TrovaCore

final class FlagFilterTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-flag-\(UUID().uuidString).sqlite"))
    }

    private func rec(_ id: String, body: String = "fatura", date: Date,
                     isRead: Bool?, isFlagged: Bool?) -> MessageRecord {
        MessageRecord(id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: "INBOX",
                      filePath: "/tmp/\(id)", fromName: "Ali", fromAddress: "ali@x.com",
                      toField: nil, ccField: nil, subject: "S\(id)", date: date,
                      snippet: String(body.prefix(40)), body: body, indexedAt: Date(),
                      isRead: isRead, isFlagged: isFlagged)
    }

    /// v9 göçü sonrası `message` tablosunda yeni nullable kolonlar bulunmalı.
    func testV9AddsFlagColumns() throws {
        let store = try makeStore()
        let columns = try store.dbQueue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(message)").map { $0["name"] as String }
        }
        XCTAssertTrue(columns.contains("isRead"), "isRead kolonu eklenmeli")
        XCTAssertTrue(columns.contains("isFlagged"), "isFlagged kolonu eklenmeli")
    }

    /// Mevcut veri korunur (eski tarz kayıt — flags nil) ve yeni kolonlar round-trip olur.
    func testFlagsRoundTripAndDataPreserved() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            rec("okunmus", date: now, isRead: true, isFlagged: false),
            rec("bilinmeyen", date: now.addingTimeInterval(-10), isRead: nil, isFlagged: nil),
        ])
        XCTAssertEqual(try store.count(), 2)   // veri korundu

        let hits = try store.browse(SearchFilter(), limit: 10)
        let byID = Dictionary(uniqueKeysWithValues: hits.map { ($0.id, $0) })
        XCTAssertEqual(byID["okunmus"]?.isRead, true)
        XCTAssertEqual(byID["okunmus"]?.isFlagged, false)
        XCTAssertNil(byID["bilinmeyen"]?.isRead)
        XCTAssertNil(byID["bilinmeyen"]?.isFlagged)
    }

    func testUnreadOnlyFilter() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            rec("okundu", date: now, isRead: true, isFlagged: false),
            rec("okunmadi", date: now.addingTimeInterval(-10), isRead: false, isFlagged: false),
            rec("bilinmeyen", date: now.addingTimeInterval(-20), isRead: nil, isFlagged: nil),
        ])
        let hits = try store.browse(SearchFilter(unreadOnly: true), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["okunmadi"], "yalnız isRead = 0 olanlar")
    }

    func testFlaggedOnlyFilter() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            rec("bayrakli", date: now, isRead: true, isFlagged: true),
            rec("duz", date: now.addingTimeInterval(-10), isRead: true, isFlagged: false),
            rec("bilinmeyen", date: now.addingTimeInterval(-20), isRead: nil, isFlagged: nil),
        ])
        let hits = try store.browse(SearchFilter(flaggedOnly: true), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["bayrakli"], "yalnız isFlagged = 1 olanlar")
    }

    /// Sanal "Okunmamışlar" klasörü rozeti bu yolu kullanır: `countMatching(query: nil,
    /// filter: unreadOnly)` yalnız isRead = 0 olanları sayar; isRead nil olanlar SAYILMAZ.
    func testUnreadCountExcludesUnknown() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            rec("okundu", date: now, isRead: true, isFlagged: false),
            rec("okunmadi1", date: now.addingTimeInterval(-10), isRead: false, isFlagged: false),
            rec("okunmadi2", date: now.addingTimeInterval(-15), isRead: false, isFlagged: false),
            rec("bilinmeyen", date: now.addingTimeInterval(-20), isRead: nil, isFlagged: nil),
        ])
        XCTAssertEqual(try store.countMatching(query: nil, filter: SearchFilter(unreadOnly: true)), 2)
    }

    /// FTS aramasında da flag filtreleri uygulanır.
    func testUnreadFilterInSearch() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            rec("1", body: "yıllık rapor", date: now, isRead: false, isFlagged: false),
            rec("2", body: "yıllık rapor", date: now.addingTimeInterval(-10), isRead: true, isFlagged: false),
        ])
        let hits = try store.search(query: "rapor", filter: SearchFilter(unreadOnly: true), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["1"])
    }
}
