import XCTest
@testable import TrovaCore

/// `find_attachments` aracı (ekleri ada/türe/gönderene göre listele): `ToolAgent.findAttachmentsText`
/// saf Türkçe biçimlendirici, `attachmentKind` etiket eşlemesi, `findAttachments` DB yolu
/// (allAttachments + `from` post-filtre) ve uçtan uca ajan tool-call akışı doğrulanır.
final class FindAttachmentsToolTests: XCTestCase {

    private final class Counter { var n = 0 }

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func row(_ id: Int64, _ fileName: String, from name: String?, addr: String?,
                     date: Date?) -> AttachmentRow {
        AttachmentRow(id: id, fileName: fileName, ext: AttachmentName.ext(of: fileName),
                      messageID: "m\(id)", subject: "S\(id)", fromName: name, fromAddress: addr,
                      date: date, filePath: "/tmp/m\(id).emlx")
    }

    // MARK: - findAttachmentsText (saf biçimlendirici)

    /// Çok satır: üstte ölçüt + sayı, her satır "dosya adı · gönderen · tarih"; ad yoksa e-posta,
    /// tarih yoksa "-" yazılır.
    func testFindAttachmentsTextFormatting() {
        let rows = [
            row(1, "fatura.pdf", from: "Ali Veli", addr: "ali@x.com", date: day(2024, 3, 5, 14, 30)),
            row(2, "sunum.key", from: nil, addr: "ayse@y.com", date: nil),
        ]
        let text = ToolAgent.findAttachmentsText(rows: rows, name: nil, kind: .pdf,
                                                 from: "ali", calendar: cal)
        XCTAssertEqual(text, """
            2 ek bulundu (tür: PDF, gönderen: ali):
            - fatura.pdf · Ali Veli · 5 Mart 2024 14:30
            - sunum.key · ayse@y.com · -
            """)
    }

    /// 0 satır → "ek bulunamadı"; ölçütler yine parantezde listelenir.
    func testFindAttachmentsTextEmpty() {
        XCTAssertEqual(
            ToolAgent.findAttachmentsText(rows: [], name: "rapor", kind: nil, from: nil),
            "Ölçütlere uyan ek bulunamadı (ad: rapor).")
        // Ölçüt yoksa sade cümle.
        XCTAssertEqual(
            ToolAgent.findAttachmentsText(rows: [], name: nil, kind: nil, from: nil),
            "Ölçütlere uyan ek bulunamadı.")
    }

    /// Tekil ölçüt (yalnız tür) metne yansır; başlık doğru sayar.
    func testFindAttachmentsTextSingleCriterion() {
        let rows = [row(1, "veri.csv", from: "K", addr: "k@x.com", date: day(2026, 1, 2))]
        let text = ToolAgent.findAttachmentsText(rows: rows, name: nil, kind: .sheet,
                                                 from: nil, calendar: cal)
        XCTAssertTrue(text.hasPrefix("1 ek bulundu (tür: Tablo):"))
        XCTAssertTrue(text.contains("- veri.csv · K · 2 Ocak 2026 09:00"))
    }

    // MARK: - attachmentKind (etiket eşlemesi)

    func testAttachmentKindMapping() {
        XCTAssertEqual(ToolAgent.attachmentKind(from: "pdf"), .pdf)
        XCTAssertEqual(ToolAgent.attachmentKind(from: "Görsel"), .image)
        XCTAssertEqual(ToolAgent.attachmentKind(from: "TABLO"), .sheet)
        XCTAssertEqual(ToolAgent.attachmentKind(from: "belge"), .doc)
        XCTAssertEqual(ToolAgent.attachmentKind(from: "sunum"), .presentation)
        XCTAssertEqual(ToolAgent.attachmentKind(from: " arşiv "), .archive)
        XCTAssertEqual(ToolAgent.attachmentKind(from: "kod"), .code)
        XCTAssertNil(ToolAgent.attachmentKind(from: nil))
        XCTAssertNil(ToolAgent.attachmentKind(from: "   "))
        XCTAssertNil(ToolAgent.attachmentKind(from: "uçak"))
    }

    // MARK: - findAttachments (DB yolu: allAttachments + from post-filtre)

