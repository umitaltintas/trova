import XCTest
@testable import TrovaCore

final class SearchOperatorParserTests: XCTestCase {

    func testFromOperator() {
        let r = SearchOperatorParser.parse("from:ali fatura")
        XCTAssertEqual(r.fromContains, "ali")
        XCTAssertFalse(r.hasAttachment)
        XCTAssertEqual(r.cleaned, "fatura")
    }

    func testTurkishFromOperator() {
        let r = SearchOperatorParser.parse("gönderen:Veli toplantı")
        XCTAssertEqual(r.fromContains, "Veli")
        XCTAssertEqual(r.cleaned, "toplantı")
    }

    func testHasAttachment() {
        let r = SearchOperatorParser.parse("rapor has:attachment")
        XCTAssertTrue(r.hasAttachment)
        XCTAssertEqual(r.cleaned, "rapor")
    }

    func testTurkishHasAttachment() {
        let r = SearchOperatorParser.parse("has:ek sözleşme")
        XCTAssertTrue(r.hasAttachment)
        XCTAssertEqual(r.cleaned, "sözleşme")
    }

    func testCombinedOperators() {
        let r = SearchOperatorParser.parse("from:ali@x.com has:ek")
        XCTAssertEqual(r.fromContains, "ali@x.com")
        XCTAssertTrue(r.hasAttachment)
        XCTAssertEqual(r.cleaned, "")
    }

    func testPreservesValueCase() {
        let r = SearchOperatorParser.parse("FROM:Ahmet rapor")
        XCTAssertEqual(r.fromContains, "Ahmet")
        XCTAssertEqual(r.cleaned, "rapor")
    }

    func testNoOperators() {
        let r = SearchOperatorParser.parse("fatura ödeme planı")
        XCTAssertNil(r.fromContains)
        XCTAssertFalse(r.hasAttachment)
        XCTAssertEqual(r.cleaned, "fatura ödeme planı")
    }

    func testEmptyFromValueIgnored() {
        let r = SearchOperatorParser.parse("from: fatura")
        XCTAssertNil(r.fromContains)
        XCTAssertEqual(r.cleaned, "fatura")
    }
}
