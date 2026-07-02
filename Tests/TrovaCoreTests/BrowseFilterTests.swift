import XCTest
@testable import TrovaCore

final class BrowseFilterTests: XCTestCase {

    private func msg(_ id: String, from: String, addr: String, attachments: String?,
                     date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: from, fromAddress: addr, toField: nil,
            ccField: nil, subject: "S\(id)", date: date, snippet: "x", body: "x",
            indexedAt: Date(), attachments: attachments)
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-browse-\(UUID().uuidString).sqlite"))
    }

    func testBrowseByFromContains() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("1", from: "Ali Veli", addr: "ali@x.com", attachments: nil, date: now),
            msg("2", from: "Ayşe", addr: "ayse@x.com", attachments: nil, date: now.addingTimeInterval(-60)),
        ])
        let hits = try store.browse(SearchFilter(fromContains: "ali"), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["1"])
    }

    func testBrowseByFromContainsTurkishCaseInsensitive() throws {
        // Türk harfli gönderen adları (İsmail/Şeyma) küçük harfle yazılınca da eşleşmeli.
        // ASCII adlarda (Ali) davranış değişmez — tr_lower yalnız katlamayı genişletir.
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("1", from: "İsmail Yılmaz", addr: "ismail@x.com", attachments: nil, date: now),
            msg("2", from: "Şeyma Kaya", addr: "seyma@x.com", attachments: nil, date: now.addingTimeInterval(-60)),
            msg("3", from: "Ali Veli", addr: "ali@x.com", attachments: nil, date: now.addingTimeInterval(-120)),
        ])
        XCTAssertEqual(try store.browse(SearchFilter(fromContains: "ismail"), limit: 10).map(\.id), ["1"])
        XCTAssertEqual(try store.browse(SearchFilter(fromContains: "şeyma"), limit: 10).map(\.id), ["2"])
        // ASCII regresyon koruması: küçük harfli "ali" hâlâ "Ali Veli"yi bulur.
        XCTAssertEqual(try store.browse(SearchFilter(fromContains: "ali"), limit: 10).map(\.id), ["3"])
    }

    func testBrowseByHasAttachment() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("1", from: "Ali", addr: "ali@x.com", attachments: "plan.pdf", date: now),
            msg("2", from: "Ali", addr: "ali@x.com", attachments: nil, date: now.addingTimeInterval(-60)),
            msg("3", from: "Ali", addr: "ali@x.com", attachments: "", date: now.addingTimeInterval(-120)),
        ])
        let hits = try store.browse(SearchFilter(hasAttachment: true), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["1"], "yalnız boş olmayan eki olan mail")
    }

    func testBrowseCombinedAndNewestFirst() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("eski", from: "Ali", addr: "ali@x.com", attachments: "a.pdf", date: now.addingTimeInterval(-1000)),
            msg("yeni", from: "Ali", addr: "ali@x.com", attachments: "b.pdf", date: now),
            msg("baska", from: "Veli", addr: "veli@x.com", attachments: "c.pdf", date: now),
        ])
        let hits = try store.browse(SearchFilter(fromContains: "ali", hasAttachment: true), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["yeni", "eski"])
    }
}
