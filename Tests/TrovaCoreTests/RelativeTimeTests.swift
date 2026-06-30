import XCTest
@testable import TrovaCore

final class RelativeTimeTests: XCTestCase {

    // Locale'den bağımsız, deterministik takvim.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        c.firstWeekday = 2   // Pazartesi
        return c
    }()

    // Sabit referans an: 15 Haziran 2024, 12:00 (Istanbul).
    private lazy var now: Date = cal.date(from: DateComponents(
        year: 2024, month: 6, day: 15, hour: 12, minute: 0))!

    private func at(_ year: Int, _ month: Int, _ day: Int,
                    _ hour: Int = 12, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day,
                                      hour: hour, minute: minute))!
    }

    // MARK: - format()

    func testFormatJustNow() {
        XCTAssertEqual(RelativeTime.format(now.addingTimeInterval(-30), now: now, calendar: cal),
                       "az önce")
    }

    func testFormatFutureIsJustNow() {
        // Gelecekteki tarih makul davranmalı.
        XCTAssertEqual(RelativeTime.format(now.addingTimeInterval(120), now: now, calendar: cal),
                       "az önce")
    }

    func testFormatMinutes() {
        XCTAssertEqual(RelativeTime.format(now.addingTimeInterval(-5 * 60), now: now, calendar: cal),
                       "5 dk önce")
    }

    func testFormatHours() {
        XCTAssertEqual(RelativeTime.format(now.addingTimeInterval(-3 * 3_600), now: now, calendar: cal),
                       "3 saat önce")
    }

    func testFormatYesterdayIsCalendarDay() {
        // 14 Haziran 23:00 → takvim olarak dün (saat farkı 13 saat olsa da).
        XCTAssertEqual(RelativeTime.format(at(2024, 6, 14, 23, 0), now: now, calendar: cal), "dün")
    }

    func testFormatHoursSameDayUpperBound() {
        // Aynı takvim günü içinde 22 saat → hâlâ "saat" (gün sınırı aşılmadı).
        let nowLate = at(2024, 6, 15, 23, 0)
        XCTAssertEqual(RelativeTime.format(at(2024, 6, 15, 1, 0), now: nowLate, calendar: cal),
                       "22 saat önce")
    }

    func testFormatYesterdayFewHoursAcrossMidnight() {
        // Gün sınırı aşıldıysa saat farkı az olsa da "dün" (saat farkı değil, takvim günü).
        let nowEarly = at(2024, 6, 15, 2, 0)
        XCTAssertEqual(RelativeTime.format(at(2024, 6, 14, 23, 0), now: nowEarly, calendar: cal), "dün")
    }

    func testFormatDaysAgo() {
        XCTAssertEqual(RelativeTime.format(at(2024, 6, 11), now: now, calendar: cal), "4 gün önce")
    }

    func testFormatLastWeek() {
        XCTAssertEqual(RelativeTime.format(at(2024, 6, 6), now: now, calendar: cal), "geçen hafta")
    }

    func testFormatWeeksAgo() {
        XCTAssertEqual(RelativeTime.format(at(2024, 5, 28), now: now, calendar: cal), "2 hafta önce")
    }

    func testFormatLastMonth() {
        XCTAssertEqual(RelativeTime.format(at(2024, 5, 1), now: now, calendar: cal), "geçen ay")
    }

    func testFormatMonthsAgo() {
        XCTAssertEqual(RelativeTime.format(at(2024, 2, 10), now: now, calendar: cal), "4 ay önce")
    }

    func testFormatSameYearOlderAbsolute() {
        // 7 ay önce, aynı yıl → "5 Mar".
        let n = at(2024, 11, 20)
        XCTAssertEqual(RelativeTime.format(at(2024, 3, 5), now: n, calendar: cal), "5 Mar")
    }

    func testFormatDifferentYearAbsolute() {
        XCTAssertEqual(RelativeTime.format(at(2022, 3, 5), now: now, calendar: cal), "5 Mar 2022")
    }

    // MARK: - short()

    func testShortNow() {
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-10), now: now, calendar: cal), "şimdi")
    }

    func testShortMinutes() {
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-5 * 60), now: now, calendar: cal), "5dk")
    }

    func testShortHours() {
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-2 * 3_600), now: now, calendar: cal), "2sa")
    }

    func testShortYesterday() {
        XCTAssertEqual(RelativeTime.short(at(2024, 6, 14, 23, 0), now: now, calendar: cal), "dün")
    }

    func testShortDays() {
        XCTAssertEqual(RelativeTime.short(at(2024, 6, 12), now: now, calendar: cal), "3g")
    }

    func testShortWeeks() {
        XCTAssertEqual(RelativeTime.short(at(2024, 5, 28), now: now, calendar: cal), "2h")
    }

    func testShortSameYearMonth() {
        let n = at(2024, 11, 20)
        XCTAssertEqual(RelativeTime.short(at(2024, 3, 5), now: n, calendar: cal), "Mar")
    }

    func testShortDifferentYearMonth() {
        XCTAssertEqual(RelativeTime.short(at(2022, 3, 5), now: now, calendar: cal), "Mar 22")
    }

    // MARK: - absolute()

    func testAbsoluteFormat() {
        XCTAssertEqual(RelativeTime.absolute(at(2024, 3, 5, 14, 30), calendar: cal),
                       "5 Mart 2024 14:30")
    }

    func testAbsolutePadsTime() {
        XCTAssertEqual(RelativeTime.absolute(at(2024, 1, 9, 9, 5), calendar: cal),
                       "9 Ocak 2024 09:05")
    }
}
