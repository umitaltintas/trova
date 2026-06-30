import XCTest
@testable import TrovaCore

/// `count_mail` aracı (ölçütlere uyan mail SAYISI): `IndexStore.countMatching` sayma mantığı,
/// `ToolAgent.countText` saf Türkçe biçimlendirici ve uçtan uca ajan tool-call akışı doğrulanır.
final class CountMailToolTests: XCTestCase {

    private final class Counter { var n = 0 }

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    private func msg(_ id: String, from name: String, addr: String, subject: String,
                     body: String, attachments: String?, date: Date) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "A", mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: name, fromAddress: addr, toField: nil,
            ccField: nil, subject: subject, date: date, snippet: body, body: body,
            indexedAt: Date(), attachments: attachments, parserVersion: 1)
    }

    /// 3 mail: 2 "fatura" (Ali, biri ekli), 1 "toplantı" (Ayşe, ekli).
    private func makeStore() throws -> IndexStore {
        let store = try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-count-\(UUID().uuidString).sqlite"))
        try store.upsert([
            msg("1", from: "Ali Veli", addr: "ali@x.com", subject: "Fatura Mart",
                body: "elektrik faturası ödendi", attachments: "f.pdf", date: day(2026, 3, 10)),
            msg("2", from: "Ali Veli", addr: "ali@x.com", subject: "Fatura Nisan",
                body: "su faturası geldi", attachments: nil, date: day(2026, 4, 10)),
            msg("3", from: "Ayşe", addr: "ayse@y.com", subject: "Toplantı",
                body: "yarın toplantı var", attachments: "slides.pdf", date: day(2026, 5, 10)),
        ])
        return store
    }

    // MARK: - countMatching

    /// Sorgu (FTS) + filtre: "fatura" iki maile uyar; gönderen filtresiyle birleşince de aynı.
    func testCountMatchingWithQuery() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.countMatching(query: "fatura"), 2)
        XCTAssertEqual(try store.countMatching(query: "toplantı"), 1)
        XCTAssertEqual(try store.countMatching(query: "fatura",
                                               filter: SearchFilter(fromContains: "ali")), 2)
    }

    /// Sorgu yok → yalnız filtre sayılır (gönderen, ek).
    func testCountMatchingFilterOnly() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.countMatching(query: nil,
                                               filter: SearchFilter(fromContains: "ali")), 2)
        XCTAssertEqual(try store.countMatching(query: nil,
                                               filter: SearchFilter(hasAttachment: true)), 2)
        XCTAssertEqual(try store.countMatching(query: nil,
                       filter: SearchFilter(fromContains: "ali", hasAttachment: true)), 1)
    }

    /// Tarih aralığı filtresi: yalnız Nisan'daki mail.
    func testCountMatchingDateRange() throws {
        let store = try makeStore()
        let filter = SearchFilter(since: day(2026, 4, 1), until: day(2026, 4, 30))
        XCTAssertEqual(try store.countMatching(query: nil, filter: filter), 1)
        XCTAssertEqual(try store.countMatching(query: "fatura", filter: filter), 1)
    }

    /// Boş sorgu + boş filtre → tüm mailleri sayar (toplam).
    func testCountMatchingEmptyCountsAll() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.countMatching(query: nil), 3)
        XCTAssertEqual(try store.countMatching(query: "   "), 3)   // yalnız boşluk → filtre yok
    }

    /// Eşleşme yok → 0 (sorgu hiçbir maile uymuyor / filtre kimseyi tutmuyor).
    func testCountMatchingNoMatch() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.countMatching(query: "kira"), 0)
        XCTAssertEqual(try store.countMatching(query: nil,
                                               filter: SearchFilter(fromContains: "mehmet")), 0)
    }

    // MARK: - countText (saf biçimlendirici)

    /// Tüm ölçütler (sorgu + gönderen + son tarih) parantez içinde sırayla listelenir.
    func testCountTextFullCriteria() {
        let text = ToolAgent.countText(query: "fatura", from: "ali", since: nil,
                                       until: "2026-06-30", hasAttachment: false, count: 42)
        XCTAssertEqual(
            text,
            "Ölçütlere uyan 42 mail bulundu (sorgu: fatura, gönderen: ali, son tarih: 2026-06-30).")
    }

    /// Ölçüt yoksa sade cümle (parantez eklenmez).
    func testCountTextNoCriteria() {
        XCTAssertEqual(
            ToolAgent.countText(query: nil, from: nil, since: nil, until: nil,
                                hasAttachment: false, count: 7),
            "Ölçütlere uyan 7 mail bulundu.")
        // Boş string'ler de ölçüt sayılmaz.
        XCTAssertEqual(
            ToolAgent.countText(query: "", from: "", since: "", until: "",
                                hasAttachment: false, count: 0),
            "Ölçütlere uyan 0 mail bulundu.")
    }

    /// Tekil ölçütler: yalnız ek; gönderen + başlangıç tarihi; 0 sonuç da düzgün yazılır.
    func testCountTextSingleCriteria() {
        XCTAssertEqual(
            ToolAgent.countText(query: nil, from: nil, since: nil, until: nil,
                                hasAttachment: true, count: 0),
            "Ölçütlere uyan 0 mail bulundu (ekli).")
        XCTAssertEqual(
            ToolAgent.countText(query: nil, from: "Ali", since: "2026-01-01", until: nil,
                                hasAttachment: false, count: 5),
            "Ölçütlere uyan 5 mail bulundu (gönderen: Ali, başlangıç tarihi: 2026-01-01).")
    }

    // MARK: - Uçtan uca (ajan tool-call → countMatching → cevap)

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Ajan `count_mail` aracını çağırır (from: Ali) → adımda "sayım: 2" görünür → yanıt verir.
    func testAgentCountMailEndToEnd() throws {
        let counter = Counter()
        MockURLProtocol.handler = { request in
            counter.n += 1
            let message: [String: Any]
            switch counter.n {
            case 1:
                message = ["role": "assistant", "content": NSNull(), "tool_calls": [
                    ["id": "c1", "type": "function",
                     "function": ["name": "count_mail", "arguments": "{\"from\":\"Ali\"}"]]]]
            default:
                message = ["role": "assistant", "content": "Ali'den 2 mail var."]
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
        let run = try agent.run("Ali'den kaç mail var?") { steps.append($0) }

        XCTAssertEqual(run.answer, "Ali'den 2 mail var.")
        XCTAssertEqual(counter.n, 2)
        XCTAssertTrue(steps.contains { $0.kind == .note && $0.detail == "sayım: 2" },
                      "count_mail adımı 'sayım: 2' olmalı: \(steps.map(\.detail))")
    }
}
