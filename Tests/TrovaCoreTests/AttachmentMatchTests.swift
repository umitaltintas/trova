import XCTest
@testable import TrovaCore

/// `AttachmentMatch.matching` — sonuç satırında "hangi ek eşleşti" rozetini besleyen saf eşleştirici.
final class AttachmentMatchTests: XCTestCase {

    func testTermInNameMatches() {
        let names = ["rapor.pdf", "logo.png"]
        XCTAssertEqual(AttachmentMatch.matching(names: names, terms: ["rapor"]), ["rapor.pdf"])
    }

    func testTermNotPresentReturnsEmpty() {
        XCTAssertTrue(AttachmentMatch.matching(names: ["rapor.pdf"], terms: ["bütçe"]).isEmpty)
    }

    func testCaseInsensitiveTurkish() {
        // Türkçe küçük harf indirgemesi: "İSTANBUL" ↔ "istanbul", "ŞİRKET" ↔ "şirket".
        XCTAssertEqual(
            AttachmentMatch.matching(names: ["İSTANBUL_Plan.pdf"], terms: ["istanbul"]),
            ["İSTANBUL_Plan.pdf"])
        XCTAssertEqual(
            AttachmentMatch.matching(names: ["Şirket_Sunum.key"], terms: ["şirket"]),
            ["Şirket_Sunum.key"])
        // Terim büyük harf, ad küçük harf de eşleşir.
        XCTAssertEqual(
            AttachmentMatch.matching(names: ["rapor.pdf"], terms: ["RAPOR"]),
            ["rapor.pdf"])
    }

    func testMultipleAttachmentsKeepsOrderAndOnlyMatches() {
        let names = ["fatura_mart.pdf", "logo.png", "fatura_nisan.pdf"]
        XCTAssertEqual(
            AttachmentMatch.matching(names: names, terms: ["fatura"]),
            ["fatura_mart.pdf", "fatura_nisan.pdf"])
    }

    func testAnyOfMultipleTermsMatches() {
        let names = ["sözleşme.docx", "ekran.png"]
        XCTAssertEqual(
            AttachmentMatch.matching(names: names, terms: ["bütçe", "ekran"]),
            ["ekran.png"])
    }

    func testEmptyTermsOrNamesReturnsEmpty() {
        XCTAssertTrue(AttachmentMatch.matching(names: ["a.pdf"], terms: []).isEmpty)
        XCTAssertTrue(AttachmentMatch.matching(names: [], terms: ["a"]).isEmpty)
        // Boş terim yok sayılır (her ada uyan bir eşleşme üretmez).
        XCTAssertTrue(AttachmentMatch.matching(names: ["a.pdf"], terms: [""]).isEmpty)
    }
}
