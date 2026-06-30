import XCTest
@testable import TrovaCore

final class ThreadGroupingTests: XCTestCase {

    /// Verilen konu, tarih (saniye ofseti) ve okundu durumuyla bir SearchHit üretir.
    /// `offset` nil ise tarihsiz (date == nil) sonuç döner.
    private func hit(_ id: String, subject: String?, _ offset: TimeInterval?,
                     isRead: Bool? = nil) -> SearchHit {
        let date = offset.map { Date(timeIntervalSince1970: $0) }
        return SearchHit(id: id, subject: subject, fromName: nil, fromAddress: nil,
                         mailbox: "INBOX", date: date, snippet: "", score: 1.0, isRead: isRead)
    }

    // MARK: - normalizeSubject

    /// Tek önek: baştaki "Re:" soyulur.
    func testSinglePrefix() {
        XCTAssertEqual(ThreadGrouping.normalizeSubject("Re: Merhaba"), "Merhaba")
    }

    /// Çok önek peş peşe: hepsi soyulur, gövde kalır.
    func testMultiplePrefixes() {
        XCTAssertEqual(ThreadGrouping.normalizeSubject("Re: Fwd: Ynt: konu"), "konu")
    }

    /// Türkçe "Ynt:" (yanıt) öneki soyulur.
    func testTurkishYntPrefix() {
        XCTAssertEqual(ThreadGrouping.normalizeSubject("Ynt: Toplantı notları"), "Toplantı notları")
    }

    /// Türkçe "İlt:" ve "Ilt:" (ilet) — iki ayrı büyük-harf biçimi de soyulur.
    func testTurkishIltPrefix() {
        XCTAssertEqual(ThreadGrouping.normalizeSubject("İlt: Rapor"), "Rapor")
        XCTAssertEqual(ThreadGrouping.normalizeSubject("Ilt: Rapor"), "Rapor")
    }

    /// Köşeli/parantezli sayaçlı önekler ("Re[2]:", "RE(3):") soyulur.
    func testBracketedAndParenCounter() {
        XCTAssertEqual(ThreadGrouping.normalizeSubject("Re[2]: Bütçe"), "Bütçe")
        XCTAssertEqual(ThreadGrouping.normalizeSubject("RE(3): Bütçe"), "Bütçe")
    }

    /// Karışık büyük/küçük harf ve farklı önekler: "RE: fwd: Selam" → "Selam".
    func testMixedCasePrefixes() {
        XCTAssertEqual(ThreadGrouping.normalizeSubject("RE: fwd: Selam"), "Selam")
    }

    /// Boş konu → boş string.
    func testEmptySubject() {
        XCTAssertEqual(ThreadGrouping.normalizeSubject(""), "")
        XCTAssertEqual(ThreadGrouping.normalizeSubject("   "), "")
    }

    /// Yalnız öneklerden ibaret konu → boş string.
    func testOnlyPrefixes() {
        XCTAssertEqual(ThreadGrouping.normalizeSubject("Re: Fwd:"), "")
        XCTAssertEqual(ThreadGrouping.normalizeSubject("Re: Re: "), "")
    }

    /// Baş/son boşluk kırpılır, iç boşluk korunur.
    func testLeadingTrailingWhitespace() {
        XCTAssertEqual(ThreadGrouping.normalizeSubject("   Re:   Proje planı   "), "Proje planı")
    }

    /// Tanınmayan "Kelime:" öneki SOYULMAZ; "Cevap:" (tanınan) soyulur.
    func testNonPrefixNotStrippedButCevapIs() {
        XCTAssertEqual(ThreadGrouping.normalizeSubject("Reklam: kampanya"), "Reklam: kampanya")
        XCTAssertEqual(ThreadGrouping.normalizeSubject("Cevap: önemli"), "önemli")
    }

    /// Anahtar üretimi: önek + boşluk + büyük/küçük harf duyarsız (Türkçe İ).
    func testGroupKeyNormalization() {
        XCTAssertEqual(ThreadGrouping.groupKey(for: "Re:  Konu  Test"),
                       ThreadGrouping.groupKey(for: "konu test"))
        // Türkçe İ: "İLAN" küçük harfte "ilan" olur → "ilan" ile eşleşir.
        XCTAssertEqual(ThreadGrouping.groupKey(for: "İLAN duyuru"),
                       ThreadGrouping.groupKey(for: "ilan duyuru"))
        // Boş/yalnız önek → emptyKey.
        XCTAssertEqual(ThreadGrouping.groupKey(for: "Re: Fwd:"), ThreadGrouping.emptyKey)
    }

