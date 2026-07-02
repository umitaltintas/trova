import XCTest
@testable import TrovaCore

/// `kutu:`/`mailbox:` operatörünün arama çekirdeğine (filterSQL → browse/search) etkisi.
/// Mailbox sütunu zaten şemada var; yalnızca opsiyonel filtre parametresi eklendi.
final class SearchOperatorMailboxTests: XCTestCase {

    private func msg(_ id: String, mailbox: String, body: String, date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: mailbox,
            filePath: "/tmp/\(id)", fromName: "Ali", fromAddress: "ali@x.com", toField: nil,
            ccField: nil, subject: "Konu \(id)", date: date, snippet: body, body: body,
            indexedAt: Date(), attachments: nil)
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-mailbox-\(UUID().uuidString).sqlite"))
    }

    func testBrowseByMailboxExact() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("1", mailbox: "INBOX", body: "fatura", date: now),
            msg("2", mailbox: "Arşiv", body: "fatura", date: now.addingTimeInterval(-60)),
        ])
        let hits = try store.browse(SearchFilter(mailboxContains: "INBOX"), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["1"])
    }

    func testMailboxPartialMatch() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("1", mailbox: "Arşiv/2024", body: "rapor", date: now),
            msg("2", mailbox: "INBOX", body: "rapor", date: now.addingTimeInterval(-60)),
        ])
        // Parça eşleşme: "Arş" iç içe kutu adını da yakalar.
        let hits = try store.browse(SearchFilter(mailboxContains: "Arş"), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["1"])
    }

    func testMailboxCaseInsensitive() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("1", mailbox: "INBOX", body: "fatura", date: now),
        ])
        // Küçük harfli sorgu büyük harfli kutu adıyla eşleşir (LIKE ASCII katlaması).
        let hits = try store.browse(SearchFilter(mailboxContains: "inbox"), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["1"])
    }

    func testMailboxTurkishCaseInsensitive() throws {
        // Türk harfli kutu adları (Önemli/Çöp/İstenmeyen) küçük harfle yazılınca da eşleşmeli.
        // SQLite yerleşik LIKE yalnız ASCII katlar → tr_lower olmadan bu vakalar KAÇARDI.
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("1", mailbox: "Önemli", body: "fatura", date: now),
            msg("2", mailbox: "Çöp", body: "fatura", date: now.addingTimeInterval(-60)),
            msg("3", mailbox: "İstenmeyen", body: "fatura", date: now.addingTimeInterval(-120)),
        ])
        XCTAssertEqual(try store.browse(SearchFilter(mailboxContains: "önemli"), limit: 10).map(\.id), ["1"])
        XCTAssertEqual(try store.browse(SearchFilter(mailboxContains: "çöp"), limit: 10).map(\.id), ["2"])
        XCTAssertEqual(try store.browse(SearchFilter(mailboxContains: "istenmeyen"), limit: 10).map(\.id), ["3"])
        // Büyük harfli sorgu da (kullanıcı nasıl yazarsa) aynı kutuyu bulmalı.
        XCTAssertEqual(try store.browse(SearchFilter(mailboxContains: "ÖNEMLİ"), limit: 10).map(\.id), ["1"])
    }

    func testSearchWithMailboxFilterNarrowsResults() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("1", mailbox: "INBOX", body: "fatura ödeme", date: now),
            msg("2", mailbox: "Gönderilenler", body: "fatura ödeme", date: now.addingTimeInterval(-60)),
        ])
        // FTS eşleşmesi iki maili de bulur; mailbox filtresi yalnız INBOX'a daraltır.
        let all = try store.search(query: "fatura", limit: 10)
        XCTAssertEqual(Set(all.map(\.id)), ["1", "2"])
        let inbox = try store.search(query: "fatura",
                                     filter: SearchFilter(mailboxContains: "INBOX"), limit: 10)
        XCTAssertEqual(inbox.map(\.id), ["1"])
    }

    func testSavedSearchWithMailboxOperator() throws {
        // Uçtan uca: ham `kutu:` sorgusu SearchPlanner ile filtreye çözülür ve sayım daralır.
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("1", mailbox: "INBOX", body: "fatura", date: now),
            msg("2", mailbox: "Arşiv", body: "fatura", date: now.addingTimeInterval(-60)),
        ])
        XCTAssertEqual(try store.countSavedSearch("fatura", now: now), 2)
        XCTAssertEqual(try store.countSavedSearch("fatura kutu:INBOX", now: now), 1)
    }
}
