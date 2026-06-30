import XCTest
@testable import TrovaCore

final class InsightsTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    private func msg(_ id: String, attachments: String?, date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: "K", fromAddress: "k@x.com", toField: nil,
            ccField: nil, subject: "S\(id)", date: date, snippet: "x", body: "x",
            indexedAt: Date(), attachments: attachments)
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-insights-\(UUID().uuidString).sqlite"))
    }

    func testAttachmentCount() throws {
        let store = try makeStore()
        let now = Date()
        try store.upsert([
            msg("1", attachments: "a.pdf", date: now),
            msg("2", attachments: nil, date: now),
            msg("3", attachments: "", date: now),
            msg("4", attachments: "b.pdf", date: now),
        ])
        XCTAssertEqual(try store.attachmentCount(), 2)
    }

    func testMonthlyCountsBucketsAndZeroFills() throws {
        let store = try makeStore()
        // Sabit referans: 2023-11-15 (Istanbul).
        let now = cal.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 12))!
        let nov = cal.date(from: DateComponents(year: 2023, month: 11, day: 2, hour: 9))!
        let sep = cal.date(from: DateComponents(year: 2023, month: 9, day: 20, hour: 9))!
        try store.upsert([
            msg("n1", attachments: nil, date: nov),
            msg("n2", attachments: nil, date: nov),
            msg("s1", attachments: nil, date: sep),
        ])
        // Son 3 ay: Eylül, Ekim, Kasım.
        let counts = try store.monthlyCounts(months: 3, now: now, calendar: cal)
        XCTAssertEqual(counts.map(\.month), ["2023-09", "2023-10", "2023-11"])
        XCTAssertEqual(counts.map(\.count), [1, 0, 2], "Ekim boş → 0; sıra en eskiden yeniye")
    }

    func testMonthlyCountsExcludesOlderThanWindow() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2023, month: 11, day: 15))!
        let old = cal.date(from: DateComponents(year: 2023, month: 1, day: 5))!  // pencere dışı
        try store.upsert([msg("old", attachments: nil, date: old)])
        let counts = try store.monthlyCounts(months: 3, now: now, calendar: cal)
        XCTAssertEqual(counts.reduce(0) { $0 + $1.count }, 0)
    }
}
