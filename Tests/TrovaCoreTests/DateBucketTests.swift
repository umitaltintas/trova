import XCTest
@testable import TrovaCore

final class DateBucketTests: XCTestCase {

    // MARK: - Deterministik yardımcılar

    /// UTC + sabit firstWeekday ile deterministik bir Gregoryen takvim. Varsayılan firstWeekday=2
    /// (Pazartesi — tr_TR hafta başı).
    private func cal(firstWeekday: Int = 2) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = firstWeekday
        return c
    }

    /// Verilen bileşenlerden bir Date üretir (enjekte edilen takvimle).
    private func date(_ y: Int, _ mo: Int, _ da: Int, _ h: Int = 12, _ mi: Int = 0,
                      _ cal: Calendar) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = da; c.hour = h; c.minute = mi
        return cal.date(from: c)!
    }

    // MARK: - Tekil kova kuralları

    func testNilYieldsTarihsiz() {
        XCTAssertEqual(DateBucket.bucket(for: nil, now: Date(), calendar: cal()), .tarihsiz)
    }

    func testSameDayDifferentTimesIsBugun() {
        let c = cal()
        let now = date(2024, 6, 10, 12, 0, c)
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 6, 10, 9, 0, c), now: now, calendar: c), .bugun)
    }

    /// Gün sınırı: now günün başında (00:00), tarih bir önceki günün sonunda (23:59) → Dün.
    func testDayBoundaryPreviousDayIsDun() {
        let c = cal()
        let now = date(2024, 6, 10, 0, 0, c)
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 6, 9, 23, 59, c), now: now, calendar: c), .dun)
    }

    /// Gün sınırı: now günün sonunda (23:59), tarih aynı günün başında (00:00) → hâlâ Bugün.
    func testLateNightSameDayIsBugun() {
        let c = cal()
        let now = date(2024, 6, 10, 23, 59, c)
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 6, 10, 0, 0, c), now: now, calendar: c), .bugun)
    }

    func testYesterdayIsDun() {
        let c = cal()
        let now = date(2024, 6, 10, 12, 0, c)
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 6, 9, 8, 0, c), now: now, calendar: c), .dun)
    }

    /// Hafta başı sınırı (firstWeekday=2, Pazartesi): now = Çrş 2024-06-12; hafta = Pzt 06-10 … Paz 06-16.
    /// Haftanın başındaki Pazartesi (bugün/dün değil) → Bu Hafta; bir önceki günkü Pazar (önceki hafta) → değil.
    func testWeekStartBoundaryMonday() {
        let c = cal(firstWeekday: 2)
        let now = date(2024, 6, 12, 12, 0, c)                 // Çarşamba
        // Pzt 06-10: aynı hafta, bugün/dün değil → Bu Hafta.
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 6, 10, 9, 0, c), now: now, calendar: c), .buHafta)
        // Paz 06-09: önceki hafta (Pazartesi başlangıçlı) → Bu Hafta DEĞİL, aynı ay → Bu Ay.
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 6, 9, 9, 0, c), now: now, calendar: c), .buAy)
    }

    /// Aynı sınır, firstWeekday=1 (Pazar): şimdi 06-09 Pazar haftanın BAŞI olur → Bu Hafta.
    /// firstWeekday'in kararı gerçekten etkilediğini gösterir.
    func testWeekRespectsFirstWeekdaySunday() {
        let c = cal(firstWeekday: 1)
        let now = date(2024, 6, 12, 12, 0, c)                 // Çarşamba; hafta = Paz 06-09 … Cmt 06-15
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 6, 9, 9, 0, c), now: now, calendar: c), .buHafta)
    }

    /// Ay sınırı: aynı ay ama bu hafta değil → Bu Ay.
    func testSameMonthNotThisWeekIsBuAy() {
        let c = cal()
        let now = date(2024, 2, 15, 12, 0, c)                 // hafta = 02-12 … 02-18
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 2, 2, 9, 0, c), now: now, calendar: c), .buAy)
    }

    /// Ay sınırı: farklı ay → Daha Eski (bu hafta/ay değil).
    func testDifferentMonthIsDahaEski() {
        let c = cal()
        let now = date(2024, 2, 15, 12, 0, c)
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 1, 15, 9, 0, c), now: now, calendar: c), .dahaEski)
    }

    /// Yıl sınırı: ay numarası aynı ama yıl farklı → aynı ay SAYILMAZ → Daha Eski.
    func testYearBoundarySameMonthNumberIsDahaEski() {
        let c = cal()
        let now = date(2025, 1, 15, 12, 0, c)
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 1, 15, 9, 0, c), now: now, calendar: c), .dahaEski)
        // Aralık 2024, hemen önceki ay ama önceki yıl → yine Daha Eski (aynı ay değil).
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 12, 20, 9, 0, c), now: now, calendar: c), .dahaEski)
    }

    // MARK: - Gelecek tarih kararı

    /// Gelecek ama aynı gün → Bugün (aynı içerme kuralı geçmiş/gelecek ayırt etmez).
    func testFutureSameDayIsBugun() {
        let c = cal()
        let now = date(2024, 6, 10, 8, 0, c)
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 6, 10, 20, 0, c), now: now, calendar: c), .bugun)
    }

    /// Gelecek ama aynı hafta → Bu Hafta (now Pzt 06-10, tarih Çrş 06-12).
    func testFutureSameWeekIsBuHafta() {
        let c = cal(firstWeekday: 2)
        let now = date(2024, 6, 10, 12, 0, c)                 // Pazartesi
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 6, 12, 12, 0, c), now: now, calendar: c), .buHafta)
    }

    /// Uzak gelecek (bu aydan öte) → Daha Eski (kararımız: ayrı "gelecek" kovası yok).
    func testFutureFarIsDahaEski() {
        let c = cal()
        let now = date(2024, 6, 10, 12, 0, c)
        XCTAssertEqual(DateBucket.bucket(for: date(2024, 8, 1, 12, 0, c), now: now, calendar: c), .dahaEski)
    }

    // MARK: - grouped

    private struct Item { let id: String; let date: Date? }

    /// grouped: kova sırası enum sırası; kova içi girdi sırası korunur; boş kovalar atlanır.
    func testGroupedOrderAndEmptySkipAndBucketOrder() {
        let c = cal(firstWeekday: 2)
        let now = date(2024, 6, 10, 12, 0, c)                 // Pazartesi; hafta = 06-10 … 06-16
        let items = [
            Item(id: "a", date: date(2024, 6, 10, 9, 0, c)),  // Bugün
            Item(id: "b", date: nil),                          // Tarihsiz
            Item(id: "c", date: date(2024, 6, 2, 9, 0, c)),   // Bu Ay (önceki hafta, aynı ay)
            Item(id: "d", date: date(2024, 6, 10, 20, 0, c)), // Bugün
            Item(id: "e", date: date(2024, 6, 3, 9, 0, c)),   // Bu Ay
        ]
        let grouped = DateBucket.grouped(items, date: { $0.date }, now: now, calendar: c)

        // Boş kovalar (Dün, Bu Hafta, Daha Eski) atlanır; kalanlar enum sırasında.
        XCTAssertEqual(grouped.map(\.bucket), [.bugun, .buAy, .tarihsiz])
        // Kova içi girdi sırası korunur.
        XCTAssertEqual(grouped[0].items.map(\.id), ["a", "d"])   // Bugün
        XCTAssertEqual(grouped[1].items.map(\.id), ["c", "e"])   // Bu Ay
        XCTAssertEqual(grouped[2].items.map(\.id), ["b"])        // Tarihsiz
    }

    func testGroupedEmptyInputYieldsEmpty() {
        let grouped = DateBucket.grouped([Item](), date: { $0.date }, now: Date(), calendar: cal())
        XCTAssertTrue(grouped.isEmpty)
    }

    // MARK: - Enum sözleşmesi

    /// CaseIterable sırası = gösterim sırası; etiketler Türkçe ve beklenen sırada.
    func testAllCasesOrderAndLabels() {
        XCTAssertEqual(DateBucket.allCases, [.bugun, .dun, .buHafta, .buAy, .dahaEski, .tarihsiz])
        XCTAssertEqual(DateBucket.allCases.map(\.label),
                       ["Bugün", "Dün", "Bu Hafta", "Bu Ay", "Daha Eski", "Tarihsiz"])
    }
}
