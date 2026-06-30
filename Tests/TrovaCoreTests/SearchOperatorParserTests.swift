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

    // MARK: - Ek türü operatörleri (has:<tür> / ek:<tür> / tür:<tür>)

    func testHasPdfKind() {
        let r = SearchOperatorParser.parse("has:pdf")
        XCTAssertEqual(r.attachmentKind, .pdf)
        XCTAssertFalse(r.hasAttachment)       // tür belirten operatör "ekli"yi tetiklemez
        XCTAssertEqual(r.cleaned, "")
    }

    func testEkGorselKindTurkish() {
        let r = SearchOperatorParser.parse("ek:görsel")
        XCTAssertEqual(r.attachmentKind, .image)
        XCTAssertEqual(r.cleaned, "")
    }

    func testTurTabloKind() {
        let r = SearchOperatorParser.parse("tür:tablo")
        XCTAssertEqual(r.attachmentKind, .sheet)
        XCTAssertEqual(r.cleaned, "")
    }

    func testHasAttachmentStillAnyAttachment() {
        // "has:attachment" hâlâ herhangi-ek anlamı taşır; tür filtresi etkilenmez.
        let r = SearchOperatorParser.parse("has:attachment")
        XCTAssertTrue(r.hasAttachment)
        XCTAssertNil(r.attachmentKind)
        XCTAssertEqual(r.cleaned, "")
    }

    func testMixedFromKindAndText() {
        let r = SearchOperatorParser.parse("from:ali has:pdf rapor")
        XCTAssertEqual(r.fromContains, "ali")
        XCTAssertEqual(r.attachmentKind, .pdf)
        XCTAssertFalse(r.hasAttachment)
        XCTAssertEqual(r.cleaned, "rapor")
    }

    func testKindOperatorCaseInsensitive() {
        XCTAssertEqual(SearchOperatorParser.parse("has:PDF").attachmentKind, .pdf)
        XCTAssertEqual(SearchOperatorParser.parse("TÜR:Tablo").attachmentKind, .sheet)
    }

    func testUnknownKindStaysInQuery() {
        // Tanınmayan tür → token aramada kalır, filtre kurulmaz.
        let r = SearchOperatorParser.parse("has:uçak fatura")
        XCTAssertNil(r.attachmentKind)
        XCTAssertEqual(r.cleaned, "has:uçak fatura")
    }
}
