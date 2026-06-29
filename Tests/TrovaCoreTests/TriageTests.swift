import XCTest
@testable import TrovaCore

final class TriageTests: XCTestCase {

    // MARK: - Kutu sınıflandırma

    func testIsSentMailbox() {
        XCTAssertTrue(isSentMailbox("Sent Messages"))
        XCTAssertTrue(isSentMailbox("/Users/x/Library/Mail/Sent.mbox"))
        XCTAssertTrue(isSentMailbox("Gönderilmiş Postalar"))
        XCTAssertTrue(isSentMailbox("Giden"))
        XCTAssertTrue(isSentMailbox("Outbox"))

        XCTAssertFalse(isSentMailbox("INBOX"))
        XCTAssertFalse(isSentMailbox("Gelen Kutusu"))
        XCTAssertFalse(isSentMailbox("Trash"))
        XCTAssertFalse(isSentMailbox("Arşiv"))
    }

    func testIsActionableMailbox() {
        XCTAssertTrue(isActionableMailbox("INBOX"))
        XCTAssertTrue(isActionableMailbox("Gelen Kutusu"))

        XCTAssertFalse(isActionableMailbox("Sent Messages"))   // gönderilmiş
        XCTAssertFalse(isActionableMailbox("Gönderilmiş"))
        XCTAssertFalse(isActionableMailbox("Trash"))
        XCTAssertFalse(isActionableMailbox("Çöp"))
        XCTAssertFalse(isActionableMailbox("Junk"))
        XCTAssertFalse(isActionableMailbox("Spam"))
        XCTAssertFalse(isActionableMailbox("Arşiv"))
        XCTAssertFalse(isActionableMailbox("Taslaklar"))       // "taslak" içerir
    }

    // MARK: - Triyaj sorguları (yanıt gerekiyor / yanıt bekliyor)

    private func makeStore() throws -> IndexStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-triage-\(UUID().uuidString).sqlite")
        return try IndexStore(path: path)
    }

    private func record(id: String, threadKey: String, mailbox: String,
                        daysAgo: Double, subject: String = "Konu") -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@test>", accountID: "ACC", mailbox: mailbox,
            filePath: "/tmp/\(id).emlx", fromName: "Gönderen", fromAddress: "x@example.com",
            toField: "me@example.com", ccField: nil, subject: subject,
            date: Date().addingTimeInterval(-daysAgo * 86_400),
            snippet: subject, body: subject, indexedAt: Date(), threadKey: threadKey)
    }

    /// Thread A: en son mail INBOX (karşı taraf yazdı) → yanıt gerekiyor.
    /// Thread B: en son mail Gönderilmiş (sen yazdın) → yanıt bekliyor.
    /// Thread C: en son mail Trash → ikisinde de OLMAMALI.
    func testNeedsReplyAndWaitingOnByLatestMailbox() throws {
        let store = try makeStore()
        try store.upsert([
            record(id: "a1", threadKey: "A", mailbox: "Sent Messages", daysAgo: 5),
            record(id: "a2", threadKey: "A", mailbox: "INBOX", daysAgo: 2),
            record(id: "b1", threadKey: "B", mailbox: "INBOX", daysAgo: 6),
            record(id: "b2", threadKey: "B", mailbox: "Gönderilmiş Postalar", daysAgo: 4),
            record(id: "c1", threadKey: "C", mailbox: "INBOX", daysAgo: 3),
            record(id: "c2", threadKey: "C", mailbox: "Trash", daysAgo: 1),
        ])

        let needs = try store.needsReply(limit: 50)
        XCTAssertEqual(needs.map(\.id), ["a2"])   // yalnızca A; en son mail INBOX

        let waiting = try store.waitingOnReply(minDays: 0, limit: 50)
        XCTAssertEqual(waiting.map(\.id), ["b2"]) // yalnızca B; en son mail Gönderilmiş

        // Trash en sonlu thread (C) yanıt gerekenlerde OLMAMALI.
        XCTAssertFalse(needs.contains { $0.id == "c1" || $0.id == "c2" })

        // minDays eşiği: B'nin yaşı ~4 gün; 5 günlük eşik elemeli.
        XCTAssertTrue(try store.waitingOnReply(minDays: 5, limit: 50).isEmpty)
    }

    /// `threadKey`'siz mailler kendi thread'i sayılır; en son mail kuralı yine geçerli.
    func testRecentReceivedExcludesSentAndJunk() throws {
        let store = try makeStore()
        try store.upsert([
            record(id: "r1", threadKey: "R1", mailbox: "INBOX", daysAgo: 1),
            record(id: "s1", threadKey: "S1", mailbox: "Sent", daysAgo: 1),
            record(id: "j1", threadKey: "J1", mailbox: "Spam", daysAgo: 1),
            record(id: "old", threadKey: "O1", mailbox: "INBOX", daysAgo: 10),
        ])
        let recent = try store.recentReceived(sinceDays: 2, limit: 50)
        XCTAssertEqual(recent.map(\.id), ["r1"])   // gönderilmiş/spam elenir, eski (10g) pencere dışı
    }
}

final class DigestBuilderTests: XCTestCase {

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func client() -> OpenRouterClient {
        OpenRouterClient(
            config: .init(baseURL: URL(string: "https://api.test/v1")!, apiKey: "k", model: "m"),
            session: session())
    }

    private func hit(_ id: String, _ subject: String) -> SearchHit {
        SearchHit(id: id, subject: subject, fromName: "Ali", fromAddress: "ali@x.z",
                  mailbox: "INBOX", date: Date(), snippet: "kısa içerik", score: 0)
    }

    func testBuildReturnsMockedMarkdown() throws {
        let markdown = "## Faturalar\n- Elektrik faturası geldi.\n\n## Yapılacaklar / yanıt bekleyenler\n- Kira sözleşmesini yenile."
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url!.absoluteString.hasSuffix("/chat/completions"))
            let root: [String: Any] = [
                "choices": [["message": ["role": "assistant", "content": markdown]]],
            ]
            let data = try JSONSerialization.data(withJSONObject: root)
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, data)
        }
        let out = try DigestBuilder(llm: client()).build([hit("1", "Elektrik faturası")])
        XCTAssertEqual(out, markdown)
    }

    func testEmptyHitsSkipsNetwork() throws {
        // Boş girdi LLM'e GİTMEMELİ; handler çağrılırsa test düşer.
        MockURLProtocol.handler = { _ in
            XCTFail("Boş mail listesinde ağ çağrısı yapılmamalı")
            throw URLError(.badURL)
        }
        let out = try DigestBuilder(llm: client()).build([])
        XCTAssertEqual(out, "Yeni mail yok.")
    }
}
