import XCTest
@testable import TrovaCore

final class FacetsTests: XCTestCase {

    /// Sadece gönderen alanları anlamlı bir SearchHit kurar (facet mantığı yalnız bunları okur).
    private func hit(_ id: String, name: String?, addr: String?) -> SearchHit {
        SearchHit(id: id, subject: "K\(id)", fromName: name, fromAddress: addr,
                  mailbox: "INBOX", date: nil, snippet: "x", score: 1.0)
    }

    // MARK: - senders

    func testSayimVeAzalanSira() {
        let hits = [
            hit("1", name: "Ali", addr: "ali@x.com"),
            hit("2", name: "Ali", addr: "ali@x.com"),
            hit("3", name: "Ali", addr: "ali@x.com"),
            hit("4", name: "Veli", addr: "veli@x.com"),
            hit("5", name: "Veli", addr: "veli@x.com"),
            hit("6", name: "Can", addr: "can@x.com"),
        ]
        let facets = Facets.senders(hits)
        XCTAssertEqual(facets.map(\.value), ["Ali", "Veli", "Can"])
        XCTAssertEqual(facets.map(\.count), [3, 2, 1])
    }

    func testEsitSayidaAlfabetikSiraBozucu() {
        let hits = [
            hit("1", name: "Veli", addr: "veli@x.com"),
            hit("2", name: "Ahmet", addr: "ahmet@x.com"),
            hit("3", name: "Can", addr: "can@x.com"),
        ]
        // Hepsi 1 hit → alfabetik: Ahmet, Can, Veli.
        XCTAssertEqual(Facets.senders(hits).map(\.value), ["Ahmet", "Can", "Veli"])
    }

    func testLimitUygulanir() {
        let hits = (1...10).map { hit("\($0)", name: "K\($0)", addr: "k\($0)@x.com") }
        XCTAssertEqual(Facets.senders(hits, limit: 4).count, 4)
        XCTAssertEqual(Facets.senders(hits).count, 6, "varsayılan limit 6")
    }

    func testAdYoksaAdresKullanilir() {
        let hits = [
            hit("1", name: nil, addr: "noreply@x.com"),
            hit("2", name: "", addr: "noreply@x.com"),
        ]
        let facets = Facets.senders(hits)
        XCTAssertEqual(facets.count, 1)
        XCTAssertEqual(facets[0].value, "noreply@x.com")
        XCTAssertEqual(facets[0].count, 2)
    }

    func testBuyukKucukHarfDuyarsizGruplama() {
        let hits = [
            hit("1", name: "Ali", addr: "ali@x.com"),
            hit("2", name: "ALİ", addr: "ali@x.com"),   // Türkçe büyük İ → aynı grup
            hit("3", name: "ali", addr: "ali@x.com"),
        ]
        let facets = Facets.senders(hits)
        XCTAssertEqual(facets.count, 1, "harf büyüklüğü farkı tek grupta birleşmeli")
        XCTAssertEqual(facets[0].count, 3)
        XCTAssertEqual(facets[0].value, "Ali", "temsilci ilk görülen yazım olmalı")
    }

    func testBosGonderenAtlanir() {
        let hits = [
            hit("1", name: "Ali", addr: "ali@x.com"),
            hit("2", name: nil, addr: nil),
            hit("3", name: "  ", addr: "   "),   // yalnız boşluk → anonim
        ]
        let facets = Facets.senders(hits)
        XCTAssertEqual(facets.count, 1)
        XCTAssertEqual(facets[0].value, "Ali")
        XCTAssertEqual(facets[0].count, 1)
    }

    func testBosListeBosDoner() {
        XCTAssertTrue(Facets.senders([]).isEmpty)
    }

    // MARK: - filter

    func testFiltreYalnizOGondereniDonerVeBuyukKucukHarfDuyarsiz() {
        let hits = [
            hit("1", name: "Ali", addr: "ali@x.com"),
            hit("2", name: "Veli", addr: "veli@x.com"),
            hit("3", name: "ali", addr: "ali@x.com"),   // farklı yazım, aynı kişi
        ]
        // Türkçe büyük "ALİ" küçük harfe "ali" iner → "Ali"/"ali" hit'leriyle eşleşir.
        let filtered = Facets.filter(hits, bySender: "ALİ")
        XCTAssertEqual(filtered.map(\.id), ["1", "3"])
    }

    func testFiltreEslesmeYoksaBosDoner() {
        let hits = [hit("1", name: "Ali", addr: "ali@x.com")]
        XCTAssertTrue(Facets.filter(hits, bySender: "Bilinmeyen").isEmpty)
    }
}
