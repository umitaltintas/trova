import XCTest
@testable import TrovaCore

/// `IndexStore.monthlySentReceived` — aylık gelen/gönderilen dağılımı testleri.
/// `now`/`calendar` sabit enjekte → deterministik (InsightsTests deseniyle aynı).
final class MonthlySentReceivedTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    private func msg(_ id: String, mailbox: String, date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: mailbox,
            filePath: "/tmp/\(id)", fromName: "K", fromAddress: "k@x.com", toField: nil,
            ccField: nil, subject: "S\(id)", date: date, snippet: "x", body: "x",
            indexedAt: Date(), attachments: nil)
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-balance-\(UUID().uuidString).sqlite"))
    }

    /// Gelen ve gönderilen mailler doğru aya ve doğru sınıfa düşer; eksik ay (0,0) dolar; sıra eskiden yeniye.
    func testBucketsClassifyAndZeroFill() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 12))!
        let nov = cal.date(from: DateComponents(year: 2023, month: 11, day: 2, hour: 9))!
        let sep = cal.date(from: DateComponents(year: 2023, month: 9, day: 20, hour: 9))!
        try store.upsert([
            msg("n1", mailbox: "INBOX", date: nov),                 // gelen
            msg("n2", mailbox: "Gelen Kutusu", date: nov),          // gelen
            msg("n3", mailbox: "Gönderilenler", date: nov),         // gönderilen
            msg("s1", mailbox: "Sent Messages", date: sep),         // gönderilen
        ])
        // Son 3 ay: Eylül, Ekim (boş), Kasım.
        let r = try store.monthlySentReceived(months: 3, now: now, calendar: cal)
        XCTAssertEqual(r.map { "\($0.year)-\($0.month)" }, ["2023-9", "2023-10", "2023-11"])
        XCTAssertEqual(r.map(\.received), [0, 0, 2], "Eylül yalnız gönderilen; Ekim boş; Kasım 2 gelen")
        XCTAssertEqual(r.map(\.sent), [1, 0, 1], "Eylül 1 gönderilen; Ekim boş; Kasım 1 gönderilen")
    }

    /// Pencereden (months) eski mailler hiç sayılmaz.
    func testExcludesOlderThanWindow() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2023, month: 11, day: 15))!
        let old = cal.date(from: DateComponents(year: 2023, month: 1, day: 5))!  // pencere dışı
        try store.upsert([
            msg("o1", mailbox: "INBOX", date: old),
            msg("o2", mailbox: "Sent", date: old),
        ])
        let r = try store.monthlySentReceived(months: 3, now: now, calendar: cal)
        XCTAssertEqual(r.reduce(0) { $0 + $1.received + $1.sent }, 0)
    }

    /// Çeşitli "gönderilmiş" kutu adları gönderilen; diğerleri (çöp/spam dahil) gelen sayılır.
    func testSentMailboxVariantsAndNonActionableAreReceived() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2023, month: 11, day: 15))!
        let d = cal.date(from: DateComponents(year: 2023, month: 11, day: 5, hour: 9))!
        try store.upsert([
            msg("a", mailbox: "Sent", date: d),
            msg("b", mailbox: "Giden", date: d),
            msg("c", mailbox: "Outbox", date: d),
            msg("e", mailbox: "INBOX", date: d),
            msg("f", mailbox: "Trash", date: d),    // çöp → monthlyCounts dışlamadığı için gelen sayılır
            msg("g", mailbox: "Spam", date: d),     // spam → gelen sayılır
        ])
        let r = try store.monthlySentReceived(months: 1, now: now, calendar: cal)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].sent, 3, "Sent/Giden/Outbox gönderilen")
        XCTAssertEqual(r[0].received, 3, "INBOX/Trash/Spam gelen (kutu filtresi yok)")
    }

    /// `received` + `sent` toplamı, aynı pencere için monthlyCounts ile birebir aynıdır (tutarlılık).
    func testTotalsMatchMonthlyCounts() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2023, month: 11, day: 15))!
        let nov = cal.date(from: DateComponents(year: 2023, month: 11, day: 2, hour: 9))!
        let oct = cal.date(from: DateComponents(year: 2023, month: 10, day: 9, hour: 9))!
        try store.upsert([
            msg("n1", mailbox: "INBOX", date: nov),
            msg("n2", mailbox: "Sent", date: nov),
            msg("n3", mailbox: "Archive", date: nov),
            msg("o1", mailbox: "Gönderilenler", date: oct),
        ])
        let counts = try store.monthlyCounts(months: 3, now: now, calendar: cal)
        let balance = try store.monthlySentReceived(months: 3, now: now, calendar: cal)
        XCTAssertEqual(counts.map(\.count), balance.map { $0.received + $0.sent },
                       "Her ayda gelen+gönderilen, monthlyCounts toplamına eşit olmalı")
    }

    /// months <= 0 boş döner (monthlyCounts ile aynı uç davranış).
    func testNonPositiveMonthsReturnsEmpty() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2023, month: 11, day: 15))!
        XCTAssertTrue(try store.monthlySentReceived(months: 0, now: now, calendar: cal).isEmpty)
    }

    /// Paylaşılan TurkishMonth yardımcısı: geçerli ay kısa ad; aralık dışı nil.
    func testTurkishMonthHelper() throws {
        XCTAssertEqual(TurkishMonth.short(1), "Oca")
        XCTAssertEqual(TurkishMonth.short(11), "Kas")
        XCTAssertEqual(TurkishMonth.short(12), "Ara")
        XCTAssertNil(TurkishMonth.short(0))
        XCTAssertNil(TurkishMonth.short(13))
    }
}
