import XCTest
@testable import TrovaCore

final class TopSendersTests: XCTestCase {

    private func msg(_ id: String, name: String?, addr: String?, mailbox: String) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: mailbox,
            filePath: "/tmp/\(id)", fromName: name, fromAddress: addr, toField: nil,
            ccField: nil, subject: "S\(id)", date: Date(), snippet: "x", body: "x", indexedAt: Date())
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-top-\(UUID().uuidString).sqlite"))
    }

    func testTopSendersCountsAndExcludesSent() throws {
        let store = try makeStore()
        try store.upsert([
            msg("1", name: "Ali", addr: "ali@x.com", mailbox: "INBOX"),
            msg("2", name: "Ali", addr: "ali@x.com", mailbox: "INBOX"),
            msg("3", name: nil, addr: "ali@x.com", mailbox: "INBOX"),
            msg("4", name: "Ali V.", addr: "ALI@x.com", mailbox: "Gelen Kutusu"),  // büyük/küçük harf → birleşir
            msg("5", name: "Veli", addr: "veli@x.com", mailbox: "INBOX"),
            msg("6", name: "Veli", addr: "veli@x.com", mailbox: "INBOX"),
            msg("7", name: "Ben", addr: "me@x.com", mailbox: "Sent Messages"),     // gönderilen → hariç
            msg("8", name: "Boş", addr: "", mailbox: "INBOX"),                     // boş adres → hariç
        ])

        let top = try store.topSenders(limit: 10)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].address.lowercased(), "ali@x.com")
        XCTAssertEqual(top[0].count, 4, "büyük/küçük harf farkı tek kişide birleşmeli")
        XCTAssertEqual(top[1].address.lowercased(), "veli@x.com")
        XCTAssertEqual(top[1].count, 2)
        XCTAssertNotNil(top[0].name, "temsilci görünen ad seçilmeli")
        XCTAssertFalse(top.contains { $0.address.lowercased() == "me@x.com" })
    }

    func testTopSendersRespectsLimit() throws {
        let store = try makeStore()
        try store.upsert((1...5).map {
            msg("\($0)", name: "K\($0)", addr: "k\($0)@x.com", mailbox: "INBOX")
        })
        XCTAssertEqual(try store.topSenders(limit: 3).count, 3)
    }

    func testEmptyStoreReturnsEmpty() throws {
        let store = try makeStore()
        XCTAssertTrue(try store.topSenders(limit: 10).isEmpty)
    }

    // MARK: - matching (ada/adrese göre süzme)

    private func peopleStore() throws -> IndexStore {
        let store = try makeStore()
        try store.upsert([
            msg("1", name: "Ali Veli", addr: "ali@x.com", mailbox: "INBOX"),
            msg("2", name: "Ayşe Şahin", addr: "ayse@firma.com", mailbox: "INBOX"),
            msg("3", name: "Mehmet Öz", addr: "mehmet@x.com", mailbox: "INBOX"),
        ])
        return store
    }

    func testMatchingByNameFiltersSenders() throws {
        let res = try peopleStore().topSenders(matching: "Ayşe", limit: 10)
        XCTAssertEqual(res.map(\.address), ["ayse@firma.com"], "yalnız ad parçası eşleşen gönderen")
    }

    func testMatchingByAddressFiltersSenders() throws {
        let res = try peopleStore().topSenders(matching: "mehmet@", limit: 10)
        XCTAssertEqual(res.map(\.address), ["mehmet@x.com"], "yalnız adres parçası eşleşen gönderen")
    }

    func testMatchingIsCaseInsensitive() throws {
        let store = try makeStore()
        try store.upsert([msg("1", name: "Ahmet", addr: "Ahmet@X.com", mailbox: "INBOX")])
        XCTAssertEqual(try store.topSenders(matching: "ahmet", limit: 10).count, 1)
        XCTAssertEqual(try store.topSenders(matching: "AHMET@x.COM", limit: 10).count, 1)
    }

    func testMatchingNilReturnsAllLikeBefore() throws {
        let store = try peopleStore()
        XCTAssertEqual(try store.topSenders(matching: nil, limit: 10).count, 3)
        XCTAssertEqual(try store.topSenders(limit: 10).count, 3, "varsayılan matching=nil → mevcut davranış")
    }

    func testMatchingNoMatchReturnsEmpty() throws {
        XCTAssertTrue(try peopleStore().topSenders(matching: "bulunmaz-kişi", limit: 10).isEmpty)
    }

    func testMatchingStillExcludesSentMailbox() throws {
        let store = try makeStore()
        try store.upsert([
            msg("1", name: "Ali", addr: "ali@x.com", mailbox: "INBOX"),
            msg("2", name: "Ali Kopya", addr: "ali@x.com", mailbox: "Sent Messages"),  // gönderilen → hariç
        ])
        let res = try store.topSenders(matching: "ali", limit: 10)
        XCTAssertEqual(res.count, 1)
        XCTAssertEqual(res[0].count, 1, "süzme yapılsa da gönderilen kutusu sayılmaz")
    }

    func testMatchingEscapesLikeWildcards() throws {
        let store = try makeStore()
        try store.upsert([
            msg("1", name: "Yüzde 50% Kampanya", addr: "promo@x.com", mailbox: "INBOX"),
            msg("2", name: "Ahmet", addr: "ahmet@x.com", mailbox: "INBOX"),
            msg("3", name: "a_b Şirketi", addr: "altcizgi@x.com", mailbox: "INBOX"),
            msg("4", name: "axb Şirketi", addr: "axb@x.com", mailbox: "INBOX"),
        ])
        // "%" literal aranır → yalnız gerçek % içeren (hepsi değil).
        XCTAssertEqual(try store.topSenders(matching: "%", limit: 10).map(\.address), ["promo@x.com"])
        // "_" literal aranır → "a_b" yalnız gerçek _ içeren; "axb" eşleşmez.
        XCTAssertEqual(try store.topSenders(matching: "a_b", limit: 10).map(\.address), ["altcizgi@x.com"])
    }
}
