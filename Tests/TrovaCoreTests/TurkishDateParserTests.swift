import XCTest
@testable import TrovaCore

final class TurkishDateParserTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        c.firstWeekday = 2   // Pazartesi
        return c
    }()

    // Sabit referans an (deterministik testler için).
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day = 86_400.0

    func testLastNDays() {
        let r = TurkishDateParser.parse("son 7 gün fatura", now: now, calendar: cal)
        XCTAssertEqual(r.cleaned, "fatura")
        XCTAssertEqual(r.hint?.label, "son 7 gün")
        XCTAssertEqual(r.hint?.since, now.addingTimeInterval(-7 * day))
        XCTAssertNil(r.hint?.until)
    }

    func testLastNWeeks() {
        let r = TurkishDateParser.parse("son 3 hafta", now: now, calendar: cal)
        XCTAssertEqual(r.cleaned, "")
        XCTAssertEqual(r.hint?.label, "son 3 hafta")
        XCTAssertEqual(r.hint?.since, now.addingTimeInterval(-21 * day))
    }

    func testToday() {
        let r = TurkishDateParser.parse("bugün toplantı", now: now, calendar: cal)
        XCTAssertEqual(r.cleaned, "toplantı")
        XCTAssertEqual(r.hint?.since, cal.startOfDay(for: now))
        XCTAssertEqual(r.hint?.label, "bugün")
    }

    func testYesterday() {
        let r = TurkishDateParser.parse("dün rapor gönderildi", now: now, calendar: cal)
        XCTAssertEqual(r.cleaned, "rapor gönderildi")
        let startToday = cal.startOfDay(for: now)
        XCTAssertEqual(r.hint?.until, startToday)
        XCTAssertEqual(r.hint?.since, cal.date(byAdding: .day, value: -1, to: startToday))
    }

    func testThisMonth() {
        let r = TurkishDateParser.parse("bu ay maaş", now: now, calendar: cal)
        XCTAssertEqual(r.cleaned, "maaş")
        XCTAssertEqual(r.hint?.label, "bu ay")
        XCTAssertEqual(r.hint?.since, cal.dateInterval(of: .month, for: now)?.start)
    }

    func testLastMonth() {
        let r = TurkishDateParser.parse("geçen ay sözleşme", now: now, calendar: cal)
        XCTAssertEqual(r.cleaned, "sözleşme")
        XCTAssertEqual(r.hint?.label, "geçen ay")
        let monthStart = cal.dateInterval(of: .month, for: now)!.start
        XCTAssertEqual(r.hint?.until, monthStart)
        XCTAssertEqual(r.hint?.since, cal.date(byAdding: .month, value: -1, to: monthStart))
    }

    func testNoDatePhrase() {
        let r = TurkishDateParser.parse("fatura ödeme planı", now: now, calendar: cal)
        XCTAssertNil(r.hint)
        XCTAssertEqual(r.cleaned, "fatura ödeme planı")
    }

    func testOnlyFirstDateMatched() {
        // İlk tarih kazanır; ikinci tarih kelimesi sorguda kalır.
        let r = TurkishDateParser.parse("dün ve bugün", now: now, calendar: cal)
        XCTAssertEqual(r.hint?.label, "dün")
        XCTAssertEqual(r.cleaned, "ve bugün")
    }

    func testCaseInsensitive() {
        let r = TurkishDateParser.parse("DÜN toplantı", now: now, calendar: cal)
        XCTAssertEqual(r.hint?.label, "dün")
        XCTAssertEqual(r.cleaned, "toplantı")
    }

    func testSonWithoutNumberIsNotDate() {
        let r = TurkishDateParser.parse("son dakika haber", now: now, calendar: cal)
        XCTAssertNil(r.hint)
        XCTAssertEqual(r.cleaned, "son dakika haber")
    }
}
