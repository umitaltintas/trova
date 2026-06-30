import XCTest
@testable import TrovaCore

final class RefreshCoalescerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let coalescer = RefreshCoalescer(window: 2)

    /// Olay yoksa asla tetiklenmez.
    func testNoEventsDoesNotFire() {
        XCTAssertFalse(coalescer.shouldFire(events: [], now: t0, lastFired: nil))
    }

    /// Pencere henüz dolmadıysa (olaylar hâlâ geliyor) tetiklenmez.
    func testWithinWindowDoesNotFire() {
        let events = [t0, t0.addingTimeInterval(0.5), t0.addingTimeInterval(1)]
        // Son olaydan yalnız 1 sn geçti; pencere 2 sn → henüz tetikleme.
        XCTAssertFalse(coalescer.shouldFire(events: events, now: t0.addingTimeInterval(2), lastFired: nil))
    }

    /// Pencere içi çok olay → sessizlikten sonra TEK tetik.
    func testManyEventsCoalesceToSingleFire() {
        let events = [t0, t0.addingTimeInterval(0.5), t0.addingTimeInterval(1)]
        // Son olay t0+1; t0+3'te 2 sn sessizlik doldu → tetikle.
        XCTAssertTrue(coalescer.shouldFire(events: events, now: t0.addingTimeInterval(3), lastFired: nil))
    }

    /// Pencere sınırı (tam window kadar sessizlik) tetiklemeye dahildir.
    func testExactWindowBoundaryFires() {
        XCTAssertTrue(coalescer.shouldFire(events: [t0], now: t0.addingTimeInterval(2), lastFired: nil))
    }

    /// Aynı olay grubu için zaten tetiklendiyse tekrar tetiklenmez.
    func testDoesNotRefireForSameGroup() {
        let events = [t0, t0.addingTimeInterval(1)]
        let firedAt = t0.addingTimeInterval(3)
        XCTAssertFalse(coalescer.shouldFire(events: events, now: t0.addingTimeInterval(4), lastFired: firedAt))
    }

    /// Sessizlikten sonra gelen İKİNCİ grup, ilk tetikten sonra yeniden tetikler.
    func testSecondGroupAfterSilenceFiresAgain() {
        let firstFired = t0.addingTimeInterval(3)
        // İlk grup (ve tetik) sonrası gelen yeni olaylar.
        let secondGroup = [t0.addingTimeInterval(10), t0.addingTimeInterval(10.5)]
        // Son olay t0+10.5; t0+13'te sessizlik doldu, lastFired (t0+3) son olaydan önce → tetikle.
        XCTAssertTrue(coalescer.shouldFire(events: secondGroup, now: t0.addingTimeInterval(13), lastFired: firstFired))
    }
}
