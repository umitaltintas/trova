import XCTest
@testable import TrovaCore

/// `SearchFilter.attachmentKind` — yalnızca ilgili türde eki olan mailleri döndüren DB filtresi.
/// `attachment` tablosu üzerinden EXISTS ile uygulanır; serbest-metin/browse yollarında çalışır.
final class AttachmentKindFilterTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-attkind-\(UUID().uuidString).sqlite"))
    }

    private func record(id: String, subject: String, date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id).emlx", fromName: "Ali", fromAddress: "ali@x.com",
            toField: "me@x.com", ccField: nil, subject: subject, date: date,
            snippet: "snippet", body: "gövde", indexedAt: Date())
    }

    /// PDF, görsel ve uzantısız ekli üç mail kurar.
    private func seed(_ store: IndexStore) throws {
        let now = Date()
        try store.upsert([
            record(id: "pdfMail", subject: "rapor pdf", date: now),
            record(id: "imgMail", subject: "rapor görsel", date: now.addingTimeInterval(-60)),
            record(id: "binMail", subject: "rapor diğer", date: now.addingTimeInterval(-120)),
        ])
        try store.replaceAttachments(forMessage: "pdfMail", names: ["rapor.pdf"])
        try store.replaceAttachments(forMessage: "imgMail", names: ["ekran.png"])
        try store.replaceAttachments(forMessage: "binMail", names: ["veri.bin"])
    }

    func testBrowseFiltersByPdfKind() throws {
        let store = try makeStore()
        try seed(store)
        let hits = try store.browse(SearchFilter(attachmentKind: .pdf), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["pdfMail"])
    }

    func testBrowseFiltersByImageKind() throws {
        let store = try makeStore()
        try seed(store)
        let hits = try store.browse(SearchFilter(attachmentKind: .image), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["imgMail"])
    }

    func testBrowseFiltersByOtherKind() throws {
        let store = try makeStore()
        try seed(store)
        // .other = bilinen uzantıların hiçbiri değil → yalnız "veri.bin".
        let hits = try store.browse(SearchFilter(attachmentKind: .other), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["binMail"])
    }

    func testSearchCombinesTextAndKind() throws {
        let store = try makeStore()
        try seed(store)
        // Hepsinin konusu "rapor"; tür filtresi yalnız PDF olanı bırakır.
        let hits = try store.search(query: "rapor", filter: SearchFilter(attachmentKind: .pdf), limit: 10)
        XCTAssertEqual(hits.map(\.id), ["pdfMail"])
    }

    func testKindFilterMakesFilterNonEmpty() {
        XCTAssertFalse(SearchFilter(attachmentKind: .pdf).isEmpty)
        XCTAssertTrue(SearchFilter().isEmpty)
    }

    /// FTS `attachments` kolonu (v5) ana serbest-metin aramasında zaten eşleşir: konu/gövdede
    /// geçmeyen bir ek adı yazınca o mail bulunur. Bu davranışın regresyona uğramadığını doğrular.
    func testFreeTextSearchMatchesAttachmentName() throws {
        let store = try makeStore()
        var rec = record(id: "m1", subject: "Aylık özet", date: Date())
        rec.body = "İçeride ek adı geçmiyor."
        rec.attachments = "butce_2026.xlsx"          // yalnız ek adında geçen sözcük
        try store.upsert([rec])
        let hits = try store.search(query: "butce", limit: 10)
        XCTAssertEqual(hits.map(\.id), ["m1"], "ek adındaki sözcük serbest aramada eşleşmeli")
    }
}
