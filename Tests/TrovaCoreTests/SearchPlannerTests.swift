import XCTest
@testable import TrovaCore

/// `SearchPlanner.plan` saf ayrıştırma zincirini (operatör → Türkçe tarih → filtre) ve
/// `IndexStore.countSavedSearch` uçtan uca sayımı doğrular. `now`/`calendar` sabit enjekte edilir.
final class SearchPlannerTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    private var now: Date { day(2026, 6, 30) }

    // MARK: - Saf planlayıcı

    /// from: + "son 7 gün" + metin → gönderen filtresi, ~7 gün öncesi since, kalan metin "fatura".
    func testFromPlusDatePlusText() {
        let plan = SearchPlanner.plan("from:ali son 7 gün fatura", now: now, calendar: cal)
        XCTAssertEqual(plan.ftsQuery, "fatura")
        XCTAssertEqual(plan.filter.fromContains, "ali")
        let since = try? XCTUnwrap(plan.filter.since)
        XCTAssertNotNil(since)
        XCTAssertEqual(since!.timeIntervalSince(now), -7 * 86_400, accuracy: 1)
        XCTAssertNil(plan.filter.until)
        XCTAssertNil(plan.filter.attachmentKind)
        XCTAssertFalse(plan.filter.hasAttachment)
    }

    /// has:pdf + metin → ek türü filtresi .pdf, kalan metin "rapor", tarih yok.
    func testAttachmentKindOperator() {
        let plan = SearchPlanner.plan("has:pdf rapor", now: now, calendar: cal)
        XCTAssertEqual(plan.ftsQuery, "rapor")
        XCTAssertEqual(plan.filter.attachmentKind, .pdf)
        XCTAssertNil(plan.filter.since)
        XCTAssertNil(plan.filter.fromContains)
    }

    /// has:ek (tür belirtmeden) → yalnız ekli filtresi, ek türü nil.
    func testHasAttachmentOnly() {
        let plan = SearchPlanner.plan("has:ek sözleşme", now: now, calendar: cal)
        XCTAssertEqual(plan.ftsQuery, "sözleşme")
        XCTAssertTrue(plan.filter.hasAttachment)
        XCTAssertNil(plan.filter.attachmentKind)
    }

    /// Salt tarih ("geçen ay") → FTS metni boş, yalnız tarih aralığı filtrede.
    func testDateOnly() {
        let plan = SearchPlanner.plan("geçen ay", now: now, calendar: cal)
        XCTAssertEqual(plan.ftsQuery, "")
        XCTAssertNotNil(plan.filter.since)
        XCTAssertNotNil(plan.filter.until)
        XCTAssertNil(plan.filter.fromContains)
    }

    /// Düz sorgu → yalnız FTS metni; hiçbir filtre kurulmaz.
    func testPlainQuery() {
        let plan = SearchPlanner.plan("toplantı notları", now: now, calendar: cal)
        XCTAssertEqual(plan.ftsQuery, "toplantı notları")
        XCTAssertTrue(plan.filter.isEmpty)
    }

    /// Hesap ve okunmadı/bayrak UI durumu plana SIZMAZ (yalnız ham sorgudan filtre türer).
    func testNoUIStateLeaks() {
        let plan = SearchPlanner.plan("from:veli rapor", now: now, calendar: cal)
        XCTAssertNil(plan.filter.accountID)
        XCTAssertFalse(plan.filter.unreadOnly)
        XCTAssertFalse(plan.filter.flaggedOnly)
    }

    // MARK: - DB üzerinden sayım (countSavedSearch)

    private func msg(_ id: String, from name: String, addr: String, subject: String,
                     body: String, attachments: String?, date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "A", mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: name, fromAddress: addr, toField: nil,
            ccField: nil, subject: subject, date: date, snippet: body, body: body,
            indexedAt: Date(), attachments: attachments, parserVersion: 1)
    }

    private func makeStore() throws -> IndexStore {
        let store = try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-plan-\(UUID().uuidString).sqlite"))
        try store.upsert([
            // Ali'den 2 fatura: biri bugünlerde (PDF ekli), biri 3 ay önce.
            msg("1", from: "Ali Veli", addr: "ali@x.com", subject: "Fatura Haziran",
                body: "elektrik faturası ödendi", attachments: "f.pdf", date: day(2026, 6, 28)),
            msg("2", from: "Ali Veli", addr: "ali@x.com", subject: "Fatura Mart",
                body: "su faturası geldi", attachments: nil, date: day(2026, 3, 10)),
            // Ayşe'den 1 toplantı (PDF ekli), bugünlerde.
            msg("3", from: "Ayşe", addr: "ayse@y.com", subject: "Toplantı",
                body: "yarın fatura toplantısı var", attachments: "slides.pdf", date: day(2026, 6, 27)),
        ])
        // Ek türü filtresi `attachment` tablosunu sorgular; PDF'leri ayrıca kaydet.
        try store.replaceAttachments(forMessage: "1", names: ["f.pdf"])
        try store.replaceAttachments(forMessage: "3", names: ["slides.pdf"])
        return store
    }

    /// "fatura" 3 maile uyar (metin); from:ali ile 2'ye iner.
    func testCountPlainAndFrom() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.countSavedSearch("fatura", now: now, calendar: cal), 3)
        XCTAssertEqual(try store.countSavedSearch("from:ali fatura", now: now, calendar: cal), 2)
    }

    /// "from:ali son 7 gün fatura" → yalnız son 7 gündeki Ali faturası (1 mail).
    func testCountWithDateFilter() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.countSavedSearch("from:ali son 7 gün fatura", now: now, calendar: cal), 1)
    }

    /// "has:pdf fatura" → ek türü PDF olan + "fatura" geçen mailler (Haziran faturası + toplantı = 2).
    func testCountWithAttachmentKind() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.countSavedSearch("has:pdf fatura", now: now, calendar: cal), 2)
    }
}
