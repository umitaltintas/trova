import XCTest
@testable import TrovaCore

final class TopSendersTests: XCTestCase {

    private func msg(_ id: String, name: String?, addr: String?, mailbox: String) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: mailbox,
            filePath: "/tmp/\(id)", fromName: name, fromAddress: addr, toField: nil,
            ccField: nil, subject: "S\(id)", date: Date(), snippet: "x", body: "x", indexedAt: Date())
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-top-\(UUID().uuidString).sqlite"))
    }

    func testTopSendersCountsAndExcludesSent() throws {
        let store = try makeStore()
        try store.upsert([
            msg("1", name: "Ali", addr: "ali@x.com", mailbox: "INBOX"),
            msg("2", name: "Ali", addr: "ali@x.com", mailbox: "INBOX"),
            msg("3", name: nil, addr: "ali@x.com", mailbox: "INBOX"),
            msg("4", name: "Ali V.", addr: "ALI@x.com", mailbox: "Gelen Kutusu"),  // büyük/küçük harf → birleşir
            msg("5", name: "Veli", addr: "veli@x.com", mailbox: "INBOX"),
            msg("6", name: "Veli", addr: "veli@x.com", mailbox: "INBOX"),
            msg("7", name: "Ben", addr: "me@x.com", mailbox: "Sent Messages"),     // gönderilen → hariç
            msg("8", name: "Boş", addr: "", mailbox: "INBOX"),                     // boş adres → hariç
        ])

        let top = try store.topSenders(limit: 10)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].address.lowercased(), "ali@x.com")
        XCTAssertEqual(top[0].count, 4, "büyük/küçük harf farkı tek kişide birleşmeli")
        XCTAssertEqual(top[1].address.lowercased(), "veli@x.com")
        XCTAssertEqual(top[1].count, 2)
        XCTAssertNotNil(top[0].name, "temsilci görünen ad seçilmeli")
        XCTAssertFalse(top.contains { $0.address.lowercased() == "me@x.com" })
    }

    func testTopSendersRespectsLimit() throws {
        let store = try makeStore()
        try store.upsert((1...5).map {
            msg("\($0)", name: "K\($0)", addr: "k\($0)@x.com", mailbox: "INBOX")
        })
        XCTAssertEqual(try store.topSenders(limit: 3).count, 3)
    }

    func testEmptyStoreReturnsEmpty() throws {
        let store = try makeStore()
        XCTAssertTrue(try store.topSenders(limit: 10).isEmpty)
    }
}
