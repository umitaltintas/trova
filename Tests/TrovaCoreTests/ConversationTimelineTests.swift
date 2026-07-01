import XCTest
@testable import TrovaCore

final class ConversationTimelineTests: XCTestCase {

    /// Verilen kimlik, RFC822 messageID ve tarih (saniye ofseti) ile bir SearchHit üretir.
    /// `offset` nil ise tarihsiz (date == nil) sonuç döner.
    private func hit(_ id: String, messageID: String? = nil, _ offset: TimeInterval?) -> SearchHit {
        let date = offset.map { Date(timeIntervalSince1970: $0) }
        return SearchHit(id: id, messageID: messageID, subject: "konu", fromName: nil,
                         fromAddress: nil, mailbox: "INBOX", date: date, snippet: "", score: 0)
    }

    // MARK: - Sınır durumlar

    /// Boş liste → boş liste.
    func testEmpty() {
        XCTAssertTrue(ConversationTimeline.timeline([]).isEmpty)
    }

    /// Tek eleman aynen korunur.
    func testSingle() {
        let result = ConversationTimeline.timeline([hit("a", 100)])
        XCTAssertEqual(result.map(\.id), ["a"])
    }

    // MARK: - Tekilleştirme (messageID)

    /// Aynı messageID'li iki kopyadan yalnız İLK görülen kalır (deterministik).
    func testDedupKeepsFirstSeen() {
        let result = ConversationTimeline.timeline([
            hit("first", messageID: "<m1@x>", 100),
            hit("second", messageID: "<m1@x>", 100),
        ])
        XCTAssertEqual(result.map(\.id), ["first"])
    }

    /// Tekilleştirme girdi sırasına bakar, tarihe değil: sonraki kopya daha ESKİ olsa bile
    /// ilk görülen tutulur.
    func testDedupPrefersInputOrderNotDate() {
        let result = ConversationTimeline.timeline([
            hit("first", messageID: "<m1@x>", 500),   // ilk görülen (daha yeni)
            hit("second", messageID: "<m1@x>", 100),  // daha eski kopya → atılır
        ])
        XCTAssertEqual(result.map(\.id), ["first"])
    }

    /// messageID'si nil olanlar anahtarsızdır → hiçbiri elenmez.
    func testNilMessageIDsNotDeduped() {
        let result = ConversationTimeline.timeline([
            hit("a", messageID: nil, 100),
            hit("b", messageID: nil, 200),
        ])
        XCTAssertEqual(Set(result.map(\.id)), ["a", "b"])
    }

    /// messageID'si boş ("" veya yalnız boşluk) olanlar anahtarsızdır → hiçbiri elenmez.
    func testEmptyMessageIDsNotDeduped() {
        let result = ConversationTimeline.timeline([
            hit("a", messageID: "", 100),
            hit("b", messageID: "   ", 200),
        ])
        XCTAssertEqual(Set(result.map(\.id)), ["a", "b"])
    }

    /// Farklı messageID'ler ayrı tutulur (yanlışlıkla elenmez).
    func testDistinctMessageIDsKept() {
        let result = ConversationTimeline.timeline([
            hit("a", messageID: "<m1@x>", 100),
            hit("b", messageID: "<m2@x>", 200),
        ])
        XCTAssertEqual(result.map(\.id), ["a", "b"])
    }

    // MARK: - Kronolojik sıra

    /// Sonuç en eskiden en yeniye (artan) sıralanır.
    func testAscendingDateOrder() {
        let result = ConversationTimeline.timeline([
            hit("yeni", 300),
            hit("eski", 100),
            hit("orta", 200),
        ])
        XCTAssertEqual(result.map(\.id), ["eski", "orta", "yeni"])
    }

    /// Tarihi nil olan mailler en sona gider (tarihliler kronolojik başta).
    func testNilDatesGoLast() {
        let result = ConversationTimeline.timeline([
            hit("tarihsiz", nil),
            hit("yeni", 200),
            hit("eski", 100),
        ])
        XCTAssertEqual(result.map(\.id), ["eski", "yeni", "tarihsiz"])
    }

    /// Eşit tarihte girdi sırası korunur (kararlı sıralama).
    func testStableEqualDates() {
        let result = ConversationTimeline.timeline([
            hit("ilk", 100),
            hit("ikinci", 100),
            hit("ucuncu", 100),
        ])
        XCTAssertEqual(result.map(\.id), ["ilk", "ikinci", "ucuncu"])
    }

    /// Birden çok tarihsiz mail kendi aralarında girdi sırasını korur (en sonda, kararlı).
    func testMultipleNilDatesStable() {
        let result = ConversationTimeline.timeline([
            hit("t2", nil),
            hit("tarihli", 100),
            hit("t1", nil),
        ])
        XCTAssertEqual(result.map(\.id), ["tarihli", "t2", "t1"])
    }

    // MARK: - Karışık senaryo

    /// Tekilleştirme + kronolojik sıra + tarihsizler sonda birlikte doğru çalışır.
    func testMixedScenario() {
        let result = ConversationTimeline.timeline([
            hit("dup-yeni", messageID: "<m@x>", 500),   // ilk görülen → kalır
            hit("eski", 100),
            hit("dup-eski", messageID: "<m@x>", 200),   // aynı messageID → atılır
            hit("tarihsiz", nil),
            hit("orta", 300),
        ])
        // Kalanlar: dup-yeni(500), eski(100), tarihsiz(nil), orta(300)
        // Sıra: eski(100), orta(300), dup-yeni(500), tarihsiz(nil)
        XCTAssertEqual(result.map(\.id), ["eski", "orta", "dup-yeni", "tarihsiz"])
    }
}
