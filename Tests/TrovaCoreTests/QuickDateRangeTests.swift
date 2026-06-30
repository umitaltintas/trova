import XCTest
@testable import TrovaCore

final class QuickDateRangeTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        c.firstWeekday = 2   // Pazartesi
        return c
    }()

    // Sabit referans an (deterministik testler için).
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testTodayStartsAtDayStart() {
        let r = QuickDate.range(.today, now: now, calendar: cal)
        XCTAssertEqual(r.since, cal.startOfDay(for: now))
        XCTAssertNil(r.until)
    }

    func testLast7IsSevenDayStartsBack() {
        let r = QuickDate.range(.last7, now: now, calendar: cal)
        XCTAssertEqual(r.since, cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)))
        XCTAssertNil(r.until)
    }

    func testLast30IsThirtyDayStartsBack() {
        let r = QuickDate.range(.last30, now: now, calendar: cal)
        XCTAssertEqual(r.since, cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: now)))
        XCTAssertNil(r.until)
    }

    func testThisYearStartsAtYearStart() {
        let r = QuickDate.range(.thisYear, now: now, calendar: cal)
        XCTAssertEqual(r.since, cal.dateInterval(of: .year, for: now)?.start)
        XCTAssertNil(r.until)
    }

    // Tüm türlerde alt sınır now'dan önce/eşit ve üst sınır açık (şimdiye kadar).
    func testSinceNotAfterNowForAllKinds() {
        for kind in QuickDateRange.allCases {
            let r = QuickDate.range(kind, now: now, calendar: cal)
            XCTAssertLessThanOrEqual(r.since, now, "\(kind) için since now'dan sonra olmamalı")
            XCTAssertNil(r.until, "\(kind) için until açık (nil) olmalı")
        }
    }

    func testLabels() {
        XCTAssertEqual(QuickDateRange.today.label, "Bugün")
        XCTAssertEqual(QuickDateRange.last7.label, "Son 7 gün")
        XCTAssertEqual(QuickDateRange.last30.label, "Son 30 gün")
        XCTAssertEqual(QuickDateRange.thisYear.label, "Bu yıl")
    }
}
