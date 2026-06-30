import XCTest
@testable import TrovaCore

final class TermHighlighterTests: XCTestCase {

    /// Bir vurgunun metindeki kapsadığı alt dizgiyi (Character ofsetiyle) döndürür ve
    /// sınırların geçerli olduğunu doğrular.
    private func slice(_ text: String, _ r: HighlightRange) -> String {
        let chars = Array(text)
        XCTAssertGreaterThanOrEqual(r.start, 0)
        XCTAssertGreaterThan(r.length, 0)
        XCTAssertLessThanOrEqual(r.start + r.length, chars.count, "vurgu metin sınırını aşıyor")
        return String(chars[r.start..<(r.start + r.length)])
    }

    func testBosMetinBosTerim() {
        XCTAssertTrue(TermHighlighter.ranges(in: "", terms: ["fatura"]).isEmpty)
        XCTAssertTrue(TermHighlighter.ranges(in: "fatura geldi", terms: []).isEmpty)
        XCTAssertTrue(TermHighlighter.ranges(in: "", terms: []).isEmpty)
    }

    func testEslesmeYok() {
        let r = TermHighlighter.ranges(in: "Merhaba dünya nasılsın", terms: ["xyz"])
        XCTAssertTrue(r.isEmpty)
    }

    func testTekTerimTekGecisOfsetDogru() {
        let text = "Ekteki sözleşme belgesini inceleyin."
        let r = TermHighlighter.ranges(in: text, terms: ["sözleşme"])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(slice(text, r[0]), "sözleşme")
    }

    func testTumGecislerBulunur() {
        // "rapor" üç kez geçiyor; üçü de ayrı aralık olarak bulunmalı.
        let text = "rapor hazır, raporu gönder, son rapor ekte."
        let r = TermHighlighter.ranges(in: text, terms: ["rapor"])
        XCTAssertEqual(r.count, 3)
        for h in r { XCTAssertEqual(slice(text, h).lowercased(with: Locale(identifier: "tr_TR")), "rapor") }
        // Aralıklar artan başlangıç sırasında olmalı.
        XCTAssertEqual(r.map(\.start), r.map(\.start).sorted())
    }

    func testBuyukKucukHarfDuyarsizTurkce() {
        // Türkçe İ/i: "İstanbul" gövdesi "istanbul" terimiyle, "istanbul" gövdesi "İSTANBUL" ile eşleşir.
        let t1 = "Toplantı İstanbul ofisinde."
        let r1 = TermHighlighter.ranges(in: t1, terms: ["istanbul"])
        XCTAssertEqual(r1.count, 1)
        XCTAssertEqual(slice(t1, r1[0]), "İstanbul")

        let t2 = "merhaba istanbul"
        let r2 = TermHighlighter.ranges(in: t2, terms: ["İSTANBUL"])
        XCTAssertEqual(r2.count, 1)
        XCTAssertEqual(slice(t2, r2[0]), "istanbul")
    }

    func testCokluTerimAyriAraliklar() {
        let text = "fatura ve sözleşme aynı mailde."
        let r = TermHighlighter.ranges(in: text, terms: ["fatura", "sözleşme"])
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(slice(text, r[0]), "fatura")
        XCTAssertEqual(slice(text, r[1]), "sözleşme")
    }

    func testCakisanTerimlerBirlestirilir() {
        // "sözleşme" ve onun ön eki "söz" örtüşür → tek birleşik aralığa iner.
        let text = "Bu sözleşme önemli."
        let r = TermHighlighter.ranges(in: text, terms: ["sözleşme", "söz"])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(slice(text, r[0]), "sözleşme")
    }

    func testGrafemOfsetiCokBaytliKarakterSonrasi() {
        // Çok baytlı Türkçe karakterlerden SONRA gelen eşleşmenin grafem ofseti doğru olmalı.
        let text = "çğşüöı fatura"
        let r = TermHighlighter.ranges(in: text, terms: ["fatura"])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].start, 7)            // "çğşüöı " = 7 grafem
        XCTAssertEqual(slice(text, r[0]), "fatura")
    }
}
