import XCTest
@testable import TrovaCore

final class AgentToolsTests: XCTestCase {

    private func wrapEMLX(_ rfc822: String) -> Data {
        let body = Data(rfc822.utf8)
        return Data("\(body.count)\n".utf8) + body
    }

    func testExtractAttachmentsAndText() {
        let payload = Data("Selam dünya, bu ek metnidir.".utf8).base64EncodedString()
        let rfc = "Subject: Ekli\r\n"
            + "Content-Type: multipart/mixed; boundary=\"B\"\r\n\r\n"
            + "--B\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nGövde\r\n"
            + "--B\r\nContent-Type: text/plain; name=\"not.txt\"\r\n"
            + "Content-Disposition: attachment; filename=\"not.txt\"\r\n"
            + "Content-Transfer-Encoding: base64\r\n\r\n\(payload)\r\n"
            + "--B--\r\n"

        let attachments = EMLXParser.extractAttachments(data: wrapEMLX(rfc))
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.filename, "not.txt")

        let text = AttachmentText.extract(attachments[0])
        XCTAssertTrue(text.contains("Selam dünya"), "Çıkarılan metin: \(text)")
    }

    func testFromSenderAndCount() throws {
        let store = try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-sender-\(UUID().uuidString).sqlite"))
        func msg(_ id: String, from name: String, addr: String) -> MessageRecord {
            MessageRecord(id: id, messageID: nil, accountID: "A", mailbox: "INBOX", filePath: "/tmp/\(id)",
                          fromName: name, fromAddress: addr, toField: nil, ccField: nil, subject: "k",
                          date: Date(), snippet: "s", body: "b", indexedAt: Date(), parserVersion: 1)
        }
        try store.upsert([
            msg("1", from: "Ali Veli", addr: "ali@x.com"),
            msg("2", from: "Ali Veli", addr: "ali@x.com"),
            msg("3", from: "Ayşe", addr: "ayse@y.com"),
        ])
        XCTAssertEqual(try store.senderCount("ali"), 2)
        XCTAssertEqual(Set(try store.fromSender("ali", limit: 10).map(\.id)), ["1", "2"])
        XCTAssertEqual(try store.fromSender("ayse@y", limit: 10).map(\.id), ["3"])
    }
}
