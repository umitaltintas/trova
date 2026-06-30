import XCTest
@testable import TrovaCore

/// `overview` aracının (posta kutusu genel istatistiği) doğru özet ürettiğini doğrular.
final class OverviewToolTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    private func msg(_ id: String, account: String, attachments: String?, date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: account, mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: "K", fromAddress: "k@x.com", toField: nil,
            ccField: nil, subject: "S\(id)", date: date, snippet: "x", body: "x",
            indexedAt: Date(), attachments: attachments)
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-overview-\(UUID().uuidString).sqlite"))
    }

    private func agent(store: IndexStore) -> ToolAgent {
        let llm = OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"))
        return ToolAgent(store: store, embedder: nil, llm: llm)
    }

    /// Saf biçimlendirici: tüm parçaları (toplam, hesap, ek, aylık dağılım, en yoğun ay) içerir.
    func testOverviewTextFormatting() {
        let monthly = [
            MonthCount(month: "2026-01", count: 120),
            MonthCount(month: "2026-02", count: 98),
            MonthCount(month: "2026-03", count: 210),
        ]
        let text = ToolAgent.overviewText(total: 7338, accounts: 3,
                                          withAttachments: 412, monthly: monthly)
        XCTAssertEqual(
            text,
            "Toplam 7338 mail, 3 hesap. 412 mailde ek var. "
                + "Son 3 ayın aylık dağılımı: 2026-01: 120, 2026-02: 98, 2026-03: 210. "
                + "En yoğun ay: 2026-03 (210).")
    }

    /// Tüm aylar boşsa "En yoğun ay" satırı eklenmez (anlamsız 0 çıktısı önlenir).
    func testOverviewTextOmitsPeakWhenEmpty() {
        let monthly = [MonthCount(month: "2026-01", count: 0), MonthCount(month: "2026-02", count: 0)]
        let text = ToolAgent.overviewText(total: 0, accounts: 0, withAttachments: 0, monthly: monthly)
        XCTAssertFalse(text.contains("En yoğun ay"), "Boş aylarda en yoğun ay satırı olmamalı")
        XCTAssertTrue(text.hasPrefix("Toplam 0 mail, 0 hesap. 0 mailde ek var."))
    }

    /// Gerçek store üzerinden uçtan uca: 2 hesap, ekler ve aylık dağılım deterministik üretilir.
    func testOverviewFromStore() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
        let mar = cal.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 9))!
        let feb = cal.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 9))!
        try store.upsert([
            msg("1", account: "A", attachments: "a.pdf", date: mar),
            msg("2", account: "A", attachments: nil, date: mar),
            msg("3", account: "B", attachments: "b.pdf", date: feb),
        ])

        let text = agent(store: store).overview(now: now, calendar: cal, months: 3)
        XCTAssertEqual(
            text,
            "Toplam 3 mail, 2 hesap. 2 mailde ek var. "
                + "Son 3 ayın aylık dağılımı: 2026-01: 0, 2026-02: 1, 2026-03: 2. "
                + "En yoğun ay: 2026-03 (2).")
    }
}
