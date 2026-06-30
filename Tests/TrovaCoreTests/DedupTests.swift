import XCTest
import GRDB
@testable import TrovaCore

/// Message-ID ile mail tekilleştirme (Faz 12): Apple Mail (Gmail/IMAP) aynı maili birden çok yere
/// yazdığından (Tüm Postalar + Gelen + her etiket) aynı mantıksal mail için çok sayıda `.emlx`
/// oluşur. İleriye dönük dedup kopyaları eklemeyi reddeder; `dedupeExisting` mevcut kopyaları temizler.
final class DedupTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-dedup-\(UUID().uuidString).sqlite"))
    }

    private func rec(id: String, messageID: String?, mailbox: String = "INBOX",
                     subject: String = "Konu", body: String = "gövde metni") -> MessageRecord {
        MessageRecord(
            id: id, messageID: messageID, accountID: "ACC", mailbox: mailbox,
            filePath: "/tmp/\(id).emlx", fromName: "Ali", fromAddress: "ali@x.com",
            toField: "me@x.com", ccField: nil, subject: subject, date: Date(),
            snippet: String(body.prefix(100)), body: body, indexedAt: Date())
    }

    /// Forward-dedup'tan ÖNCE yazılmış kopyaları taklit eder: dedup kapısını atlayıp ham satır ekler.
    private func seedRaw(_ store: IndexStore, _ records: [MessageRecord]) throws {
        try store.dbQueue.write { db in
            for r in records { try r.insert(db) }
        }
    }

    private func ids(_ store: IndexStore) throws -> Set<String> {
        Set(try store.dbQueue.read { db in try String.fetchAll(db, sql: "SELECT id FROM message") })
    }

    // MARK: - İleriye dönük dedup (upsert)

    /// Aynı Message-ID'li iki farklı yol → yalnız 1 satır; ilki inserted, ikincisi duplicates.
    func testForwardDedupSkipsDuplicateMessageID() throws {
        let store = try makeStore()
        let first = try store.upsert([rec(id: "pathA", messageID: "<m1@host>")])
        XCTAssertEqual(first.inserted, 1)
        XCTAssertEqual(first.duplicates, 0)

        let second = try store.upsert([rec(id: "pathB", messageID: "<m1@host>")])
        XCTAssertEqual(second.inserted, 0)
        XCTAssertEqual(second.duplicates, 1)
        XCTAssertTrue(second.duplicateIDs.contains("pathB"))

        XCTAssertEqual(try store.count(), 1)   // tek mantıksal mail kalır
    }

    /// NULL Message-ID'li iki kayıt tekilleştirilmez (her biri tutulur).
    func testNullMessageIDNotDeduped() throws {
        let store = try makeStore()
        let r = try store.upsert([
            rec(id: "a", messageID: nil),
            rec(id: "b", messageID: nil),
        ])
        XCTAssertEqual(r.inserted, 2)
        XCTAssertEqual(r.duplicates, 0)
        XCTAssertEqual(try store.count(), 2)
    }

    /// Aynı dosyayı (aynı id) yeniden upsert → güncelleme; dedup atlanmaz, kopya sayılmaz.
    func testReupsertSameIDIsUpdateNotDuplicate() throws {
        let store = try makeStore()
        _ = try store.upsert([rec(id: "a", messageID: "<m@host>", subject: "İlk")])
        let again = try store.upsert([rec(id: "a", messageID: "<m@host>", subject: "Güncel")])
        XCTAssertEqual(again.inserted, 0)
        XCTAssertEqual(again.duplicates, 0)
        XCTAssertEqual(try store.count(), 1)
        XCTAssertEqual(try store.search(query: "Güncel", limit: 10).first?.id, "a")
    }

    /// Aynı parti içindeki kopyalar da yakalanır (ilk eklenir, sonraki atlanır).
    func testForwardDedupWithinSingleBatch() throws {
        let store = try makeStore()
        let r = try store.upsert([
            rec(id: "a", messageID: "<dup@host>"),
            rec(id: "b", messageID: "<dup@host>"),   // aynı parti — kopya
            rec(id: "c", messageID: "<other@host>"),
        ])
        XCTAssertEqual(r.inserted, 2)   // a + c
        XCTAssertEqual(r.duplicates, 1) // b atlandı
        XCTAssertEqual(try store.count(), 2)
    }

    // MARK: - Mevcut yinelenenleri temizle (dedupeExisting)

    /// Kanonik satır kalır, kopyalar silinir; vektör yokken gelen kutusu arşive tercih edilir.
    func testDedupeExistingKeepsCanonicalRemovesCopies() throws {
        let store = try makeStore()
        try seedRaw(store, [
            rec(id: "p1", messageID: "<dup@host>", mailbox: "Archive"),
            rec(id: "p2", messageID: "<dup@host>", mailbox: "INBOX"),
            rec(id: "p3", messageID: "<dup@host>", mailbox: "Gmail/Tüm Postalar"),
            rec(id: "solo", messageID: "<solo@host>", mailbox: "INBOX"),
        ])
        XCTAssertEqual(try store.count(), 4)
        XCTAssertEqual(try store.duplicateCount(), 2)   // 3 kopya − 1 distinct = 2 fazladan

        let removed = try store.dedupeExisting()
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(try store.count(), 2)
        XCTAssertEqual(try store.duplicateCount(), 0)
        // Vektör yok → (b) gelen/gönderilen kutusu; INBOX/Tüm Postalar eşit, en küçük rowid (p2) kazanır.
        XCTAssertEqual(try ids(store), Set(["p2", "solo"]))
    }

    /// (a) Vektörü (embedding) olan satır kutu tercihinden önce gelir → gömme korunur.
    func testDedupePrefersRowWithVector() throws {
        let store = try makeStore()
        try seedRaw(store, [
            rec(id: "v1", messageID: "<dup@host>", mailbox: "INBOX"),
            rec(id: "v2", messageID: "<dup@host>", mailbox: "Archive"),
        ])
        try store.upsertVectors([("v2", [1, 0, 0])])   // gömme yalnız arşivdeki kopyada

        let removed = try store.dedupeExisting()
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(try ids(store), Set(["v2"]))   // arşivde olsa bile vektörlü satır kalır
        XCTAssertEqual(try store.vectorCount(), 1)    // gömme korundu
    }

    /// Silinen kopyanın YETİM ek/ek-içeriği kayıtları da temizlenir; kanoniğin eki korunur.
    func testDedupeRemovesOrphanAttachmentsAndContent() throws {
        let store = try makeStore()
        try seedRaw(store, [
            rec(id: "keep", messageID: "<dup@host>", mailbox: "INBOX"),
            rec(id: "drop", messageID: "<dup@host>", mailbox: "Archive"),
        ])
        try store.replaceAttachments(forMessage: "drop", names: ["rapor.pdf"])
        try store.replaceAttachmentContent(messageID: "drop", text: "yetim ek içeriği")
        try store.replaceAttachments(forMessage: "keep", names: ["sozlesme.pdf"])

        let removed = try store.dedupeExisting()
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(try ids(store), Set(["keep"]))

        let attMessageIDs = try store.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT messageID FROM attachment")
        }
        XCTAssertEqual(attMessageIDs, ["keep"])               // kanoniğin eki duruyor
        XCTAssertEqual(try store.attachmentContentCount(), 0) // yetim ek-içeriği silindi
    }

    /// Yinelenen yokken (NULL'lar dahil) işlem no-op'tur.
    func testDedupeNoDuplicatesIsNoOp() throws {
        let store = try makeStore()
        _ = try store.upsert([
            rec(id: "a", messageID: "<a@host>"),
            rec(id: "b", messageID: "<b@host>"),
            rec(id: "n1", messageID: nil),
            rec(id: "n2", messageID: nil),
        ])
        XCTAssertEqual(try store.duplicateCount(), 0)
        XCTAssertEqual(try store.dedupeExisting(), 0)
        XCTAssertEqual(try store.count(), 4)
    }

    /// `duplicateCount` silinecek satır sayısına eşittir; ilerleme grup sayısını raporlar.
    func testDuplicateCountEqualsRemovedAndProgressReported() throws {
        let store = try makeStore()
        try seedRaw(store, [
            rec(id: "a1", messageID: "<g1@host>"),
            rec(id: "a2", messageID: "<g1@host>"),
            rec(id: "a3", messageID: "<g1@host>"),
            rec(id: "b1", messageID: "<g2@host>"),
            rec(id: "b2", messageID: "<g2@host>"),
        ])
        let expected = try store.duplicateCount()   // (3−1) + (2−1) = 3
        XCTAssertEqual(expected, 3)

        var lastTotal = 0
        let removed = try store.dedupeExisting { _, total in lastTotal = total }
        XCTAssertEqual(removed, expected)
        XCTAssertEqual(lastTotal, 2)                 // 2 yinelenen Message-ID grubu
        XCTAssertEqual(try store.count(), 2)         // her gruptan 1 kanonik
    }
}
