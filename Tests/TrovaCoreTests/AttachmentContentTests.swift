import XCTest
import AppKit
@testable import TrovaCore

/// Ek içeriği araması (Faz 11, opt-in): ucuz metin çıkarımı (AttachmentTextFast),
/// `attachment_content` FTS tablosu (migration additive + CRUD) ve Searcher entegrasyonu.
final class AttachmentContentTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-content-\(UUID().uuidString).sqlite")
        return try IndexStore(path: path)
    }

    private func record(id: String, subject: String, body: String) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@test>", accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id).emlx", fromName: "Ali", fromAddress: "ali@example.com",
            toField: "me@example.com", ccField: nil, subject: subject, date: Date(),
            snippet: String(body.prefix(80)), body: body, indexedAt: Date(),
            attachments: "ek.txt")   // ekli işaretle ki backfill listesine düşsün
    }

    // MARK: - AttachmentTextFast (ucuz, OCR'sız çıkarım)

    func testFastTextPlainUTF8() {
        let data = Data("Merhaba dünya, bu düz metin ekidir. çğıöşü".utf8)
        XCTAssertEqual(AttachmentTextFast.fastText(data: data, fileName: "notlar.txt"),
                       "Merhaba dünya, bu düz metin ekidir. çğıöşü")
    }

    func testFastTextCSVAndMarkdown() {
        XCTAssertEqual(AttachmentTextFast.fastText(data: Data("a,b,c\n1,2,3".utf8), fileName: "veri.csv"),
                       "a,b,c\n1,2,3")
        XCTAssertEqual(AttachmentTextFast.fastText(data: Data("# Başlık".utf8), fileName: "README.md"),
                       "# Başlık")
    }

    func testFastTextRTF() {
        let s = NSAttributedString(string: "Sözleşme metni RTF içinde")
        let rtf = s.rtf(from: NSRange(location: 0, length: s.length), documentAttributes: [:])
        let text = AttachmentTextFast.fastText(data: rtf ?? Data(), fileName: "belge.rtf")
        XCTAssertEqual(text, "Sözleşme metni RTF içinde")
    }

    func testFastTextUnknownAndImageReturnsNil() {
        // Görsel/taranmış uzantılar OCR'a düşmeden nil (Vision çağrılmaz).
        XCTAssertNil(AttachmentTextFast.fastText(data: Data("PNGDATA".utf8), fileName: "foto.png"))
        XCTAssertNil(AttachmentTextFast.fastText(data: Data("x".utf8), fileName: "arsiv.zip"))
        XCTAssertNil(AttachmentTextFast.fastText(data: Data("x".utf8), fileName: "veri.bin"))
    }

    func testFastTextEmptyDataReturnsNil() {
        XCTAssertNil(AttachmentTextFast.fastText(data: Data(), fileName: "bos.txt"))
        // Yalnız boşluktan oluşan metin de nil (anlamlı içerik yok).
        XCTAssertNil(AttachmentTextFast.fastText(data: Data("   \n\t ".utf8), fileName: "bos.txt"))
    }

    func testFastTextRespectsMaxChars() {
        let data = Data(String(repeating: "x", count: 500).utf8)
        XCTAssertEqual(AttachmentTextFast.fastText(data: data, fileName: "uzun.txt", maxChars: 100)?.count, 100)
    }

    // MARK: - attachmentContentText (mailin tüm eklerinden toplu metin)

    func testAttachmentContentTextFromEMLXCollectsOnlyAttachments() {
        let mime = "Content-Type: multipart/mixed; boundary=\"B\"\r\n\r\n"
            + "--B\r\nContent-Type: text/plain\r\n\r\nGövde metni burada.\r\n"
            + "--B\r\nContent-Type: text/plain; name=\"notlar.txt\"\r\n"
            + "Content-Disposition: attachment; filename=\"notlar.txt\"\r\n\r\n"
            + "Gizli ek metni raporxyz.\r\n"
            + "--B--\r\n"
        let text = Indexer.attachmentContentText(from: Data(mime.utf8))
        XCTAssertTrue(text.contains("raporxyz"))
        XCTAssertFalse(text.contains("Gövde metni"))   // yalnız ek içeriği, gövde değil
    }

    // MARK: - IndexStore CRUD + idempotency

    func testReplaceMatchClearCount() throws {
        let store = try makeStore()
        try store.upsert([record(id: "m1", subject: "Konu", body: "gövde")])

        XCTAssertEqual(try store.attachmentContentCount(), 0)
        try store.replaceAttachmentContent(messageID: "m1", text: "Bu ekte raporxyz geçiyor")
        XCTAssertEqual(try store.attachmentContentCount(), 1)
        XCTAssertEqual(try store.messageIDsMatchingAttachmentContent("raporxyz"), ["m1"])

        // İdempotent: tekrar yazınca çift kayıt oluşmaz.
        try store.replaceAttachmentContent(messageID: "m1", text: "Bu ekte raporxyz geçiyor")
        XCTAssertEqual(try store.attachmentContentCount(), 1)

        // Boş metinle değiştirince satır silinir (eski içerik bayatlamaz).
        try store.replaceAttachmentContent(messageID: "m1", text: "   ")
        XCTAssertEqual(try store.attachmentContentCount(), 0)
        XCTAssertTrue(try store.messageIDsMatchingAttachmentContent("raporxyz").isEmpty)

        // Temizleme tabloyu boşaltır.
        try store.replaceAttachmentContent(messageID: "m1", text: "tekrar raporxyz")
        try store.clearAttachmentContent()
        XCTAssertEqual(try store.attachmentContentCount(), 0)
    }

    func testMigrationIsAdditive() throws {
        // v11 yeni FTS tablosu eklenince mevcut mesaj işlevleri (sayım, arama) bozulmaz.
        let store = try makeStore()
        try store.upsert([record(id: "m1", subject: "Kira sözleşmesi", body: "daire kirası")])
        XCTAssertEqual(try store.count(), 1)
        XCTAssertEqual(try store.search(query: "kira", limit: 10).first?.id, "m1")
        XCTAssertEqual(try store.attachmentContentCount(), 0)   // yeni tablo başlangıçta boş
    }

    func testMessagesWithAttachmentsBackfillList() throws {
        let store = try makeStore()
        try store.upsert([record(id: "m1", subject: "Ekli", body: "x")])
        var noAtt = record(id: "m2", subject: "Eksiz", body: "y")
        noAtt.attachments = nil
        try store.upsert([noAtt])
        let list = try store.messagesWithAttachments()
        XCTAssertEqual(list.map(\.id), ["m1"])   // yalnız eki olan mail
        XCTAssertEqual(list.first?.filePath, "/tmp/m1.emlx")
    }

    // MARK: - Searcher entegrasyonu (opt-in)

    func testSearcherIncludesAttachmentContentWhenEnabled() throws {
        let store = try makeStore()
        // Gövde "raporxyz" içermiyor; yalnız ek içeriğinde var.
        try store.upsert([record(id: "m1", subject: "Aylık özet", body: "bu ay olağan gidişat")])
        try store.replaceAttachmentContent(messageID: "m1", text: "Ekteki tabloda raporxyz değeri var")

        // Kapalı: ek içeriği taranmaz → sonuç yok.
        let off = try Searcher(store: store, includeAttachmentContent: false)
            .search("raporxyz", mode: .fts, limit: 10)
        XCTAssertTrue(off.isEmpty)

        // Açık: ek içeriğinden gelir ve rozetlenir.
        let on = try Searcher(store: store, includeAttachmentContent: true)
            .search("raporxyz", mode: .fts, limit: 10)
        XCTAssertEqual(on.map(\.id), ["m1"])
        XCTAssertTrue(on.first?.matchedInAttachment ?? false)
    }

    func testSearcherMarksExistingHitMatchedInAttachment() throws {
        let store = try makeStore()
        // Hem gövde hem ek içeriği "kontrat" içeriyor → mevcut FTS sonucu işaretlenir.
        try store.upsert([record(id: "m1", subject: "Konu", body: "kontrat detayları gövdede")])
        try store.replaceAttachmentContent(messageID: "m1", text: "ekte de kontrat maddeleri")

        let on = try Searcher(store: store, includeAttachmentContent: true)
            .search("kontrat", mode: .fts, limit: 10)
        XCTAssertEqual(on.map(\.id), ["m1"])
        XCTAssertTrue(on.first?.matchedInAttachment ?? false)
    }
}
