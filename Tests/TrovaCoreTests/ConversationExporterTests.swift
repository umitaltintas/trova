import XCTest
@testable import TrovaCore

final class ConversationExporterTests: XCTestCase {

    private let bom = "\u{FEFF}"

    // Deterministik mutlak tarih için sabit UTC takvimi (yerel saat diliminden bağımsız).
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 9, _ mn: Int = 0) -> Date {
        cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                      year: y, month: mo, day: d, hour: h, minute: mn))!
    }

    private func hit(_ id: String, subject: String? = "Konu", name: String? = nil,
                     addr: String? = nil, date: Date? = nil, snippet: String = "özet") -> SearchHit {
        SearchHit(id: id, subject: subject, fromName: name, fromAddress: addr,
                  mailbox: "INBOX", date: date, snippet: snippet, score: 1)
    }

    // MARK: - Markdown

    func testEmptyListStillHasTitleAndCount() {
        let md = ConversationExporter.markdown(subject: nil, messages: [], calendar: cal)
        XCTAssertTrue(md.hasPrefix("# (konu yok)\n"))
        XCTAssertTrue(md.contains("_0 mesaj_"))
        XCTAssertFalse(md.contains("##"))   // hiç mesaj bloğu yok
    }

    func testSingleMessageHeaderMetaAndBody() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", subject: "Fatura", name: "Ali", addr: "ali@x.com", date: date(2024, 3, 5, 14, 30)),
             "Fatura ektedir."),
        ]
        let md = ConversationExporter.markdown(subject: "Fatura", messages: msgs, calendar: cal)
        XCTAssertTrue(md.hasPrefix("# Fatura\n"))
        XCTAssertTrue(md.contains("_1 mesaj · 5 Mart 2024 14:30_"))   // tek tarih → aralık değil
        XCTAssertTrue(md.contains("## Ali — 5 Mart 2024 14:30"))
        XCTAssertTrue(md.contains("Fatura ektedir."))
    }

    func testMultipleMessagesOrderPreservedWithSeparators() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", name: "Ali", date: date(2024, 3, 5, 10, 0)), "Birinci"),
            (hit("2", name: "Veli", date: date(2024, 3, 6, 11, 0)), "İkinci"),
            (hit("3", name: "Can", date: date(2024, 3, 7, 12, 0)), "Üçüncü"),
        ]
        let md = ConversationExporter.markdown(subject: "Konu", messages: msgs, calendar: cal)
        // Meta aralığı en eski – en yeni.
        XCTAssertTrue(md.contains("_3 mesaj · 5 Mart 2024 10:00 – 7 Mart 2024 12:00_"))
        // Girdi sırası korunur.
        guard let iAli = md.range(of: "Birinci"),
              let iVeli = md.range(of: "İkinci"),
              let iCan = md.range(of: "Üçüncü") else { return XCTFail("gövdeler bulunamadı") }
        XCTAssertTrue(iAli.lowerBound < iVeli.lowerBound)
        XCTAssertTrue(iVeli.lowerBound < iCan.lowerBound)
        // Mesajlar arası ayraç (3 mesaj → 2 ayraç).
        XCTAssertEqual(md.components(separatedBy: "\n---\n").count - 1, 2)
    }

    func testNilSenderAndNilDatePlaceholders() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", name: nil, addr: nil, date: nil), "gövde"),
        ]
        let md = ConversationExporter.markdown(subject: "Konu", messages: msgs, calendar: cal)
        XCTAssertTrue(md.contains("## — — tarih yok"))   // gönderen "—", tarih "tarih yok"
        XCTAssertTrue(md.contains("_1 mesaj_"))          // tarihsiz → meta'da tarih yok
        XCTAssertFalse(md.contains(" · "))               // tarih aralığı eklenmez
    }

    func testSenderFallsBackToAddress() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", name: nil, addr: "kimse@x.com", date: date(2024, 1, 2)), "gövde"),
        ]
        let md = ConversationExporter.markdown(subject: "Konu", messages: msgs, calendar: cal)
        XCTAssertTrue(md.contains("## kimse@x.com — 2 Ocak 2024 09:00"))
    }

    func testBodyFallsBackToSnippetThenPlaceholder() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", name: "Ali", snippet: "özet-metni"), nil),           // gövde nil → snippet
            (hit("2", name: "Veli", snippet: "diğer-özet"), "   "),        // boş gövde → snippet
            (hit("3", name: "Can", snippet: ""), nil),                     // ikisi de boş → placeholder
        ]
        let md = ConversationExporter.markdown(subject: "Konu", messages: msgs, calendar: cal)
        XCTAssertTrue(md.contains("özet-metni"))
        XCTAssertTrue(md.contains("diğer-özet"))
        XCTAssertTrue(md.contains("_(gövde yok)_"))
    }

    func testNilSubjectUsesPlaceholder() {
        let md = ConversationExporter.markdown(subject: "  ", messages: [
            (hit("1", name: "Ali", date: date(2024, 5, 1)), "x"),
        ], calendar: cal)
        XCTAssertTrue(md.hasPrefix("# (konu yok)\n"))
    }

    // MARK: - CSV

    func testCsvHeaderAndBomAndColumns() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", subject: "Fatura", name: "Ali", addr: "ali@x.com",
                 date: date(2024, 3, 5, 14, 30), snippet: "kısa özet"), "tam gövde"),
        ]
        let csv = ConversationExporter.csv(messages: msgs, calendar: cal)
        XCTAssertTrue(csv.hasPrefix("\(bom)Tarih,Gönderen,Adres,Konu,Özet\r\n"))
        // Özet sütunu snippet'ten gelir (tam gövde değil).
        XCTAssertTrue(csv.contains("5 Mart 2024 14:30,Ali,ali@x.com,Fatura,kısa özet\r\n"))
        XCTAssertFalse(csv.contains("tam gövde"))
    }

    func testCsvEmptyDateAndFields() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", subject: nil, name: nil, addr: nil, date: nil, snippet: "yalnız özet"), nil),
        ]
        let csv = ConversationExporter.csv(messages: msgs, calendar: cal)
        // Tarih/Gönderen/Adres/Konu boş; yalnız özet dolu.
        XCTAssertTrue(csv.contains(",,,,yalnız özet\r\n"))
    }

    func testCsvEscapesCommaAndNewline() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", subject: "Rapor, ek", name: "Ali", addr: "a@x.com",
                 date: date(2024, 3, 5), snippet: "üst\nalt"), nil),
        ]
        let csv = ConversationExporter.csv(messages: msgs, calendar: cal)
        XCTAssertTrue(csv.contains("\"Rapor, ek\""))   // virgüllü konu tırnaklanır
        XCTAssertTrue(csv.contains("\"üst\nalt\""))    // satır sonlu özet tırnaklanır ve korunur
    }

    func testCsvEmptyMessagesOnlyHeader() {
        let csv = ConversationExporter.csv(messages: [], calendar: cal)
        XCTAssertEqual(csv, "\(bom)Tarih,Gönderen,Adres,Konu,Özet\r\n")
    }

    // MARK: - Kişi (toplu, konuşmalara gruplu) Markdown

    func testPersonEmptyStillHasHeaderAndZeroCount() {
        let md = ConversationExporter.personMarkdown(
            personName: "Ali Veli", personAddress: "ali@x.com", messages: [], calendar: cal)
        // Ad varsa başlık ad; adres alt satırda; özet "_0 mesaj_"; hiç konuşma başlığı yok.
        XCTAssertTrue(md.hasPrefix("# Ali Veli\n\n_ali@x.com_\n"))
        XCTAssertTrue(md.contains("_0 mesaj_"))
        XCTAssertFalse(md.contains("## "))
    }

    func testPersonHeaderFallsBackToAddressWithoutSubtitle() {
        let md = ConversationExporter.personMarkdown(
            personName: nil, personAddress: "ali@x.com", messages: [], calendar: cal)
        XCTAssertTrue(md.hasPrefix("# ali@x.com\n"))
        // Ad yoksa adres yalnız başlıkta; alt satırda "_adres_" olarak tekrar edilmez.
        XCTAssertFalse(md.contains("_ali@x.com_"))
    }

    func testPersonSingleMessageStructure() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", subject: "Fatura", name: "Ali", addr: "ali@x.com", date: date(2024, 3, 5, 14, 30)),
             "Fatura ektedir."),
        ]
        let md = ConversationExporter.personMarkdown(
            personName: "Ali", personAddress: "ali@x.com", messages: msgs, calendar: cal)
        XCTAssertTrue(md.contains("_1 mesaj · 5 Mart 2024 14:30_"))   // üst özet
        XCTAssertTrue(md.contains("## Fatura"))                        // konuşma başlığı
        XCTAssertTrue(md.contains("### Ali — 5 Mart 2024 14:30"))      // mesaj başlığı (### düzeyi)
        XCTAssertTrue(md.contains("Fatura ektedir."))
    }

    func testPersonGroupsMessagesByThreadSubject() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", subject: "Proje planı", name: "Ali", date: date(2024, 3, 1)), "ilk"),
            (hit("2", subject: "Fatura", name: "Ali", date: date(2024, 3, 3)), "fatura"),
            (hit("3", subject: "Re: Proje planı", name: "Ali", date: date(2024, 3, 5)), "yanıt"),
        ]
        let md = ConversationExporter.personMarkdown(
            personName: "Ali", personAddress: "ali@x.com", messages: msgs, calendar: cal)
        // "Re:" öneki aynı gruba düşer; temsilci konu = grubun en YENİ üyesinin orijinal konusu.
        XCTAssertTrue(md.contains("## Re: Proje planı"))
        XCTAssertTrue(md.contains("## Fatura"))
        // Tam iki konuşma başlığı (mesaj "### " başlıkları "\n## " ile eşleşmez).
        XCTAssertEqual(md.components(separatedBy: "\n## ").count - 1, 2)
        // Proje grubu içinde kronolojik: "ilk" (1 Mart) "yanıt"tan (5 Mart) önce gelir.
        guard let iIlk = md.range(of: "ilk"), let iYanit = md.range(of: "yanıt") else {
            return XCTFail("gövdeler bulunamadı")
        }
        XCTAssertTrue(iIlk.lowerBound < iYanit.lowerBound)
        // Konuşma başına mesaj sayısı satırı.
        XCTAssertTrue(md.contains("_2 mesaj_"))   // Proje grubu (2 üye)
        XCTAssertTrue(md.contains("_1 mesaj_"))   // Fatura grubu (1 üye)
    }

    func testPersonDateRangeSpansAllMessages() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", subject: "A", name: "Ali", date: date(2024, 3, 5, 10, 0)), "x"),
            (hit("2", subject: "B", name: "Ali", date: date(2024, 3, 7, 12, 0)), "y"),
        ]
        let md = ConversationExporter.personMarkdown(
            personName: "Ali", personAddress: "ali@x.com", messages: msgs, calendar: cal)
        XCTAssertTrue(md.contains("_2 mesaj · 5 Mart 2024 10:00 – 7 Mart 2024 12:00_"))
    }

    func testPersonTruncationNoteWhenTotalExceedsExported() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", subject: "Konu", name: "Ali", date: date(2024, 1, 1)), "x"),
            (hit("2", subject: "Konu", name: "Ali", date: date(2024, 1, 2)), "y"),
        ]
        let md = ConversationExporter.personMarkdown(
            personName: "Ali", personAddress: "ali@x.com", messages: msgs,
            truncatedTotal: 10, calendar: cal)
        XCTAssertTrue(md.contains("Toplam 10 mesajın en yeni 2 tanesi dışa aktarıldı."))
    }

    func testPersonNoTruncationNoteWhenTotalMatches() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", subject: "Konu", name: "Ali", date: date(2024, 1, 1)), "x"),
        ]
        let md = ConversationExporter.personMarkdown(
            personName: "Ali", personAddress: "ali@x.com", messages: msgs,
            truncatedTotal: 1, calendar: cal)
        XCTAssertFalse(md.contains("Toplam"))
    }

    func testPersonBodyFallsBackToSnippet() {
        let msgs: [ConversationExporter.Message] = [
            (hit("1", subject: "Konu", name: "Ali", date: date(2024, 1, 1), snippet: "özet-metni"), nil),
        ]
        let md = ConversationExporter.personMarkdown(
            personName: "Ali", personAddress: "ali@x.com", messages: msgs, calendar: cal)
        XCTAssertTrue(md.contains("### Ali — 1 Ocak 2024 09:00"))
        XCTAssertTrue(md.contains("özet-metni"))
    }
}
