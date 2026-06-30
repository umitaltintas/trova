import XCTest
@testable import TrovaCore

final class MarkdownExporterTests: XCTestCase {

    private func hit(_ id: String, subject: String?, name: String?, addr: String?,
                     mailbox: String = "INBOX", attachments: [String] = []) -> SearchHit {
        SearchHit(id: id, subject: subject, fromName: name, fromAddress: addr,
                  mailbox: mailbox, date: nil, snippet: "özet", score: 1,
                  threadKey: nil, attachments: attachments)
    }

    // MARK: - Yanıt

    func testAnswerWithCitations() {
        let cites = [
            hit("1", subject: "Fatura", name: "Ali", addr: "ali@x.com"),
            hit("2", subject: "Kira", name: nil, addr: "ev@x.com", mailbox: "Arşiv"),
        ]
        let md = MarkdownExporter.answer(question: "Faturalarım ne durumda?",
                                         answer: "İki fatura bulundu.", citations: cites)
        XCTAssertTrue(md.hasPrefix("# Faturalarım ne durumda?\n"))
        XCTAssertTrue(md.contains("İki fatura bulundu."))
        XCTAssertTrue(md.contains("## Kaynaklar"))
        XCTAssertTrue(md.contains("1. **Fatura** · Ali <ali@x.com> · `INBOX`"))
        XCTAssertTrue(md.contains("2. **Kira** · ev@x.com · `Arşiv`"))
        XCTAssertTrue(md.contains("_Trova ile dışa aktarıldı_"))
    }

    func testAnswerWithoutCitationsOmitsSection() {
        let md = MarkdownExporter.answer(question: "Selam", answer: "Merhaba", citations: [])
        XCTAssertFalse(md.contains("## Kaynaklar"))
        XCTAssertTrue(md.contains("Merhaba"))
    }

    func testEmptyQuestionGetsPlaceholder() {
        let md = MarkdownExporter.answer(question: "   ", answer: "x", citations: [])
        XCTAssertTrue(md.hasPrefix("# Soru\n"))
    }

    // MARK: - Mail

    func testEmailExport() {
        let h = hit("1", subject: "Toplantı", name: "Veli", addr: "veli@x.com",
                    mailbox: "Gelen", attachments: ["plan.pdf"])
        let md = MarkdownExporter.email(h, body: "Yarın saat 10'da toplanıyoruz.")
        XCTAssertTrue(md.hasPrefix("# Toplantı\n"))
        XCTAssertTrue(md.contains("**Gönderen:** Veli <veli@x.com>"))
        XCTAssertTrue(md.contains("**Kutu:** Gelen"))
        XCTAssertTrue(md.contains("**Ekler:** plan.pdf"))
        XCTAssertTrue(md.contains("Yarın saat 10'da toplanıyoruz."))
    }

    func testEmailFallsBackToSnippetWhenNoBody() {
        let h = hit("1", subject: nil, name: nil, addr: nil)
        let md = MarkdownExporter.email(h, body: nil)
        XCTAssertTrue(md.hasPrefix("# (konu yok)\n"))
        XCTAssertTrue(md.contains("**Gönderen:** Bilinmeyen gönderen"))
        XCTAssertTrue(md.contains("özet"))   // snippet'e düşer
    }

    // MARK: - Sohbet

    func testConversationExport() {
        let turns = [
            ExportedTurn(question: "İlk soru?", answer: "İlk yanıt.",
                         citations: [hit("1", subject: "Fatura", name: "Ali", addr: "ali@x.com")]),
            ExportedTurn(question: "Takip?", answer: "İkinci yanıt."),
        ]
        let md = MarkdownExporter.conversation(turns, title: "Test Sohbeti")
        XCTAssertTrue(md.hasPrefix("# Test Sohbeti\n"))
        XCTAssertTrue(md.contains("## 1. İlk soru?"))
        XCTAssertTrue(md.contains("İlk yanıt."))
        XCTAssertTrue(md.contains("**Kaynaklar:**"))
        XCTAssertTrue(md.contains("**Fatura**"))
        XCTAssertTrue(md.contains("## 2. Takip?"))
        XCTAssertTrue(md.contains("İkinci yanıt."))
        XCTAssertTrue(md.contains("_Trova ile dışa aktarıldı_"))
    }

    func testEmptyConversation() {
        let md = MarkdownExporter.conversation([], title: "Boş")
        XCTAssertTrue(md.contains("(boş sohbet)"))
    }

    // MARK: - Bugün brifingi (digest)

