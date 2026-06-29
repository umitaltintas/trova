import XCTest
@testable import TrovaCore

final class EMLXParserTests: XCTestCase {

    /// `.emlx` zarfını (byte sayısı önekiyle) RFC822 mesajına sarar.
    private func wrapEMLX(_ rfc822: String) -> Data {
        let body = Data(rfc822.utf8)
        return Data("\(body.count)\n".utf8) + body
    }

    func testQuotedPrintableBodyAndEncodedWordHeaders() {
        let rfc = "From: =?UTF-8?Q?=C3=9Cmit=20Alt=C4=B1nta=C5=9F?= <umit@example.com>\r\n"
            + "To: ali@example.com\r\n"
            + "Subject: =?UTF-8?B?TWVyaGFiYSBkw7xueWE=?=\r\n"
            + "Date: Mon, 29 Jun 2026 10:00:00 +0000\r\n"
            + "Content-Type: text/plain; charset=UTF-8\r\n"
            + "Content-Transfer-Encoding: quoted-printable\r\n"
            + "\r\n"
            + "Merhaba=20d=C3=BCnya, bu bir =C3=B6rnek mesajd=C4=B1r.\r\n"

        let parsed = EMLXParser.parse(data: wrapEMLX(rfc))
        XCTAssertEqual(parsed.subject, "Merhaba dünya")
        XCTAssertEqual(parsed.fromName, "Ümit Altıntaş")
        XCTAssertEqual(parsed.fromAddress, "umit@example.com")
        XCTAssertTrue(parsed.body.contains("örnek"), "Gövde: \(parsed.body)")
        XCTAssertTrue(parsed.body.contains("mesajdır"), "Gövde: \(parsed.body)")
        XCTAssertNotNil(parsed.date)
    }

    func testMultipartAlternativePrefersPlainText() {
        let rfc = "Subject: Test\r\n"
            + "Content-Type: multipart/alternative; boundary=\"BOUND\"\r\n"
            + "\r\n"
            + "--BOUND\r\n"
            + "Content-Type: text/plain; charset=UTF-8\r\n"
            + "\r\n"
            + "Düz metin gövdesi\r\n"
            + "--BOUND\r\n"
            + "Content-Type: text/html; charset=UTF-8\r\n"
            + "\r\n"
            + "<html><body><p>HTML gövdesi</p></body></html>\r\n"
            + "--BOUND--\r\n"

        let parsed = EMLXParser.parse(data: wrapEMLX(rfc))
        XCTAssertTrue(parsed.body.contains("Düz metin"), "Gövde: \(parsed.body)")
        XCTAssertFalse(parsed.body.contains("HTML gövdesi"), "Gövde: \(parsed.body)")
    }

    func testHTMLOnlyBodyIsStripped() {
        let rfc = "Subject: Bülten\r\n"
            + "Content-Type: text/html; charset=UTF-8\r\n"
            + "\r\n"
            + "<div>Fatura <b>tutarınız</b> 100 TL</div>\r\n"

        let parsed = EMLXParser.parse(data: wrapEMLX(rfc))
        XCTAssertTrue(parsed.body.contains("Fatura"))
        XCTAssertTrue(parsed.body.contains("tutarınız"))
        XCTAssertFalse(parsed.body.contains("<b>"))
    }

    func testExtractHTMLBodyFromMultipart() {
        let rfc = "Subject: Test\r\n"
            + "Content-Type: multipart/alternative; boundary=\"B\"\r\n"
            + "\r\n"
            + "--B\r\n"
            + "Content-Type: text/plain; charset=UTF-8\r\n"
            + "\r\n"
            + "Düz metin\r\n"
            + "--B\r\n"
            + "Content-Type: text/html; charset=UTF-8\r\n"
            + "\r\n"
            + "<p>Biçimli <b>içerik</b></p>\r\n"
            + "--B--\r\n"
        let html = EMLXParser.extractHTMLBody(data: wrapEMLX(rfc))
        XCTAssertNotNil(html)
        XCTAssertTrue(html!.contains("<b>içerik</b>"))
    }

    func testSanitizeRemovesTrackingAndScripts() {
        let dirty = "<p>Selam</p>"
            + "<img src=\"https://track.example.com/pixel.gif\" width=1>"
            + "<script>alert('x')</script>"
            + "<a href=\"#\" onclick=\"steal()\">tık</a>"
        let clean = EMLXParser.sanitizeEmailHTML(dirty)
        XCTAssertFalse(clean.contains("track.example.com"), "izleme pikseli kalmamalı: \(clean)")
        XCTAssertFalse(clean.contains("<script"), "script kalmamalı")
        XCTAssertFalse(clean.lowercased().contains("onclick"), "olay işleyici kalmamalı")
        XCTAssertTrue(clean.contains("Selam"))
    }

    func testNormalizeSubjectStripsPrefixes() {
        XCTAssertEqual(EMLXParser.normalizeSubject("Re: Toplantı"), "toplantı")
        XCTAssertEqual(EMLXParser.normalizeSubject("YANIT: Fwd: Rapor"), "rapor")
        XCTAssertEqual(EMLXParser.normalizeSubject("İlt: Bütçe Planı"), "bütçe planı")
        XCTAssertEqual(EMLXParser.normalizeSubject(nil), "")
    }

    func testAttachmentNamesAndReferences() {
        let rfc = "Subject: Ekli rapor\r\n"
            + "In-Reply-To: <abc@x>\r\n"
            + "References: <root@x> <abc@x>\r\n"
            + "Content-Type: multipart/mixed; boundary=\"M\"\r\n\r\n"
            + "--M\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nGövde metni\r\n"
            + "--M\r\nContent-Type: application/pdf; name=\"rapor.pdf\"\r\n"
            + "Content-Disposition: attachment; filename=\"rapor.pdf\"\r\n\r\nJVBERi0x\r\n"
            + "--M--\r\n"
        let parsed = EMLXParser.parse(data: wrapEMLX(rfc))
        XCTAssertEqual(parsed.attachments, ["rapor.pdf"])
        XCTAssertTrue(parsed.body.contains("Gövde metni"))
        XCTAssertEqual(parsed.inReplyTo, "abc@x")
        XCTAssertEqual(parsed.references, ["root@x", "abc@x"])
    }

    func testISO88599TurkishCharset() {
        // "İçerik" benzeri Türkçe metni iso-8859-9 ile kodla.
        let turkish = "Selam çörek ş"
        let data = turkish.data(using: String.Encoding(rawValue:
            CFStringConvertEncodingToNSStringEncoding(
                CFStringConvertIANACharSetNameToEncoding("iso-8859-9" as CFString))))!
        let rfc = "Subject: Test\r\n"
            + "Content-Type: text/plain; charset=iso-8859-9\r\n"
            + "\r\n"
        let raw = Data(rfc.utf8) + data
        let parsed = EMLXParser.parse(data: Data("\(raw.count)\n".utf8) + raw)
        XCTAssertEqual(parsed.body, turkish)
    }
}
