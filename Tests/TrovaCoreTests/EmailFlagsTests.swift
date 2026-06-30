import XCTest
@testable import TrovaCore

final class EmailFlagsTests: XCTestCase {

    func testReadBit() {
        let f = EmailFlags(rawValue: 0x1)
        XCTAssertTrue(f.isRead)
        XCTAssertFalse(f.isFlagged)
        XCTAssertFalse(f.isAnswered)
    }

    func testFlaggedBit() {
        let f = EmailFlags(rawValue: 0x10)
        XCTAssertTrue(f.isFlagged)
        XCTAssertFalse(f.isRead)
        XCTAssertFalse(f.isAnswered)
    }

    func testAnsweredBit() {
        let f = EmailFlags(rawValue: 0x4)
        XCTAssertTrue(f.isAnswered)
        XCTAssertFalse(f.isRead)
        XCTAssertFalse(f.isFlagged)
    }

    func testReadAndFlaggedTogether() {
        let f = EmailFlags(rawValue: 0x11)   // 0x1 | 0x10
        XCTAssertTrue(f.isRead)
        XCTAssertTrue(f.isFlagged)
        XCTAssertFalse(f.isAnswered)
    }

    func testNoBits() {
        let f = EmailFlags(rawValue: 0x0)
        XCTAssertFalse(f.isRead)
        XCTAssertFalse(f.isFlagged)
        XCTAssertFalse(f.isAnswered)
    }

    func testRealisticPackedValue() {
        // Apple Mail flags alanı başka bitleri de paketler; ilgili bitleri yine de çözmeliyiz.
        // 0x15 = 0x1 (okundu) | 0x4 (yanıtlandı) | 0x10 (bayraklı)
        let f = EmailFlags(rawValue: 0x15)
        XCTAssertTrue(f.isRead)
        XCTAssertTrue(f.isAnswered)
        XCTAssertTrue(f.isFlagged)
    }
}
