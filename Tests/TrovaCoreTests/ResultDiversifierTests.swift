import XCTest
@testable import TrovaCore

final class ResultDiversifierTests: XCTestCase {

    /// Sıralı bir SearchHit üretir; skor sıraya göre azalır, thread anahtarı verilir.
    private func hit(_ id: String, thread: String?) -> SearchHit {
        SearchHit(id: id, subject: id, fromName: nil, fromAddress: nil,
                  mailbox: "INBOX", date: nil, snippet: "", score: 1.0, threadKey: thread)
    }

    func testCapsPerThreadPreservingOrder() {
        // Sıra: A A B A C C C  → maxPerThread=2 → A A B C C
        let hits = [
            hit("a1", thread: "A"), hit("a2", thread: "A"), hit("b1", thread: "B"),
            hit("a3", thread: "A"), hit("c1", thread: "C"), hit("c2", thread: "C"),
            hit("c3", thread: "C"),
        ]
        let out = ResultDiversifier.diversify(hits, maxPerThread: 2, limit: 10)
        XCTAssertEqual(out.map(\.id), ["a1", "a2", "b1", "c1", "c2"])
    }

    func testNilThreadKeysAlwaysKept() {
        // threadKey'i olmayanlar her biri benzersiz konuşma; hiçbiri elenmez.
        let hits = [
            hit("x", thread: nil), hit("y", thread: nil), hit("z", thread: nil),
            hit("a1", thread: "A"), hit("a2", thread: "A"), hit("a3", thread: "A"),
        ]
        let out = ResultDiversifier.diversify(hits, maxPerThread: 1, limit: 10)
        XCTAssertEqual(out.map(\.id), ["x", "y", "z", "a1"])
    }

    func testEmptyThreadKeyTreatedAsUnique() {
        let hits = [hit("p", thread: ""), hit("q", thread: ""), hit("r", thread: "")]
        let out = ResultDiversifier.diversify(hits, maxPerThread: 1, limit: 10)
        XCTAssertEqual(out.count, 3)
    }

    func testRespectsLimit() {
        let hits = (1...20).map { hit("m\($0)", thread: nil) }
        let out = ResultDiversifier.diversify(hits, maxPerThread: 2, limit: 5)
        XCTAssertEqual(out.count, 5)
        XCTAssertEqual(out.first?.id, "m1")
    }

    func testBackfillsDistinctFromDeeperPool() {
        // İlk sıralarda tek thread tıkar; çeşitlendirme derinden farklı konuşmaları öne çeker.
        let hits = [
            hit("a1", thread: "A"), hit("a2", thread: "A"), hit("a3", thread: "A"),
            hit("a4", thread: "A"), hit("b1", thread: "B"), hit("c1", thread: "C"),
        ]
        let out = ResultDiversifier.diversify(hits, maxPerThread: 1, limit: 3)
        XCTAssertEqual(out.map(\.id), ["a1", "b1", "c1"])
    }

    func testZeroMaxFallsBackToPlainPrefix() {
        let hits = [hit("a1", thread: "A"), hit("a2", thread: "A")]
        let out = ResultDiversifier.diversify(hits, maxPerThread: 0, limit: 5)
        XCTAssertEqual(out.map(\.id), ["a1", "a2"])
    }
}
