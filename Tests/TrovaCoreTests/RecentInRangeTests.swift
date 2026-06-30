import XCTest
@testable import TrovaCore

final class RecentInRangeTests: XCTestCase {

    private func msg(_ id: String, date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: "Gönderen", fromAddress: "x@y.com", toField: nil,
            ccField: nil, subject: "S\(id)", date: date, snippet: "x", body: "x", indexedAt: Date())
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-range-\(UUID().uuidString).sqlite"))
    }

    func testFiltersBySinceAndOrdersNewestFirst() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("yeni", date: now),
            msg("orta", date: now.addingTimeInterval(-2 * 86_400)),
            msg("eski", date: now.addingTimeInterval(-10 * 86_400)),
        ])
        let hits = try store.recentInRange(since: now.addingTimeInterval(-5 * 86_400),
                                           until: nil, limit: 10)
        XCTAssertEqual(hits.map(\.id), ["yeni", "orta"])   // eski (10 gün) aralık dışı, en yeni önce
    }

    func testUntilBound() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("yeni", date: now),
            msg("dun", date: now.addingTimeInterval(-1 * 86_400)),
        ])
        let hits = try store.recentInRange(since: nil,
                                           until: now.addingTimeInterval(-12 * 3_600), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["dun"])   // yalnız 12 saatten eski olan
    }

    func testLimit() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert((0..<5).map { msg("\($0)", date: now.addingTimeInterval(Double(-$0) * 3_600)) })
        XCTAssertEqual(try store.recentInRange(since: nil, until: nil, limit: 2).count, 2)
    }
}
