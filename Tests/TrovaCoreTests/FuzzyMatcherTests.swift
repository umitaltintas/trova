import XCTest
@testable import TrovaCore

final class FuzzyMatcherTests: XCTestCase {

    func testExactSubstringMatches() {
        XCTAssertNotNil(FuzzyMatcher.score("ara", "Ara"))
        XCTAssertNotNil(FuzzyMatcher.score("sor", "Sor"))
    }

    func testNonSubsequenceReturnsNil() {
        XCTAssertNil(FuzzyMatcher.score("xyz", "Ara"))
        XCTAssertNil(FuzzyMatcher.score("zor", "Sor"))   // z yok
    }

    func testSubsequenceMatchesWithGaps() {
        // "kil" → Kişiler içinde k,i,l sırayla geçer
        XCTAssertNotNil(FuzzyMatcher.score("kil", "Kişiler"))
    }

    func testEmptyQueryScoresZero() {
        XCTAssertEqual(FuzzyMatcher.score("", "herhangi"), 0)
    }

    func testLongerQueryThanCandidateFails() {
        XCTAssertNil(FuzzyMatcher.score("uzunca", "kısa"))
    }

    func testConsecutiveScoresHigherThanGapped() {
        let consecutive = FuzzyMatcher.score("son", "sonuç")!     // s-o-n ardışık
        let gapped = FuzzyMatcher.score("son", "salonun")!        // s..o..n boşluklu
        XCTAssertGreaterThan(consecutive, gapped)
    }

    func testWordStartBonus() {
        // "b" baştaysa (Bugün) ortada olmasından daha yüksek skor alır.
        let start = FuzzyMatcher.score("b", "Bugün")!
        let middle = FuzzyMatcher.score("b", "Abone")!
        XCTAssertGreaterThan(start, middle)
    }

    func testRankSortsByScoreAndDropsNonMatches() {
        let items = ["Ara", "Sor", "Bugün", "Kişiler"]
        let ranked = FuzzyMatcher.rank("s", items, key: { $0 })
        XCTAssertTrue(ranked.contains("Sor"))
        XCTAssertFalse(ranked.contains("Bugün"))   // 's' yok
    }

    func testRankEmptyQueryPreservesOrder() {
        let items = ["bir", "iki", "üç"]
        XCTAssertEqual(FuzzyMatcher.rank("", items, key: { $0 }), items)
    }
}
