import XCTest
@testable import TrovaCore

/// `attachment` tablosu (v10) + ada/türe göre arama + reindex idempotency testleri.
final class AttachmentIndexTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-att-\(UUID().uuidString).sqlite")
        return try IndexStore(path: path)
    }

    private func record(id: String, subject: String,
                        from: String = "Ali Veli", address: String = "ali@example.com",
                        date: Date = Date()) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@test>", accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id).emlx", fromName: from, fromAddress: address,
            toField: "me@example.com", ccField: nil, subject: subject, date: date,
            snippet: "snippet", body: "gövde", indexedAt: Date())
    }

    func testReplaceAttachmentsAndJoin() throws {
        let store = try makeStore()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        try store.upsert([record(id: "m1", subject: "Fatura ekte", date: day)])
        try store.replaceAttachments(forMessage: "m1", names: ["fatura.pdf", "ekran.png"])

        let rows = try store.allAttachments(limit: 50)
        XCTAssertEqual(rows.count, 2)
        // Sahip mesaj alanları JOIN ile gelir.
        let pdf = try XCTUnwrap(rows.first { $0.fileName == "fatura.pdf" })
        XCTAssertEqual(pdf.ext, "pdf")
        XCTAssertEqual(pdf.kind, .pdf)
        XCTAssertEqual(pdf.subject, "Fatura ekte")
        XCTAssertEqual(pdf.fromAddress, "ali@example.com")
        XCTAssertEqual(pdf.filePath, "/tmp/m1.emlx")
        XCTAssertEqual(pdf.messageID, "m1")
    }

    func testNameQueryFilter() throws {
        let store = try makeStore()
        try store.upsert([record(id: "m1", subject: "k")])
        try store.replaceAttachments(forMessage: "m1", names: ["Sözleşme.pdf", "logo.png", "sunum.key"])

        // LIKE harf duyarsız (ASCII): "PDF" araması "Sözleşme.pdf"i bulur.
        let pdf = try store.allAttachments(query: "pdf", limit: 50)
        XCTAssertEqual(pdf.map(\.fileName), ["Sözleşme.pdf"])

        let logo = try store.allAttachments(query: "lOgO", limit: 50)
        XCTAssertEqual(logo.map(\.fileName), ["logo.png"])

        XCTAssertTrue(try store.allAttachments(query: "yokböyle", limit: 50).isEmpty)
    }

    func testKindFilterIncludingOther() throws {
        let store = try makeStore()
        try store.upsert([record(id: "m1", subject: "k")])
        try store.replaceAttachments(forMessage: "m1",
            names: ["a.pdf", "b.png", "c.xlsx", "veri.bin", "LICENSE"])

        XCTAssertEqual(try store.allAttachments(kind: .pdf, limit: 50).map(\.fileName), ["a.pdf"])
        XCTAssertEqual(try store.allAttachments(kind: .image, limit: 50).map(\.fileName), ["b.png"])
        XCTAssertEqual(try store.allAttachments(kind: .sheet, limit: 50).map(\.fileName), ["c.xlsx"])

        // .other = bilinen uzantıların hiçbiri değil (uzantısız "LICENSE" dahil).
        let other = Set(try store.allAttachments(kind: .other, limit: 50).map(\.fileName))
        XCTAssertEqual(other, ["veri.bin", "LICENSE"])

        // Kategori sayıları.
        let counts = try store.attachmentKindCounts()
        XCTAssertEqual(counts[.pdf], 1)
        XCTAssertEqual(counts[.image], 1)
        XCTAssertEqual(counts[.sheet], 1)
        XCTAssertEqual(counts[.other], 2)
    }

    func testReindexIsIdempotent() throws {
        let store = try makeStore()
        try store.upsert([record(id: "m1", subject: "k")])
        // İki kez aynı adları yaz → çift kayıt OLUŞMAZ.
        try store.replaceAttachments(forMessage: "m1", names: ["rapor.pdf", "ek.png"])
        try store.replaceAttachments(forMessage: "m1", names: ["rapor.pdf", "ek.png"])
        XCTAssertEqual(try store.allAttachments(limit: 50).count, 2)

        // Adlar değişince eskiler silinip yenileri yazılır.
        try store.replaceAttachments(forMessage: "m1", names: ["yeni.pdf"])
        XCTAssertEqual(try store.allAttachments(limit: 50).map(\.fileName), ["yeni.pdf"])
    }

    func testMigrationIsAdditiveAndCoexists() throws {
        // v10 ek tablosu eklenince mevcut mesaj işlevleri (sayım, arama, ekli sayısı) bozulmaz.
        let store = try makeStore()
        var rec = record(id: "m1", subject: "Kira sözleşmesi")
        rec.attachments = "sozlesme.pdf"   // mesajdaki birleşik FTS kolonu (ayrı tablodan bağımsız)
        try store.upsert([rec])

        XCTAssertEqual(try store.count(), 1)
        XCTAssertEqual(try store.search(query: "kira", limit: 10).first?.id, "m1")
        XCTAssertEqual(try store.attachmentCount(), 1)              // message.attachments kolonu hâlâ çalışır
        XCTAssertTrue(try store.allAttachments(limit: 10).isEmpty)  // ayrı tablo henüz boş
    }
}
