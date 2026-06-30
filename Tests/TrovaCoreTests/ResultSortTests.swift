import XCTest
@testable import TrovaCore

final class ResultSortTests: XCTestCase {

    /// Verilen id ve tarihle (saniye ofseti) bir SearchHit üretir.
    /// `offset` nil ise tarihsiz (date == nil) sonuç döner.
    private func hit(_ id: String, _ offset: TimeInterval?) -> SearchHit {
        let date = offset.map { Date(timeIntervalSince1970: $0) }
        return SearchHit(id: id, subject: id, fromName: nil, fromAddress: nil,
                         mailbox: "INBOX", date: date, snippet: "", score: 1.0)
    }

    /// En yeni: en büyük tarih başta.
    func testNewestPutsLatestFirst() {
        let hits = [hit("a", 100), hit("b", 300), hit("c", 200)]
        let out = ResultSorter.sort(hits, by: .newest)
        XCTAssertEqual(out.map(\.id), ["b", "c", "a"])
    }

    /// En eski: en küçük tarih başta.
    func testOldestPutsEarliestFirst() {
        let hits = [hit("a", 100), hit("b", 300), hit("c", 200)]
        let out = ResultSorter.sort(hits, by: .oldest)
        XCTAssertEqual(out.map(\.id), ["a", "c", "b"])
    }

    /// Tarihsiz (nil) sonuçlar en yenide de en eskide de SONA gider.
    func testNilDatesGoLastInBothDirections() {
        let hits = [hit("a", nil), hit("b", 200), hit("c", nil), hit("d", 100)]

        let newest = ResultSorter.sort(hits, by: .newest)
        XCTAssertEqual(newest.map(\.id), ["b", "d", "a", "c"])

        let oldest = ResultSorter.sort(hits, by: .oldest)
        XCTAssertEqual(oldest.map(\.id), ["d", "b", "a", "c"])
    }

    /// Alaka: girdi sırası birebir korunur (tarihten bağımsız).
    func testRelevancePreservesInputOrder() {
        let hits = [hit("a", 100), hit("b", 300), hit("c", nil), hit("d", 200)]
        let out = ResultSorter.sort(hits, by: .relevance)
        XCTAssertEqual(out.map(\.id), ["a", "b", "c", "d"])
    }

    /// Eşit tarihlerde sıralama kararlıdır: girdi sırası korunur (her iki yön).
    func testStableForEqualDates() {
        let hits = [hit("a", 100), hit("b", 100), hit("c", 100)]
        XCTAssertEqual(ResultSorter.sort(hits, by: .newest).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(ResultSorter.sort(hits, by: .oldest).map(\.id), ["a", "b", "c"])
    }

    /// Boş liste her düzende boş döner.
    func testEmptyList() {
        for order in ResultSort.allCases {
            XCTAssertEqual(ResultSorter.sort([], by: order).count, 0)
        }
    }
}