    func testDigestWithBothLists() {
        let needs = [DigestItem(from: "Ali", subject: "Fatura", ageLabel: "2g")]
        let waiting = [DigestItem(from: "Veli", subject: "Teklif", ageLabel: "5g")]
        let md = MarkdownExporter.digest(title: "Bugün — 30 Haziran",
                                         briefing: "Bugün iki konu öne çıkıyor.",
                                         needsReply: needs, waitingOn: waiting)
        XCTAssertTrue(md.hasPrefix("# Bugün — 30 Haziran\n"))
        XCTAssertTrue(md.contains("Bugün iki konu öne çıkıyor."))
        XCTAssertTrue(md.contains("## Yanıt gerekiyor"))
        XCTAssertTrue(md.contains("- **Ali** — Fatura _(2g)_"))
        XCTAssertTrue(md.contains("## Yanıt bekliyor"))
        XCTAssertTrue(md.contains("- **Veli** — Teklif _(5g)_"))
        XCTAssertTrue(md.contains("_Trova ile dışa aktarıldı_"))
    }

    func testDigestWithoutAgeLabelOmitsParens() {
        let needs = [DigestItem(from: "Ali", subject: "Fatura", ageLabel: "")]
        let md = MarkdownExporter.digest(title: "Bugün", briefing: "",
                                         needsReply: needs, waitingOn: [])
        XCTAssertTrue(md.contains("- **Ali** — Fatura\n"))
        XCTAssertFalse(md.contains("Fatura _("))
    }

    func testDigestEmptyListsStayConsistent() {
        let md = MarkdownExporter.digest(title: "Bugün", briefing: "Brifing metni.",
                                         needsReply: [], waitingOn: [])
        XCTAssertTrue(md.contains("## Yanıt gerekiyor"))
        XCTAssertTrue(md.contains("## Yanıt bekliyor"))
        XCTAssertTrue(md.contains("_(yok)_"))
    }

    func testDigestEmptyBriefingStillHasTitle() {
        let md = MarkdownExporter.digest(title: "Bugün — Test", briefing: "   ",
                                         needsReply: [], waitingOn: [])
        XCTAssertTrue(md.hasPrefix("# Bugün — Test\n"))
        XCTAssertFalse(md.contains("\n\n\n"))   // boş brifing fazladan boşluk bırakmaz
    }

    // MARK: - Mail listesi (emailList)

    func testEmailListWithItems() {
        let items = [
            ExportedListItem(from: "Ali", subject: "Fatura", dateLabel: "2g", mailbox: "INBOX"),
            ExportedListItem(from: "Veli", subject: "Teklif", dateLabel: "5g", mailbox: "Arşiv"),
        ]
        let md = MarkdownExporter.emailList(title: "Arama: fatura", items: items)
        XCTAssertTrue(md.hasPrefix("# Arama: fatura\n"))
        XCTAssertTrue(md.contains("_2 kayıt_"))
        XCTAssertTrue(md.contains("- **Ali** — Fatura  \n  2g · INBOX"))
        XCTAssertTrue(md.contains("- **Veli** — Teklif  \n  5g · Arşiv"))
        XCTAssertTrue(md.contains("_Trova ile dışa aktarıldı_"))
    }

    func testEmailListWithoutMailboxOmitsSeparator() {
        let items = [ExportedListItem(from: "Ali", subject: "Fatura", dateLabel: "2g", mailbox: nil)]
        let md = MarkdownExporter.emailList(title: "Benzer mailler", items: items)
        XCTAssertTrue(md.contains("- **Ali** — Fatura  \n  2g"))
        XCTAssertFalse(md.contains(" · "))   // kutu yoksa ayraç yok
    }

    func testEmailListEmptyShowsPlaceholder() {
        let md = MarkdownExporter.emailList(title: "Arama sonuçları", items: [])
        XCTAssertTrue(md.hasPrefix("# Arama sonuçları\n"))
        XCTAssertTrue(md.contains("_(kayıt yok)_"))
        XCTAssertFalse(md.contains("- **"))   // madde üretilmez
    }

    func testEmailListCountReflectsItemCount() {
        let items = [ExportedListItem(from: "Ali", subject: "Fatura", dateLabel: "2g", mailbox: "INBOX")]
        let md = MarkdownExporter.emailList(title: "X", items: items)
        XCTAssertTrue(md.contains("_1 kayıt_"))
    }

    func testEmailListCleansNewlinesAndKeepsDiacritics() {
        let items = [ExportedListItem(from: "Ali\nVeli", subject: "Çok\nsatırlı şğüöçı",
                                      dateLabel: "dün", mailbox: "Gönderilenler")]
        let md = MarkdownExporter.emailList(title: "İş: çağrı", items: items)
        XCTAssertTrue(md.hasPrefix("# İş: çağrı\n"))
        XCTAssertTrue(md.contains("- **Ali Veli** — Çok satırlı şğüöçı  \n  dün · Gönderilenler"))
    }
}