    // MARK: - group

    /// Aynı konunun farklı önekli kopyaları tek grupta toplanır.
    func testSameSubjectDifferentPrefixesGroupTogether() {
        let hits = [
            hit("a", subject: "Proje", 100),
            hit("b", subject: "Re: Proje", 200),
            hit("c", subject: "Ynt: Proje", 300),
        ]
        let groups = ThreadGrouping.group(hits)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 3)
        XCTAssertEqual(groups[0].key, "proje")
    }

    /// Üyeler grup içinde en yeniden eskiye sıralanır; representativeSubject en yeninin konusu.
    func testMembersNewestToOldest() {
        let hits = [
            hit("a", subject: "Proje", 100),
            hit("c", subject: "Ynt: Proje", 300),
            hit("b", subject: "Re: Proje", 200),
        ]
        let groups = ThreadGrouping.group(hits)
        XCTAssertEqual(groups[0].members.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(groups[0].representativeSubject, "Ynt: Proje")
        XCTAssertEqual(groups[0].latestDate, Date(timeIntervalSince1970: 300))
    }

    /// Gruplar latestDate'e göre azalan sıralanır (en yeni konuşma üstte).
    func testGroupsSortedByLatestDateDescending() {
        let hits = [
            hit("a", subject: "Eski konu", 100),
            hit("b", subject: "Yeni konu", 500),
            hit("c", subject: "Orta konu", 300),
        ]
        let groups = ThreadGrouping.group(hits)
        XCTAssertEqual(groups.map(\.key), ["yeni konu", "orta konu", "eski konu"])
    }

    /// unreadCount: isRead == false sayılır, nil/true sayılmaz.
    func testUnreadCount() {
        let hits = [
            hit("a", subject: "Konu", 100, isRead: false),
            hit("b", subject: "Re: Konu", 200, isRead: true),
            hit("c", subject: "Ynt: Konu", 300, isRead: false),
            hit("d", subject: "Fwd: Konu", 400, isRead: nil),
        ]
        let groups = ThreadGrouping.group(hits)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].unreadCount, 2)
    }

    /// Tek üyeli grup (singleton) count == 1 ile döner ve gösterimi orijinal konudur.
    func testSingletonGroup() {
        let hits = [
            hit("a", subject: "Tekil konu", 100),
            hit("b", subject: "Başka konu", 200),
        ]
        let groups = ThreadGrouping.group(hits)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.count == 1 })
        XCTAssertEqual(groups[0].representativeSubject, "Başka konu")  // en yeni üstte
    }

    /// Tarihsiz (nil) gruplar en sona; grup içinde tarihsiz üyeler en sona gider.
    func testNilDatesGoLast() {
        let hits = [
            hit("a", subject: "Tarihli", 200),
            hit("b", subject: "Tarihsiz konu", nil),
            hit("c", subject: "Re: Tarihli", nil),     // gruplanır: "tarihli"
            hit("d", subject: "Re: Tarihli", 100),
        ]
        let groups = ThreadGrouping.group(hits)
        // İki grup: "tarihli" (a,c,d) latestDate=200; "tarihsiz konu" (b) latestDate=nil → sona.
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].key, "tarihli")
        XCTAssertEqual(groups[1].key, "tarihsiz konu")
        XCTAssertNil(groups[1].latestDate)
        // Grup içi: tarihliler önce (a=200, d=100), tarihsiz (c) sona.
        XCTAssertEqual(groups[0].members.map(\.id), ["a", "d", "c"])
    }

    /// Boş/yalnız-önek konular tek "(konu yok)" grubunda toplanır.
    func testEmptySubjectsGroupUnderEmptyKey() {
        let hits = [
            hit("a", subject: "Re: Fwd:", 100),
            hit("b", subject: "", 200),
            hit("c", subject: nil, 300),
        ]
        let groups = ThreadGrouping.group(hits)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].key, ThreadGrouping.emptyKey)
        XCTAssertEqual(groups[0].count, 3)
    }

    /// Boş girdi → boş grup listesi.
    func testEmptyInput() {
        XCTAssertTrue(ThreadGrouping.group([]).isEmpty)
    }
}
