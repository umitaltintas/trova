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

    // MARK: - Açık alan operatörleri (Iter 65): kimden: / kutu: / ek: (+ İngilizce eş anlamlılar)

    func testKimdenOperatorTurkish() {
        let r = SearchOperatorParser.parse("kimden:ali fatura")
        XCTAssertEqual(r.fromContains, "ali")
        XCTAssertEqual(r.cleaned, "fatura")
    }

    func testKutuOperatorTurkish() {
        let r = SearchOperatorParser.parse("kutu:INBOX toplantı")
        XCTAssertEqual(r.mailboxContains, "INBOX")
        XCTAssertNil(r.fromContains)
        XCTAssertEqual(r.cleaned, "toplantı")
    }

    func testMailboxOperatorEnglish() {
        let r = SearchOperatorParser.parse("mailbox:Arşiv rapor")
        XCTAssertEqual(r.mailboxContains, "Arşiv")
        XCTAssertEqual(r.cleaned, "rapor")
    }

    func testAttachmentEnglishSynonym() {
        // attachment:<tür> — ek:<tür>/has:<tür> ile aynı ek türü filtresini kurar.
        let r = SearchOperatorParser.parse("attachment:pdf sözleşme")
        XCTAssertEqual(r.attachmentKind, .pdf)
        XCTAssertFalse(r.hasAttachment)
        XCTAssertEqual(r.cleaned, "sözleşme")
    }

    func testQuotedFromValue() {
        // Tırnaklı değer boşluk içeren adı tek değer yapar; tırnaklar ayıklanır.
        let r = SearchOperatorParser.parse("kimden:\"Ali Veli\" fatura")
        XCTAssertEqual(r.fromContains, "Ali Veli")
        XCTAssertEqual(r.cleaned, "fatura")
    }

    func testQuotedMailboxValue() {
        let r = SearchOperatorParser.parse("kutu:\"Gelen Kutusu\" rapor")
        XCTAssertEqual(r.mailboxContains, "Gelen Kutusu")
        XCTAssertEqual(r.cleaned, "rapor")
    }

    func testOperatorsExtractedFromFtsText() {
        // Operatörler FTS metninden AYIKLANIR; yalnız normal terimler kalır.
        let r = SearchOperatorParser.parse("kimden:ali fatura kutu:INBOX ödeme")
        XCTAssertEqual(r.fromContains, "ali")
        XCTAssertEqual(r.mailboxContains, "INBOX")
        XCTAssertEqual(r.cleaned, "fatura ödeme")
    }

    func testAllOperatorsRemainingEmpty() {
        // Kalan-boş sorgu: yalnız operatörler → cleaned == "" (çağıran yalnız filtreyle gezinir).
        let r = SearchOperatorParser.parse("kimden:ali kutu:INBOX ek:pdf")
        XCTAssertEqual(r.fromContains, "ali")
        XCTAssertEqual(r.mailboxContains, "INBOX")
        XCTAssertEqual(r.attachmentKind, .pdf)
        XCTAssertEqual(r.cleaned, "")
    }

    func testUnknownAttachmentKindIgnored() {
        // Bilinmeyen ek türü → operatör yok sayılır (hata yok), belirteç aramada kalır.
        let r = SearchOperatorParser.parse("ek:uçak fatura")
        XCTAssertNil(r.attachmentKind)
        XCTAssertFalse(r.hasAttachment)
        XCTAssertEqual(r.cleaned, "ek:uçak fatura")
    }

    func testOperatorNameCaseInsensitive() {
        // Operatör adları büyük/küçük harf duyarsız (tr_TR: İ/i); değer harf durumu korunur.
        let r = SearchOperatorParser.parse("KİMDEN:Ali KUTU:inbox")
        XCTAssertEqual(r.fromContains, "Ali")
        XCTAssertEqual(r.mailboxContains, "inbox")
        XCTAssertEqual(r.cleaned, "")
    }

    func testExplicitOperatorOverridesEarlierValue() {
        // Açık operatör aynı alandaki çıkarımı ezer: birden çok kez verilirse SON değer kazanır.
        let r = SearchOperatorParser.parse("kimden:ali kimden:veli")
        XCTAssertEqual(r.fromContains, "veli")
    }

    func testMultipleOperatorsCombined() {
        let r = SearchOperatorParser.parse("kimden:\"Ali Veli\" kutu:Arşiv attachment:pdf teklif")
        XCTAssertEqual(r.fromContains, "Ali Veli")
        XCTAssertEqual(r.mailboxContains, "Arşiv")
        XCTAssertEqual(r.attachmentKind, .pdf)
        XCTAssertEqual(r.cleaned, "teklif")
    }

    func testQuotedPhraseWithoutOperatorPreserved() {
        // Operatör olmayan tırnaklı ifade (gelişmiş FTS söz dizimi) olduğu gibi korunur.
        let r = SearchOperatorParser.parse("\"tam ifade\" kimden:ali")
        XCTAssertEqual(r.fromContains, "ali")
        XCTAssertEqual(r.cleaned, "\"tam ifade\"")
    }
}
