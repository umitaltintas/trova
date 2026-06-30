import XCTest
import GRDB
@testable import TrovaCore

/// Silinen mailleri indekslemede temizleme (prune): kullanıcı Apple Mail'den bir maili silince
/// kaynak `.emlx` kaybolur; tam, iptal edilmemiş bir yeniden indekslemede o satır (ve yetim
/// vektör/ek/ek-içeriği) DB'den düşürülür. Kısmi/iptal/limit'li/prune-kapalı taramada ASLA silinmez.
final class PruneTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-prune-\(UUID().uuidString).sqlite"))
    }

    private func rec(_ id: String, messageID: String? = nil, mailbox: String = "INBOX") -> MessageRecord {
        MessageRecord(
            id: id, messageID: messageID ?? "<\(id)@host>", accountID: "ACC", mailbox: mailbox,
            filePath: "/tmp/\(id).emlx", fromName: "Ali", fromAddress: "ali@x.com",
            toField: "me@x.com", ccField: nil, subject: "Konu", date: Date(),
            snippet: "snippet", body: "gövde metni", indexedAt: Date())
    }

    private func ids(_ store: IndexStore) throws -> Set<String> {
        Set(try store.dbQueue.read { db in try String.fetchAll(db, sql: "SELECT id FROM message") })
    }

    // MARK: - pruneMissing (store seviyesi)

    /// keepIDs dışındaki satır + yetim vektör/ek/ek-içeriği silinir; keepIDs içindekiler korunur.
    func testPruneMissingRemovesOrphansKeepsKept() throws {
        let store = try makeStore()
        try store.upsert([rec("a"), rec("b"), rec("c")])
        try store.upsertVectors([("b", [1, 0, 0])])
        try store.replaceAttachments(forMessage: "b", names: ["kayip.pdf"])
        try store.replaceAttachmentContent(messageID: "b", text: "yetim ek içeriği")
        try store.replaceAttachments(forMessage: "a", names: ["duran.pdf"])

        let removed = try store.pruneMissing(keepIDs: ["a", "c"])   // b'nin dosyası kaybolmuş
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(try store.count(), 2)
        XCTAssertEqual(try ids(store), Set(["a", "c"]))
        XCTAssertEqual(try store.vectorCount(), 0)            // b'nin gömmesi gitti
        XCTAssertEqual(try store.attachmentContentCount(), 0) // b'nin ek-içeriği gitti

        let attMessageIDs = try store.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT messageID FROM attachment")
        }
        XCTAssertEqual(attMessageIDs, ["a"])   // b'nin eki gitti, a'nınki durdu
    }

    /// Uç durum: boş keepIDs → tüm satırlar silinir.
    func testPruneMissingEmptyKeepRemovesAll() throws {
        let store = try makeStore()
        try store.upsert([rec("a"), rec("b")])
        XCTAssertEqual(try store.pruneMissing(keepIDs: []), 2)
        XCTAssertEqual(try store.count(), 0)
    }

    /// Kayıp dosya yoksa (tüm satırlar keepIDs'te) işlem no-op'tur; fazladan id zararsızdır.
    func testPruneMissingNoMissingIsNoOp() throws {
        let store = try makeStore()
        try store.upsert([rec("a"), rec("b")])
        let removed = try store.pruneMissing(keepIDs: ["a", "b", "dbde-olmayan-id"])
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(try store.count(), 2)
    }

    /// Büyük keepIDs (binlerce id) → geçici tablo yolu SQLite parametre limitine takılmadan çalışır.
    func testPruneMissingLargeKeepSet() throws {
        let store = try makeStore()
        var recs: [MessageRecord] = []
        for i in 0..<5000 { recs.append(rec("id\(i)")) }
        try store.upsert(recs)
        XCTAssertEqual(try store.count(), 5000)

        var keep = Set<String>()
        for i in 0..<5000 where i % 2 == 0 { keep.insert("id\(i)") }   // çiftleri tut → 2500
        let removed = try store.pruneMissing(keepIDs: keep)
        XCTAssertEqual(removed, 2500)
        XCTAssertEqual(try store.count(), 2500)
    }

    // MARK: - Indexer.run (uçtan uca, gerçek `.emlx`)

    private func tempRoot() throws -> (root: URL, messages: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-prune-store-\(UUID().uuidString)", isDirectory: true)
        let messages = root.appendingPathComponent("ACCT/Gelen.mbox/Messages", isDirectory: true)
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)
        return (root, messages)
    }

    @discardableResult
    private func writeEMLX(_ dir: URL, name: String, subject: String, messageID: String) throws -> URL {
        let rfc = "Message-ID: \(messageID)\r\n"
            + "From: Ali <ali@x.com>\r\n"
            + "Subject: \(subject)\r\n"
            + "Content-Type: text/plain; charset=UTF-8\r\n\r\n"
            + "gövde metni\r\n"
        let body = Data(rfc.utf8)
        let url = dir.appendingPathComponent(name)
        try (Data("\(body.count)\n".utf8) + body).write(to: url)
        return url
    }

    /// 3 `.emlx` indeksle; birini sil; TAM yeniden indeksle → o satır prune edilir (removed=1),
    /// diğerleri durur.
    func testFullReindexPrunesDeletedEmlx() throws {
        let (root, messages) = try tempRoot()
        try writeEMLX(messages, name: "1.emlx", subject: "Bir", messageID: "<m1@host>")
        let second = try writeEMLX(messages, name: "2.emlx", subject: "İki", messageID: "<m2@host>")
        try writeEMLX(messages, name: "3.emlx", subject: "Üç", messageID: "<m3@host>")

        let store = try makeStore()
        let first = try Indexer.run(store: store, root: root)
        XCTAssertEqual(first.removed, 0)        // ilk taramada silinecek yok
        XCTAssertEqual(try store.count(), 3)

        try FileManager.default.removeItem(at: second)   // kullanıcı Mail'den sildi

        let again = try Indexer.run(store: store, root: root)
        XCTAssertEqual(again.removed, 1)
        XCTAssertEqual(try store.count(), 2)
        XCTAssertFalse(try ids(store).contains(Indexer.stableID(for: second)))
    }

    /// İptal edilmiş tam tarama → `seen` eksik olabileceğinden ASLA prune yapılmaz.
    func testCancelledRunDoesNotPrune() throws {
        let (root, messages) = try tempRoot()
        try writeEMLX(messages, name: "1.emlx", subject: "Bir", messageID: "<m1@host>")
        let second = try writeEMLX(messages, name: "2.emlx", subject: "İki", messageID: "<m2@host>")
        try writeEMLX(messages, name: "3.emlx", subject: "Üç", messageID: "<m3@host>")

        let store = try makeStore()
        _ = try Indexer.run(store: store, root: root)
        XCTAssertEqual(try store.count(), 3)

        try FileManager.default.removeItem(at: second)
        let flag = CancellationFlag()
        flag.cancel()
        let result = try Indexer.run(store: store, root: root, cancel: flag)
        XCTAssertEqual(result.removed, 0)
        XCTAssertEqual(try store.count(), 3)   // iptal → silinen satır prune EDİLMEDİ
    }

    /// limit'li (kısmi) tarama → `seen` eksik olduğundan prune yapılmaz.
    func testLimitedScanDoesNotPrune() throws {
        let (root, messages) = try tempRoot()
        try writeEMLX(messages, name: "1.emlx", subject: "Bir", messageID: "<m1@host>")
        let second = try writeEMLX(messages, name: "2.emlx", subject: "İki", messageID: "<m2@host>")
        try writeEMLX(messages, name: "3.emlx", subject: "Üç", messageID: "<m3@host>")

        let store = try makeStore()
        _ = try Indexer.run(store: store, root: root)
        try FileManager.default.removeItem(at: second)

        let result = try Indexer.run(store: store, root: root, limit: 1)
        XCTAssertEqual(result.removed, 0)
        XCTAssertEqual(try store.count(), 3)   // kısmi tarama → prune yok
    }

    /// pruneMissing: false (autoSync yolu gibi) → silinen dosya olsa bile satır düşürülmez.
    func testPruneDisabledFlagSkipsPrune() throws {
        let (root, messages) = try tempRoot()
        try writeEMLX(messages, name: "1.emlx", subject: "Bir", messageID: "<m1@host>")
        let second = try writeEMLX(messages, name: "2.emlx", subject: "İki", messageID: "<m2@host>")

        let store = try makeStore()
        _ = try Indexer.run(store: store, root: root)
        try FileManager.default.removeItem(at: second)

        let result = try Indexer.run(store: store, root: root, pruneMissing: false)
        XCTAssertEqual(result.removed, 0)
        XCTAssertEqual(try store.count(), 2)   // prune kapalı → satır korunur
    }

    /// KRİTİK güvenlik değişmezi: hiç `.emlx` GÖRÜLMEYEN (boş/erişilemeyen kök) tam bir tarama
    /// ASLA satır silmez. `seen` boş kalırsa `pruneMissing(keepIDs: [])` TÜM indeksi süpürürdü;
    /// Indexer'ın guard'ı bunu engeller. (En felaket senaryo — daha önce Indexer seviyesinde
    /// doğrudan test edilmiyordu.)
    func testEmptyRootDoesNotPruneEverything() throws {
        let (root, messages) = try tempRoot()
        try writeEMLX(messages, name: "1.emlx", subject: "Bir", messageID: "<m1@host>")
        try writeEMLX(messages, name: "2.emlx", subject: "İki", messageID: "<m2@host>")

        let store = try makeStore()
        _ = try Indexer.run(store: store, root: root)
        XCTAssertEqual(try store.count(), 2)

        // Geçerli ama BOŞ (hiç .emlx içermeyen) bir kök → discoverMessages [] döner → seen boş.
        let emptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-prune-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)

        let result = try Indexer.run(store: store, root: emptyRoot)   // pruneMissing varsayılan: true
        XCTAssertEqual(result.removed, 0)            // boş `seen` → silme YOK
        XCTAssertEqual(try store.count(), 2)         // indeks olduğu gibi korunur (felaket önlendi)
    }

    // MARK: - Prune güvenlik yüklemi (saf — Indexer.shouldPrune)

    /// Yalnız "tam + iptal yok + limit yok + en az bir dosya görüldü + pruneMissing açık" durumunda
    /// prune güvenlidir; her ihlal eden kombinasyon `false` döner (her biri `seen`'i eksik bırakabilir).
    func testShouldPruneTruthTable() {
        // Tüm koşullar sağlanırsa → güvenli.
        XCTAssertTrue(Indexer.shouldPrune(
            pruneMissing: true, limit: nil, cancelled: false, seenIsEmpty: false))

        // Her bir koşulun ihlali tek başına prune'u engeller.
        XCTAssertFalse(Indexer.shouldPrune(
            pruneMissing: false, limit: nil, cancelled: false, seenIsEmpty: false), "pruneMissing kapalı")
        XCTAssertFalse(Indexer.shouldPrune(
            pruneMissing: true, limit: 100, cancelled: false, seenIsEmpty: false), "limit verildi")
        XCTAssertFalse(Indexer.shouldPrune(
            pruneMissing: true, limit: nil, cancelled: true, seenIsEmpty: false), "iptal edildi")
        XCTAssertFalse(Indexer.shouldPrune(
            pruneMissing: true, limit: nil, cancelled: false, seenIsEmpty: true), "hiç dosya görülmedi")
    }
}
