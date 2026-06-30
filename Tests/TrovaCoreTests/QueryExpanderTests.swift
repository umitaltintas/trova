import XCTest
@testable import TrovaCore

final class QueryExpanderTests: XCTestCase {

    func testPicksMostFrequentAcrossDocs() {
        let docs = [
            "kira sözleşmesi yenileme",
            "kira sözleşmesi bitiyor",
            "fatura ödeme planı",
        ]
        let terms = QueryExpander.expansionTerms(query: "kira", docs: docs, maxTerms: 2)
        // "sözleşmesi" 2 belgede → ilk. "kira" sorgu terimi → hariç.
        XCTAssertEqual(terms.first, "sözleşmesi")
        XCTAssertFalse(terms.contains("kira"))
    }

    func testExcludesQueryTerms() {
        let terms = QueryExpander.expansionTerms(query: "fatura ödeme",
                                                 docs: ["fatura ödeme fatura ödeme elektrik"], maxTerms: 5)
        XCTAssertFalse(terms.contains("fatura"))
        XCTAssertFalse(terms.contains("ödeme"))
        XCTAssertTrue(terms.contains("elektrik"))
    }

    func testExcludesStopwordsAndShortAndNumbers() {
        let terms = QueryExpander.expansionTerms(query: "x",
                                                 docs: ["ve bu için 12 ab toplantı toplantı"], maxTerms: 5)
        XCTAssertFalse(terms.contains("ve"))
        XCTAssertFalse(terms.contains("bu"))
        XCTAssertFalse(terms.contains("için"))
        XCTAssertFalse(terms.contains("12"))   // sayı
        XCTAssertFalse(terms.contains("ab"))   // 2 harf
        XCTAssertTrue(terms.contains("toplantı"))
    }

    func testRespectsMaxTerms() {
        let docs = ["alfa beta gama delta epsilon zeta"]
        XCTAssertEqual(QueryExpander.expansionTerms(query: "x", docs: docs, maxTerms: 3).count, 3)
    }

    func testDeterministicTieBreakAlphabetical() {
        // Hepsi 1 belge, 1 frekans → alfabetik: "alfa","beta"
        let terms = QueryExpander.expansionTerms(query: "x", docs: ["zeta beta alfa"], maxTerms: 2)
        XCTAssertEqual(terms, ["alfa", "beta"])
    }

    func testEmptyDocsReturnsEmpty() {
        XCTAssertTrue(QueryExpander.expansionTerms(query: "kira", docs: [], maxTerms: 4).isEmpty)
    }
}
