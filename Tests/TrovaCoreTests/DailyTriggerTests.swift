import XCTest
@testable import TrovaCore

final class DailyTriggerTests: XCTestCase {
    /// Deterministik: sabit UTC takvimi (test dilime bağlı kalmasın).
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// UTC'de bir tarih/saat üretir.
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d
        comps.hour = h; comps.minute = mi; comps.second = s
        return cal.date(from: comps)!
    }

    // MARK: - nextFire

    /// Hedef bugün henüz gelmemişse bugünün hedefi döner.
    func testNextFireTargetLaterTodayReturnsToday() {
        let now = date(2026, 7, 2, 6, 0)
        let fire = DailyTrigger.nextFire(after: now, hour: 8, minute: 0, calendar: cal)
        XCTAssertEqual(fire, date(2026, 7, 2, 8, 0))
    }

    /// Hedef bugün geçmişse yarının hedefi döner.
    func testNextFireTargetPassedReturnsTomorrow() {
        let now = date(2026, 7, 2, 9, 30)
        let fire = DailyTrigger.nextFire(after: now, hour: 8, minute: 0, calendar: cal)
        XCTAssertEqual(fire, date(2026, 7, 3, 8, 0))
    }

    /// `now` tam hedefe eşitse "sonraki" bu an değil, ertesi günün hedefidir.
    func testNextFireExactlyAtTargetReturnsTomorrow() {
        let now = date(2026, 7, 2, 8, 0)
        let fire = DailyTrigger.nextFire(after: now, hour: 8, minute: 0, calendar: cal)
        XCTAssertEqual(fire, date(2026, 7, 3, 8, 0))
    }

    /// Dakika hassasiyeti: hedeften 1 dakika önce hâlâ bugünün hedefini döner.
    func testNextFireMinutePrecision() {
        let now = date(2026, 7, 2, 8, 29)
        let fire = DailyTrigger.nextFire(after: now, hour: 8, minute: 30, calendar: cal)
        XCTAssertEqual(fire, date(2026, 7, 2, 8, 30))
    }

    /// Ay sınırı: ayın son günü hedef geçmişse ertesi ayın 1'ine sarar.
    func testNextFireMonthBoundary() {
        let now = date(2026, 7, 31, 10, 0)
        let fire = DailyTrigger.nextFire(after: now, hour: 8, minute: 0, calendar: cal)
        XCTAssertEqual(fire, date(2026, 8, 1, 8, 0))
    }

    /// Yıl sınırı: 31 Aralık hedef geçmişse ertesi yılın 1 Ocak'ına sarar.
    func testNextFireYearBoundary() {
        let now = date(2026, 12, 31, 23, 0)
        let fire = DailyTrigger.nextFire(after: now, hour: 8, minute: 0, calendar: cal)
        XCTAssertEqual(fire, date(2027, 1, 1, 8, 0))
    }

    /// Gece yarısı hedefi (00:00): hedef geçmişse ertesi günün 00:00'ı döner.
    func testNextFireMidnightTarget() {
        let now = date(2026, 7, 2, 0, 30)
        let fire = DailyTrigger.nextFire(after: now, hour: 0, minute: 0, calendar: cal)
        XCTAssertEqual(fire, date(2026, 7, 3, 0, 0))
    }

    // MARK: - shouldFire

    /// Hedeften önce: ateşleme yok.
    func testShouldNotFireBeforeTarget() {
        let now = date(2026, 7, 2, 7, 59)
        XCTAssertFalse(DailyTrigger.shouldFire(now: now, hour: 8, minute: 0,
                                               lastFiredDay: nil, calendar: cal))
    }

    /// Tam hedef anında: hiç ateşlenmemişse ateşler.
    func testShouldFireExactlyAtTarget() {
        let now = date(2026, 7, 2, 8, 0)
        XCTAssertTrue(DailyTrigger.shouldFire(now: now, hour: 8, minute: 0,
                                              lastFiredDay: nil, calendar: cal))
    }

    /// Hedef geçmiş + hiç ateşlenmemiş (uygulama sonradan açıldı) → telafi ateşler.
    func testShouldFireAfterTargetWhenNeverFired() {
        let now = date(2026, 7, 2, 11, 0)
        XCTAssertTrue(DailyTrigger.shouldFire(now: now, hour: 8, minute: 0,
                                              lastFiredDay: nil, calendar: cal))
    }

    /// Bugün zaten ateşlendiyse (aynı gün, farklı an) tekrar ateşlemez.
    func testShouldNotFireWhenAlreadyFiredToday() {
        let now = date(2026, 7, 2, 11, 0)
        let firedEarlier = date(2026, 7, 2, 8, 0)
        XCTAssertFalse(DailyTrigger.shouldFire(now: now, hour: 8, minute: 0,
                                               lastFiredDay: firedEarlier, calendar: cal))
    }

    /// Dün ateşlendiyse bugün yeniden ateşler (her gün kendi hedefi).
    func testShouldFireWhenLastFiredYesterday() {
        let now = date(2026, 7, 2, 8, 0)
        let firedYesterday = date(2026, 7, 1, 8, 0)
        XCTAssertTrue(DailyTrigger.shouldFire(now: now, hour: 8, minute: 0,
                                              lastFiredDay: firedYesterday, calendar: cal))
    }

    /// Dakika hassasiyeti: hedeften 1 dakika önce ateşlemez, tam dakikada ateşler.
    func testShouldFireMinutePrecision() {
        XCTAssertFalse(DailyTrigger.shouldFire(now: date(2026, 7, 2, 8, 29), hour: 8, minute: 30,
                                               lastFiredDay: nil, calendar: cal))
        XCTAssertTrue(DailyTrigger.shouldFire(now: date(2026, 7, 2, 8, 30), hour: 8, minute: 30,
                                              lastFiredDay: nil, calendar: cal))
    }

    /// Gece yarısı hedefi: 00:00'da ateşler, 23:59'da (hedef henüz gelmemiş) ateşlemez.
    func testShouldFireMidnightBoundary() {
        XCTAssertTrue(DailyTrigger.shouldFire(now: date(2026, 7, 2, 0, 0), hour: 0, minute: 0,
                                              lastFiredDay: nil, calendar: cal))
        XCTAssertFalse(DailyTrigger.shouldFire(now: date(2026, 7, 2, 23, 59), hour: 0, minute: 0,
                                               lastFiredDay: date(2026, 7, 2, 0, 0), calendar: cal))
    }

    /// Gün sınırı: dün geç ateşlendi (23:00), bugün hedef (08:00) geldiğinde yeniden ateşler.
    func testShouldFireCrossingDayBoundary() {
        let now = date(2026, 7, 2, 8, 5)
        let firedLateYesterday = date(2026, 7, 1, 23, 0)
        XCTAssertTrue(DailyTrigger.shouldFire(now: now, hour: 8, minute: 0,
                                              lastFiredDay: firedLateYesterday, calendar: cal))
    }

    /// Ateşlemeden hemen sonraki dakika kontrolü (aynı gün, hedef geçmiş) tekrar ateşlemez.
    func testShouldNotRefireOneMinuteAfterFiring() {
        let firedAt = date(2026, 7, 2, 8, 0)
        let oneMinuteLater = date(2026, 7, 2, 8, 1)
        XCTAssertFalse(DailyTrigger.shouldFire(now: oneMinuteLater, hour: 8, minute: 0,
                                               lastFiredDay: firedAt, calendar: cal))
    }

    /// nextFire ile shouldFire tutarlı: tam hedef anında shouldFire=true iken nextFire yarını gösterir.
    func testNextFireAndShouldFireConsistentAtTarget() {
        let now = date(2026, 7, 2, 8, 0)
        XCTAssertTrue(DailyTrigger.shouldFire(now: now, hour: 8, minute: 0,
                                              lastFiredDay: nil, calendar: cal))
        XCTAssertEqual(DailyTrigger.nextFire(after: now, hour: 8, minute: 0, calendar: cal),
                       date(2026, 7, 3, 8, 0))
    }
}
