import XCTest
@testable import TrovaCore

final class AttachmentExtractionTests: XCTestCase {

    func testExtractsAttachmentBytesAndName() {
        // base64 "JVBERi0x" → "%PDF-1" (PDF sihirli baytları).
        let mime = "Content-Type: multipart/mixed; boundary=\"B\"\r\n\r\n"
            + "--B\r\nContent-Type: text/plain\r\n\r\nGövde metni\r\n"
            + "--B\r\nContent-Type: application/pdf; name=\"rapor.pdf\"\r\n"
            + "Content-Transfer-Encoding: base64\r\n"
            + "Content-Disposition: attachment; filename=\"rapor.pdf\"\r\n\r\nJVBERi0x\r\n"
            + "--B--\r\n"
        let attachments = EMLXParser.extractAttachments(data: Data(mime.utf8))

        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.filename, "rapor.pdf")
        XCTAssertEqual(attachments.first?.mimeType.contains("pdf"), true)
        XCTAssertEqual(String(decoding: attachments.first?.data ?? Data(), as: UTF8.self), "%PDF-1")
    }

    func testNoAttachmentsForPlainMessage() {
        let mime = "Content-Type: text/plain\r\n\r\nSadece gövde, ek yok.\r\n"
        XCTAssertTrue(EMLXParser.extractAttachments(data: Data(mime.utf8)).isEmpty)
    }
}
