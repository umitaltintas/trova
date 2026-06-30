import XCTest
@testable import TrovaCore

final class SnippetExtractorTests: XCTestCase {

    /// Bir vurgunun snippet metnindeki kapsadığı alt dizgiyi (Character ofsetiyle) döndürür.
    private func slice(_ s: Snippet, _ h: SnippetHighlight) -> String {
        let chars = Array(s.text)
        XCTAssertGreaterThanOrEqual(h.start, 0)
        XCTAssertLessThanOrEqual(h.start + h.length, chars.count, "vurgu metin sınırını aşıyor")
        return String(chars[h.start..<(h.start + h.length)])
    }

    func testBosGovdeBosSnippet() {
        let s = SnippetExtractor.make(body: "", terms: ["fatura"])
        XCTAssertEqual(s.text, "")
        XCTAssertTrue(s.highlights.isEmpty)
    }

    func testEslesmeYokBastanKirpmaVeUcNokta() {
        let body = String(repeating: "abc defg ", count: 60)   // > 200 karakter
        let s = SnippetExtractor.make(body: body, terms: ["xyz"], maxLength: 50)
        XCTAssertTrue(s.highlights.isEmpty)
        XCTAssertTrue(s.text.hasSuffix("…"), "kırpıldığında sona … eklenmeli")
        XCTAssertTrue(body.hasPrefix(String(s.text.dropLast())), "baştan kırpılmalı")
        XCTAssertLessThanOrEqual(s.text.count, 51)             // maxLen + "…"
    }

    func testKisaGovdeKirpilmaz() {
        let body = "kısa bir önizleme"
        let s = SnippetExtractor.make(body: body, terms: ["bulunmayan"])
        XCTAssertEqual(s.text, body)
        XCTAssertFalse(s.text.hasSuffix("…"))
        XCTAssertTrue(s.highlights.isEmpty)
    }

    func testTerimBasta() {
        let body = "Fatura ödemesi için son tarih yaklaşıyor lütfen dikkat edin."
        let s = SnippetExtractor.make(body: body, terms: ["fatura"])
        XCTAssertEqual(s.highlights.count, 1)
        XCTAssertEqual(slice(s, s.highlights[0]).lowercased(with: Locale(identifier: "tr_TR")), "fatura")
    }

    func testTerimOrtada() {
        let body = "Merhaba, ekteki sözleşme belgesini incelemeniz rica olunur teşekkürler."
        let s = SnippetExtractor.make(body: body, terms: ["sözleşme"])
        XCTAssertEqual(s.highlights.count, 1)
        XCTAssertEqual(slice(s, s.highlights[0]), "sözleşme")
    }

    func testTerimSonda() {
        let body = "Lütfen bu konuyu en kısa sürede bana iletin, beklediğim önemli rapor."
        let s = SnippetExtractor.make(body: body, terms: ["rapor"])
        XCTAssertEqual(s.highlights.count, 1)
        XCTAssertEqual(slice(s, s.highlights[0]), "rapor")
    }

    func testBuyukKucukHarfDuyarsizTurkce() {
        // Türkçe İ/i eşlemesi: "İstanbul" gövdesi "istanbul" terimiyle eşleşmeli.
        let body = "Toplantı İstanbul ofisinde yapılacak."
        let s = SnippetExtractor.make(body: body, terms: ["istanbul"])
        XCTAssertEqual(s.highlights.count, 1)
        XCTAssertEqual(slice(s, s.highlights[0]), "İstanbul")
    }

    func testBuyukTerimKucukGovde() {
        let body = "yıllık istanbul raporu hazır"
        let s = SnippetExtractor.make(body: body, terms: ["İSTANBUL"])
        XCTAssertEqual(s.highlights.count, 1)
        XCTAssertEqual(slice(s, s.highlights[0]), "istanbul")
    }

    func testCokTerimEnYogunPencere() {
        // Sol blokta yalnız "alfa"; sağ blokta "alfa", "beta", "gama" yoğun.
        let solBlok = "alfa " + String(repeating: "dolgu ", count: 40)
        let sagBlok = "alfa beta gama bitiş"
        let body = solBlok + sagBlok
        let s = SnippetExtractor.make(body: body, terms: ["alfa", "beta", "gama"], maxLength: 60)
        // En yoğun pencere üç farklı terimi de içermeli.
        let kelimeler = Set(s.highlights.map { slice(s, $0).lowercased(with: Locale(identifier: "tr_TR")) })
        XCTAssertEqual(kelimeler, ["alfa", "beta", "gama"])
    }

    func testTumVurgularGercektenTerim() {
        let body = "Proje bütçesi onaylandı; bütçe planı ve proje takvimi güncellendi."
        let terms = ["proje", "bütçe"]
        let s = SnippetExtractor.make(body: body, terms: terms, maxLength: 200)
        XCTAssertFalse(s.highlights.isEmpty)
        let locale = Locale(identifier: "tr_TR")
        for h in s.highlights {
            let parca = slice(s, h).lowercased(with: locale)
            // Her vurgu, verilen terimlerden birini (alt dizge olarak) kapsamalı.
            XCTAssertTrue(terms.contains { parca == $0 }, "vurgu '\(parca)' bir terim değil")
        }
    }

    func testTekrarliTerimCokluVurgu() {
        let body = "fatura geldi, fatura ödendi, fatura arşivlendi."
        let s = SnippetExtractor.make(body: body, terms: ["fatura"], maxLength: 200)
        XCTAssertEqual(s.highlights.count, 3)
        for h in s.highlights {
            XCTAssertEqual(slice(s, h), "fatura")
        }
    }

    func testMaxLengthSiniri() {
        let body = String(repeating: "kelime ", count: 200)
        let s = SnippetExtractor.make(body: body, terms: ["yok"], maxLength: 80)
        // Metin maxLength + olası tek "…" sınırını aşmamalı.
        XCTAssertLessThanOrEqual(s.text.count, 81)
    }

    func testKelimeSinirindaKirpma() {
        // Pencere bir kelimenin ortasından geçmemeli (kenarlarda yarım kelime kalmasın).
        let body = "alfa beta gama delta epsilon zeta eta teta iyota kappa lambda mu nu ksi omikron pi ro sigma tau"
        let s = SnippetExtractor.make(body: body, terms: ["epsilon"], maxLength: 40)
        let govde = s.text.replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: .whitespaces)
        // Gövde gerçek kelimelerden oluşmalı; orijinal metinde tam kelime olarak yer almalı.
        let bodyKelimeler = Set(body.split(separator: " ").map(String.init))
        for kelime in govde.split(separator: " ").map(String.init) {
            XCTAssertTrue(bodyKelimeler.contains(kelime), "yarım kelime kırpıldı: '\(kelime)'")
        }
    }

    func testVurgulariSiraliVeMetinIcinde() {
        let body = "gama sonra beta sonra alfa sonra delta sonra beta"
        let s = SnippetExtractor.make(body: body, terms: ["alfa", "beta", "gama"], maxLength: 200)
        // Sıralı olmalı ve her biri metin sınırları içinde kalmalı.
        var onceki = -1
        let toplam = s.text.count
        for h in s.highlights {
            XCTAssertGreaterThanOrEqual(h.start, onceki)
            XCTAssertLessThanOrEqual(h.start + h.length, toplam)
            onceki = h.start
        }
    }

    func testEslesmeYoksaVurguBos() {
        let body = "Bu metinde aranan terim hiç geçmiyor."
        let s = SnippetExtractor.make(body: body, terms: ["bulunmaz"])
        XCTAssertTrue(s.highlights.isEmpty)
        XCTAssertEqual(s.text, body)
    }
}
