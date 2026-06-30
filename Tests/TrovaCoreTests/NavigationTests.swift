import XCTest
@testable import TrovaCore

final class NavigationTests: XCTestCase {

    func testEmptyListReturnsNil() {
        XCTAssertNil(Navigation.adjacent(ids: [], current: nil, delta: 1))
        XCTAssertNil(Navigation.adjacent(ids: [], current: "a", delta: -1))
    }

    func testForwardFromMiddle() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(Navigation.adjacent(ids: ids, current: "b", delta: 1), "c")
    }

    func testBackwardFromMiddle() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(Navigation.adjacent(ids: ids, current: "b", delta: -1), "a")
    }

    func testClampsAtEnd() {
        let ids = ["a", "b", "c"]
        // Son öğedeyken ileri gidince aynı (son) id döner — kenetlenir, sarmaz.
        XCTAssertEqual(Navigation.adjacent(ids: ids, current: "c", delta: 1), "c")
    }

    func testClampsAtStart() {
        let ids = ["a", "b", "c"]
        // İlk öğedeyken geri gidince aynı (ilk) id döner — kenetlenir, sarmaz.
        XCTAssertEqual(Navigation.adjacent(ids: ids, current: "a", delta: -1), "a")
    }

    func testCurrentNilForwardReturnsFirst() {
        XCTAssertEqual(Navigation.adjacent(ids: ["a", "b", "c"], current: nil, delta: 1), "a")
    }

    func testCurrentNilBackwardReturnsLast() {
        XCTAssertEqual(Navigation.adjacent(ids: ["a", "b", "c"], current: nil, delta: -1), "c")
    }

    func testCurrentNotInListForwardReturnsFirst() {
        XCTAssertEqual(Navigation.adjacent(ids: ["a", "b", "c"], current: "x", delta: 1), "a")
    }

    func testCurrentNotInListBackwardReturnsLast() {
        XCTAssertEqual(Navigation.adjacent(ids: ["a", "b", "c"], current: "x", delta: -1), "c")
    }

    func testSingleElementClampsBothWays() {
        XCTAssertEqual(Navigation.adjacent(ids: ["only"], current: "only", delta: 1), "only")
        XCTAssertEqual(Navigation.adjacent(ids: ["only"], current: "only", delta: -1), "only")
    }

    func testLargerDeltaClampsWithinBounds() {
        let ids = ["a", "b", "c", "d"]
        XCTAssertEqual(Navigation.adjacent(ids: ids, current: "b", delta: 5), "d")
        XCTAssertEqual(Navigation.adjacent(ids: ids, current: "c", delta: -5), "a")
    }

    func testZeroDeltaReturnsSameID() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(Navigation.adjacent(ids: ids, current: "b", delta: 0), "b")
    }
}
