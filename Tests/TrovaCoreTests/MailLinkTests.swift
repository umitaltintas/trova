import XCTest
@testable import TrovaCore

final class MailLinkTests: XCTestCase {

    func testBuildsURLFromBracketedID() {
        let url = MailLink.appleMailURL(messageID: "<abc123@mail.example.com>")
        XCTAssertEqual(url?.absoluteString, "message://%3Cabc123%40mail.example.com%3E")
    }

    func testBuildsURLFromBareID() {
        let url = MailLink.appleMailURL(messageID: "abc123@mail.example.com")
        XCTAssertEqual(url?.absoluteString, "message://%3Cabc123%40mail.example.com%3E")
    }

    func testEncodesUnsafeCharacters() {
        // Message-ID'de + / = gibi karakterler yüzde-kodlanmalı.
        let url = MailLink.appleMailURL(messageID: "<CA+Ej_p5/4=x@gmail.com>")
        XCTAssertEqual(url?.absoluteString,
                       "message://%3CCA%2BEj_p5%2F4%3Dx%40gmail.com%3E")
    }

    func testTrimsWhitespace() {
        let url = MailLink.appleMailURL(messageID: "   <id@host>  ")
        XCTAssertEqual(url?.absoluteString, "message://%3Cid%40host%3E")
    }

    func testPreservesUnreservedChars() {
        let url = MailLink.appleMailURL(messageID: "a-b._c~d@h-o.st")
        XCTAssertEqual(url?.absoluteString, "message://%3Ca-b._c~d%40h-o.st%3E")
    }

    func testNilForEmpty() {
        XCTAssertNil(MailLink.appleMailURL(messageID: nil))
        XCTAssertNil(MailLink.appleMailURL(messageID: ""))
        XCTAssertNil(MailLink.appleMailURL(messageID: "   "))
        XCTAssertNil(MailLink.appleMailURL(messageID: "<>"))
        XCTAssertNil(MailLink.appleMailURL(messageID: "<  >"))
    }
}
