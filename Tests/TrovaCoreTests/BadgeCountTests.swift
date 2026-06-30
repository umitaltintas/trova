import XCTest
@testable import TrovaCore

final class BadgeCountTests: XCTestCase {

    func testZeroAndNegativeAreNil() {
        XCTAssertNil(BadgeCount.label(0))
        XCTAssertNil(BadgeCount.label(-1))
        XCTAssertNil(BadgeCount.label(-99))
    }

    func testSmallCountsAreLiteral() {
        XCTAssertEqual(BadgeCount.label(1), "1")
        XCTAssertEqual(BadgeCount.label(42), "42")
        XCTAssertEqual(BadgeCount.label(99), "99")
    }

    func testOverNinetyNineIsCapped() {
        XCTAssertEqual(BadgeCount.label(100), "99+")
        XCTAssertEqual(BadgeCount.label(12_345), "99+")
    }
}
