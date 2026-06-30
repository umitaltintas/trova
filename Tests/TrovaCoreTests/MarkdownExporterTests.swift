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
}