    private func msg(_ id: String, from name: String, addr: String, subject: String,
                     date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "A", mailbox: "INBOX",
            filePath: "/tmp/\(id).emlx", fromName: name, fromAddress: addr, toField: nil,
            ccField: nil, subject: subject, date: date, snippet: "x", body: "x",
            indexedAt: Date(), attachments: nil)
    }

    /// 3 mail, 5 ek: Ali (fatura.pdf, logo.png + sunum.key), Ayşe (rapor.pdf, veri.csv).
    private func makeStore() throws -> IndexStore {
        let store = try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-finatt-\(UUID().uuidString).sqlite"))
        try store.upsert([
            msg("1", from: "Ali Veli", addr: "ali@x.com", subject: "Fatura", date: day(2026, 3, 10)),
            msg("2", from: "Ali Veli", addr: "ali@x.com", subject: "Sunum", date: day(2026, 4, 10)),
            msg("3", from: "Ayşe Yıldız", addr: "ayse@y.com", subject: "Rapor", date: day(2026, 5, 10)),
        ])
        try store.replaceAttachments(forMessage: "1", names: ["fatura.pdf", "logo.png"])
        try store.replaceAttachments(forMessage: "2", names: ["sunum.key"])
        try store.replaceAttachments(forMessage: "3", names: ["rapor.pdf", "veri.csv"])
        return store
    }

    private func agent(_ store: IndexStore) -> ToolAgent {
        let llm = OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"))
        return ToolAgent(store: store, embedder: nil, llm: llm)
    }

    /// Ada göre (fileName LIKE): "pdf" → iki PDF.
    func testFindByName() throws {
        let rows = agent(try makeStore()).findAttachments(name: "pdf", kind: nil, from: nil, limit: 20)
        XCTAssertEqual(Set(rows.map(\.fileName)), ["fatura.pdf", "rapor.pdf"])
    }

    /// Türe göre: pdf → 2; tablo → yalnız csv.
    func testFindByKind() throws {
        let store = try makeStore()
        XCTAssertEqual(
            Set(agent(store).findAttachments(name: nil, kind: .pdf, from: nil, limit: 20).map(\.fileName)),
            ["fatura.pdf", "rapor.pdf"])
        XCTAssertEqual(
            agent(store).findAttachments(name: nil, kind: .sheet, from: nil, limit: 20).map(\.fileName),
            ["veri.csv"])
    }

    /// Gönderene göre post-filtre: e-posta parçası VE gönderen adı (her ikisi de) eşleşir; yoksa boş.
    func testFindFromPostFilter() throws {
        let store = try makeStore()
        // E-posta parçası → Ali'nin tüm ekleri.
        XCTAssertEqual(
            Set(agent(store).findAttachments(name: nil, kind: nil, from: "ali@x", limit: 20).map(\.fileName)),
            ["fatura.pdf", "logo.png", "sunum.key"])
        // Gönderen ADI → Ayşe'nin ekleri (post-filtre fromName'i de denetler).
        XCTAssertEqual(
            Set(agent(store).findAttachments(name: nil, kind: nil, from: "yıldız", limit: 20).map(\.fileName)),
            ["rapor.pdf", "veri.csv"])
        // Eşleşmeyen gönderen → boş.
        XCTAssertTrue(
            agent(store).findAttachments(name: nil, kind: nil, from: "mehmet", limit: 20).isEmpty)
    }

    /// Ölçüt birleşimi: tür + gönderen → Ali'nin PDF'i yalnız fatura.pdf (rapor.pdf Ayşe'nin).
    func testFindCombination() throws {
        let rows = agent(try makeStore()).findAttachments(name: nil, kind: .pdf, from: "ali", limit: 20)
        XCTAssertEqual(rows.map(\.fileName), ["fatura.pdf"])
    }

    /// limit, (post-filtre olmadan) sonuç sayısını sınırlar.
    func testFindRespectsLimit() throws {
        let rows = agent(try makeStore()).findAttachments(name: nil, kind: nil, from: nil, limit: 2)
        XCTAssertEqual(rows.count, 2)   // toplam 5 ek var
    }

    // MARK: - Uçtan uca (ajan tool-call → findAttachments → cevap)

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Ajan `find_attachments` (kind: pdf) çağırır → adımda "ekler: 2" görünür → yanıt verir.
    func testAgentFindAttachmentsEndToEnd() throws {
        let counter = Counter()
        MockURLProtocol.handler = { request in
            counter.n += 1
            let message: [String: Any]
            switch counter.n {
            case 1:
                message = ["role": "assistant", "content": NSNull(), "tool_calls": [
                    ["id": "c1", "type": "function",
                     "function": ["name": "find_attachments", "arguments": "{\"kind\":\"pdf\"}"]]]]
            default:
                message = ["role": "assistant", "content": "2 PDF eki var."]
            }
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": message]]])
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, data)
        }

        let llm = OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"),
            session: session())
        let agent = ToolAgent(store: try makeStore(), embedder: nil, llm: llm)

        var steps: [AgentStep] = []
        let run = try agent.run("hangi PDF ekleri geldi?") { steps.append($0) }

        XCTAssertEqual(run.answer, "2 PDF eki var.")
        XCTAssertEqual(counter.n, 2)
        XCTAssertTrue(steps.contains { $0.kind == .search && $0.detail == "ekler: 2" },
                      "find_attachments adımı 'ekler: 2' olmalı: \(steps.map(\.detail))")
    }
}
