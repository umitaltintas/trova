import XCTest
@testable import TrovaCore

final class RecentSearchesTests: XCTestCase {

    func testAddToEmptyPutsItemFirst() {
        var r = RecentSearches()
        r.add("fatura")
        XCTAssertEqual(r.items, ["fatura"])
    }

    func testSecondAddPushesFirstDown() {
        var r = RecentSearches()
        r.add("ilk")
        r.add("ikinci")
        // En yeni başta.
        XCTAssertEqual(r.items, ["ikinci", "ilk"])
    }

    func testReaddingMovesToFrontWithoutDuplicateCaseInsensitive() {
        var r = RecentSearches()
        r.add("Ahmet")
        r.add("Mehmet")
        r.add("ahmet")   // aynı sorgu (case-insensitive) — başa taşınmalı, çift kayıt olmamalı
        XCTAssertEqual(r.items, ["ahmet", "Mehmet"])
        XCTAssertEqual(r.items.count, 2)
    }

    func testEmptyOrWhitespaceQueryIgnored() {
        var r = RecentSearches()
        r.add("fatura")
        r.add("")
        r.add("   ")
        XCTAssertEqual(r.items, ["fatura"])
    }

    func testLimitDropsOldest() {
        var r = RecentSearches(limit: 3)
        r.add("a")
        r.add("b")
        r.add("c")
        r.add("d")
        // En eski ("a") düşmeli, 3 kayıt kalmalı.
        XCTAssertEqual(r.items, ["d", "c", "b"])
        XCTAssertFalse(r.items.contains("a"))
    }

    func testInitNormalizes() {
        let r = RecentSearches(items: ["  fatura  ", "", "Fatura", "  ", "ali"])
        // Trim edilir, boşlar atılır, tekrarlar (case-insensitive) elenir; ilk görülen korunur.
        XCTAssertEqual(r.items, ["fatura", "ali"])
    }

    func testInitTrimsToLimit() {
        let r = RecentSearches(items: ["a", "b", "c", "d", "e"], limit: 3)
        XCTAssertEqual(r.items, ["a", "b", "c"])
    }

    func testClearEmptiesList() {
        var r = RecentSearches()
        r.add("a")
        r.add("b")
        r.clear()
        XCTAssertTrue(r.items.isEmpty)
    }
}
