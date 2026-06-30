import XCTest
@testable import TrovaCore

final class MailtoLinkTests: XCTestCase {

    // MARK: - url()

    func testSingleRecipientWithSpacedSubject() {
        let url = MailtoLink.url(to: ["ali@ornek.com"], subject: "Toplantı notları")
        // Boşluk %20, ı → UTF-8 (%C4%B1) olarak kodlanmalı.
        XCTAssertEqual(url?.absoluteString,
                       "mailto:ali@ornek.com?subject=Toplant%C4%B1%20notlar%C4%B1")
    }

    func testSubjectWithAmpersand() {
        let url = MailtoLink.url(to: ["a@b.com"], subject: "A & B")
        XCTAssertEqual(url?.absoluteString, "mailto:a@b.com?subject=A%20%26%20B")
    }

    func testTurkishCharactersRoundTrip() {
        // Diakritikli konu geri çözülünce orijinaline birebir dönmeli.
        let subject = "Görüşme çağrısı — şçöğüı İstanbul"
        let url = MailtoLink.url(to: ["a@b.com"], subject: subject)
        let comps = URLComponents(string: url!.absoluteString)
        let value = comps?.queryItems?.first { $0.name == "subject" }?.value
        XCTAssertEqual(value, subject)
    }

    func testBodyNewlinesEncoded() {
        let url = MailtoLink.url(to: ["a@b.com"], body: "Line1\nLine2")
        // Satır sonu %0A olarak kodlanmalı.
        XCTAssertEqual(url?.absoluteString, "mailto:a@b.com?body=Line1%0ALine2")
    }

    func testMultipleRecipientsCommaJoined() {
        let url = MailtoLink.url(to: ["a@b.com", "c@d.com"])
        XCTAssertEqual(url?.absoluteString, "mailto:a@b.com,c@d.com")
    }

    func testCcRecipient() {
        let url = MailtoLink.url(to: ["a@b.com"], cc: ["c@d.com"])
        XCTAssertEqual(url?.absoluteString, "mailto:a@b.com?cc=c@d.com")
    }

    func testEmptyFieldsAreSkipped() {
        // Kırpma + boşların atılması: tek geçerli alıcı kalır, boş konu/gövde düşer.
        let url = MailtoLink.url(to: ["  a@b.com  ", "", "   "], subject: "   ", body: "")
        XCTAssertEqual(url?.absoluteString, "mailto:a@b.com")
    }

    func testNewEmailWithoutRecipientButWithSubject() {
        // Alıcı boş olsa da konu varsa geçerli (alıcısız yeni e-posta) URL üretilir.
        let url = MailtoLink.url(to: [], subject: "Konu")
        XCTAssertEqual(url?.absoluteString, "mailto:?subject=Konu")
    }

    func testAllEmptyReturnsNil() {
        XCTAssertNil(MailtoLink.url(to: []))
        XCTAssertNil(MailtoLink.url(to: ["  "], cc: [""], subject: "   ", body: " \n "))
    }

    // MARK: - replySubject()

    func testReplySubjectAddsTurkishPrefix() {
        XCTAssertEqual(MailtoLink.replySubject("Toplantı"), "Yan: Toplantı")
    }

    func testReplySubjectKeepsExistingTurkishPrefix() {
        XCTAssertEqual(MailtoLink.replySubject("Yan: Toplantı"), "Yan: Toplantı")
    }

    func testReplySubjectKeepsRePrefix() {
        XCTAssertEqual(MailtoLink.replySubject("Re: Meeting"), "Re: Meeting")
    }

    func testReplySubjectKeepsUppercaseRe() {
        XCTAssertEqual(MailtoLink.replySubject("RE: x"), "RE: x")
    }

    func testReplySubjectKeepsForwardPrefix() {
        // İletme öneki de "önek var" sayılır; başa ikinci kez "Yan:" eklenmez.
        XCTAssertEqual(MailtoLink.replySubject("Fwd: y"), "Fwd: y")
        XCTAssertEqual(MailtoLink.replySubject("İlt: Rapor"), "İlt: Rapor")
    }

    func testReplySubjectTrimsBeforePrefixing() {
        XCTAssertEqual(MailtoLink.replySubject("  Toplantı  "), "Yan: Toplantı")
    }
}
