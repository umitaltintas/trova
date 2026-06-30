import XCTest
@testable import TrovaCore

/// "Görmezden gel" (digest öğelerini brifingden düşürme) için testler:
/// saf süzme mantığı (`filterDismissed`) + DB round-trip (dismiss/undismiss/clear) + additive migration.
final class DismissedDigestTests: XCTestCase {

    // MARK: - Yardımcılar

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-dismiss-\(UUID().uuidString).sqlite"))
    }

    private func hit(id: String, threadKey: String?, date: Date?) -> SearchHit {
        SearchHit(id: id, subject: "Konu", fromName: "Ali", fromAddress: "ali@x.z",
                  mailbox: "INBOX", date: date, snippet: "kısa içerik", score: 0, threadKey: threadKey)
    }

    private func record(id: String, threadKey: String, mailbox: String = "INBOX") -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@test>", accountID: "ACC", mailbox: mailbox,
            filePath: "/tmp/\(id).emlx", fromName: "Gönderen", fromAddress: "x@example.com",
            toField: "me@example.com", ccField: nil, subject: "Konu", date: Date(),
            snippet: "Konu", body: "Konu", indexedAt: Date(), threadKey: threadKey)
    }

    // MARK: - Saf süzme (filterDismissed)

    func testNotDismissedStaysVisible() {
        let h = hit(id: "1", threadKey: "T", date: Date())
        XCTAssertEqual(filterDismissed([h], dismissed: ["BASKA": Date()]).map(\.id), ["1"])
    }

    func testEmptyDismissedShowsAll() {
        let a = hit(id: "1", threadKey: "A", date: Date())
        let b = hit(id: "2", threadKey: "B", date: Date())
        XCTAssertEqual(filterDismissed([a, b], dismissed: [:]).map(\.id), ["1", "2"])
    }

    func testDismissedWithOlderDateIsHidden() {
        let now = Date()
        // Öğe tarihi gizleme anından ESKİ → gizli.
        let h = hit(id: "1", threadKey: "T", date: now.addingTimeInterval(-100))
        XCTAssertTrue(filterDismissed([h], dismissed: ["T": now]).isEmpty)
    }

    func testDismissedWithNewerDateResurfaces() {
        let now = Date()
        // Öğe tarihi gizleme anından SONRA (konuya yeni yanıt) → tekrar görünür.
        let h = hit(id: "1", threadKey: "T", date: now.addingTimeInterval(100))
        XCTAssertEqual(filterDismissed([h], dismissed: ["T": now]).map(\.id), ["1"])
    }

    func testEqualDateBoundaryIsHidden() {
        let now = Date()
        // Sınır: öğe tarihi == dismissedAt → gizli (yalnız SONRAki tarih görünür).
        let h = hit(id: "1", threadKey: "T", date: now)
        XCTAssertTrue(filterDismissed([h], dismissed: ["T": now]).isEmpty)
    }

    func testThreadKeyNilFallsBackToID() {
        let now = Date()
        // threadKey yoksa anahtar mailin id'sidir.
        let h = hit(id: "X", threadKey: nil, date: now.addingTimeInterval(-10))
        XCTAssertTrue(filterDismissed([h], dismissed: ["X": now]).isEmpty)
        XCTAssertEqual(filterDismissed([h], dismissed: ["Y": now]).map(\.id), ["X"])
    }

    // MARK: - DB round-trip

    func testDismissAndFetchRoundTrip() throws {
        let store = try makeStore()
        let t = Date()
        try store.dismissDigest(threadKey: "T1", at: t)
        let map = try store.dismissedDigest()
        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map["T1"]!.timeIntervalSince1970, t.timeIntervalSince1970, accuracy: 1)
    }

    func testDismissUpsertUpdatesTimestamp() throws {
        let store = try makeStore()
        let t1 = Date().addingTimeInterval(-1000)
        let t2 = Date()
        try store.dismissDigest(threadKey: "T1", at: t1)
        try store.dismissDigest(threadKey: "T1", at: t2)   // upsert → güncelle
        let map = try store.dismissedDigest()
        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map["T1"]!.timeIntervalSince1970, t2.timeIntervalSince1970, accuracy: 1)
    }

    func testUndismissRemovesOnlyOne() throws {
        let store = try makeStore()
        try store.dismissDigest(threadKey: "A", at: Date())
        try store.dismissDigest(threadKey: "B", at: Date())
        try store.undismissDigest(threadKey: "A")
        let map = try store.dismissedDigest()
        XCTAssertEqual(Set(map.keys), ["B"])
    }

    func testClearEmpties() throws {
        let store = try makeStore()
        try store.dismissDigest(threadKey: "A", at: Date())
        try store.dismissDigest(threadKey: "B", at: Date())
        try store.clearDismissedDigest()
        XCTAssertTrue(try store.dismissedDigest().isEmpty)
    }

    func testBlankKeyIgnored() throws {
        let store = try makeStore()
        try store.dismissDigest(threadKey: "   ", at: Date())
        XCTAssertTrue(try store.dismissedDigest().isEmpty)
    }

    // MARK: - Migration v13 additive (mevcut veri korunur)

    func testMigrationAdditivePreservesMessages() throws {
        let store = try makeStore()
        try store.upsert([record(id: "m1", threadKey: "T"), record(id: "m2", threadKey: "T2")])
        XCTAssertEqual(try store.count(), 2)
        // Yeni tablo çalışır ve mevcut mesaj verisi bozulmaz.
        try store.dismissDigest(threadKey: "T", at: Date())
        XCTAssertEqual(try store.dismissedDigest().count, 1)
        XCTAssertEqual(try store.count(), 2)
    }
}
