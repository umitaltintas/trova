import XCTest
@testable import TrovaCore

final class ThreadingFilterTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-thr-\(UUID().uuidString).sqlite"))
    }

    private func rec(_ id: String, account: String = "A", subject: String = "konu",
                     body: String = "gövde", date: Date? = nil, threadKey: String? = nil,
                     attachments: String? = nil) -> MessageRecord {
        MessageRecord(id: id, messageID: nil, accountID: account, mailbox: "INBOX",
                      filePath: "/tmp/\(id)", fromName: nil, fromAddress: nil, toField: nil,
                      ccField: nil, subject: subject, date: date, snippet: String(body.prefix(40)),
                      body: body, indexedAt: Date(), fileModified: nil, inReplyTo: nil,
                      threadKey: threadKey, attachments: attachments, parserVersion: 1)
    }

    func testThreadGroupingOrdersByDate() throws {
        let store = try makeStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        try store.upsert([
            rec("2", date: t0.addingTimeInterval(60), threadKey: "s:toplantı"),
            rec("1", date: t0, threadKey: "s:toplantı"),
            rec("3", date: t0, threadKey: "s:fatura"),
        ])
        XCTAssertEqual(try store.thread(forKey: "s:toplantı").map(\.id), ["1", "2"])
        XCTAssertEqual(try store.thread(forKey: "s:fatura").map(\.id), ["3"])
    }

    func testFilterByAccount() throws {
        let store = try makeStore()
        try store.upsert([
            rec("a1", account: "A", body: "yıllık rapor"),
            rec("b1", account: "B", body: "yıllık rapor"),
        ])
        let onlyA = try store.search(query: "rapor", filter: SearchFilter(accountID: "A"), limit: 10)
        XCTAssertEqual(onlyA.map(\.id), ["a1"])
        let all = try store.search(query: "rapor", limit: 10)
        XCTAssertEqual(Set(all.map(\.id)), ["a1", "b1"])
    }

    func testFilterByDateRange() throws {
        let store = try makeStore()
        let old = Date(timeIntervalSince1970: 1_000_000)
        let recent = Date(timeIntervalSince1970: 2_000_000)
        try store.upsert([
            rec("old", body: "fatura", date: old),
            rec("new", body: "fatura", date: recent),
        ])
        let since = try store.search(query: "fatura",
                                     filter: SearchFilter(since: Date(timeIntervalSince1970: 1_500_000)),
                                     limit: 10)
        XCTAssertEqual(since.map(\.id), ["new"])
    }

    func testAttachmentNameIsSearchable() throws {
        let store = try makeStore()
        try store.upsert([rec("1", body: "ekte dosya var", attachments: "butce2026.xlsx")])
        let hits = try store.search(query: "butce2026", limit: 10)
        XCTAssertEqual(hits.first?.id, "1")
        XCTAssertEqual(hits.first?.attachments, ["butce2026.xlsx"])
    }
}
