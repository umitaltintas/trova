import XCTest
@testable import TrovaCore

final class SenderStatsTests: XCTestCase {

    private func msg(_ id: String, addr: String, attachments: String?, date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: "K", fromAddress: addr, toField: nil,
            ccField: nil, subject: "S\(id)", date: date, snippet: "x", body: "x",
            indexedAt: Date(), attachments: attachments)
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-sstat-\(UUID().uuidString).sqlite"))
    }

    func testCountsAttachmentsAndDateSpan() throws {
        let store = try makeStore()
        let early = Date(timeIntervalSince1970: 1_600_000_000)
        let late = Date(timeIntervalSince1970: 1_700_000_000)
        try store.upsert([
            msg("1", addr: "ali@x.com", attachments: "a.pdf", date: late),
            msg("2", addr: "ali@x.com", attachments: nil, date: early),
            msg("3", addr: "ALI@x.com", attachments: "b.pdf", date: Date(timeIntervalSince1970: 1_650_000_000)),
            msg("9", addr: "baska@x.com", attachments: "c.pdf", date: late),  // başka kişi, sayılmaz
        ])
        let s = try store.senderStats(address: "ali@x.com")
        XCTAssertEqual(s.total, 3, "büyük/küçük harf birleşir, başka kişi hariç")
        XCTAssertEqual(s.withAttachments, 2)
        XCTAssertEqual(s.firstDate, early)
        XCTAssertEqual(s.lastDate, late)
    }

    func testUnknownSenderIsZero() throws {
        let store = try makeStore()
        try store.upsert([msg("1", addr: "ali@x.com", attachments: nil, date: Date())])
        let s = try store.senderStats(address: "yok@x.com")
        XCTAssertEqual(s.total, 0)
        XCTAssertNil(s.firstDate)
        XCTAssertNil(s.lastDate)
    }
}
