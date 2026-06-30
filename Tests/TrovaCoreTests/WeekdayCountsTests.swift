import XCTest
@testable import TrovaCore

/// `IndexStore.weekdayCounts` — maillerin haftanın gününe göre dağılımı testleri.
/// Sabit `Calendar(identifier:.gregorian)` enjekte → deterministik (MonthlySentReceived deseniyle aynı).
final class WeekdayCountsTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    private func msg(_ id: String, date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: "K", fromAddress: "k@x.com", toField: nil,
            ccField: nil, subject: "S\(id)", date: date, snippet: "x", body: "x",
            indexedAt: Date(), attachments: nil)
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-weekday-\(UUID().uuidString).sqlite"))
    }

    /// Çıktı her zaman 7 eleman ve Pazartesi(1)→Pazar(7) sırasında döner.
    func testAlwaysSevenOrderedDays() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2024, month: 1, day: 10))!
        let r = try store.weekdayCounts(now: now, calendar: cal)
        XCTAssertEqual(r.map(\.weekday), [1, 2, 3, 4, 5, 6, 7], "Pzt→Paz sırası, 7 eleman")
        XCTAssertTrue(r.allSatisfy { $0.count == 0 }, "Mail yoksa tüm günler 0")
    }

    /// Bilinen tarihler doğru güne bucket'lanır; weekday eşlemesi SABİT Pzt=1..Paz=7.
    /// 2024-01-01 Pazartesi, 2024-01-07 Pazar (Gregoryen takvim, gerçek günler).
    func testKnownDatesMapToFixedWeekday() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 12))!
        let monday = cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 9))!   // Pazartesi
        let sunday = cal.date(from: DateComponents(year: 2024, month: 1, day: 7, hour: 9))!    // Pazar
        // Doğrulama: Gregoryen .weekday Pazartesi=2, Pazar=1 verir; eşleme bunu 1 / 7 yapmalı.
        XCTAssertEqual(cal.component(.weekday, from: monday), 2)
        XCTAssertEqual(cal.component(.weekday, from: sunday), 1)
        try store.upsert([msg("m", date: monday), msg("s", date: sunday)])
        let r = try store.weekdayCounts(now: now, calendar: cal)
        XCTAssertEqual(r.first { $0.weekday == 1 }?.count, 1, "Pazartesi → weekday 1")
        XCTAssertEqual(r.first { $0.weekday == 7 }?.count, 1, "Pazar → weekday 7")
    }

    /// Aynı güne düşen birden çok mail toplanır; diğer günler 0 kalır.
    func testCountsAccumulateAndMissingDaysZero() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2024, month: 1, day: 10))!
        // 2024-01-03 Çarşamba (weekday 3).
        let wed = cal.date(from: DateComponents(year: 2024, month: 1, day: 3, hour: 9))!
        try store.upsert([msg("a", date: wed), msg("b", date: wed), msg("c", date: wed)])
        let r = try store.weekdayCounts(now: now, calendar: cal)
        XCTAssertEqual(r.first { $0.weekday == 3 }?.count, 3, "Çarşamba 3 mail")
        XCTAssertEqual(r.filter { $0.weekday != 3 }.reduce(0) { $0 + $1.count }, 0, "Diğer günler 0")
        XCTAssertEqual(r.reduce(0) { $0 + $1.count }, 3, "Toplam tüm mail sayısına eşit")
    }

    /// Haftanın yedi gününün tamamı doğru güne dağılır (tam tur eşleme doğrulaması).
    func testFullWeekDistribution() throws {
        let store = try makeStore()
        let now = cal.date(from: DateComponents(year: 2024, month: 1, day: 14))!
        // 2024-01-01 Pazartesi ... 2024-01-07 Pazar → her gün bir mail.
        for day in 1...7 {
            let d = cal.date(from: DateComponents(year: 2024, month: 1, day: day, hour: 9))!
            try store.upsert([msg("d\(day)", date: d)])
        }
        let r = try store.weekdayCounts(now: now, calendar: cal)
        XCTAssertEqual(r.map(\.count), [1, 1, 1, 1, 1, 1, 1], "Her gün tam 1 mail")
    }

    /// Paylaşılan TurkishWeekday yardımcısı: doğru kısa Türkçe etiketler; aralık dışı nil.
    func testTurkishWeekdayHelper() throws {
        XCTAssertEqual(TurkishWeekday.short(1), "Pzt")
        XCTAssertEqual(TurkishWeekday.short(2), "Sal")
        XCTAssertEqual(TurkishWeekday.short(3), "Çar")
        XCTAssertEqual(TurkishWeekday.short(4), "Per")
        XCTAssertEqual(TurkishWeekday.short(5), "Cum")
        XCTAssertEqual(TurkishWeekday.short(6), "Cmt")
        XCTAssertEqual(TurkishWeekday.short(7), "Paz")
        XCTAssertNil(TurkishWeekday.short(0))
        XCTAssertNil(TurkishWeekday.short(8))
    }
}
