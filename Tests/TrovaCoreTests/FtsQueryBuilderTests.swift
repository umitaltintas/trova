import XCTest
@testable import TrovaCore

/// `FtsQueryBuilder` — gelişmiş arama sözdizimi (tam ifade + dışlama) ve geri-düşüş davranışı.
/// Sözdizimi geçerliliği, gerçek bir geçici FTS5 veritabanında MATCH çalıştırılarak doğrulanır
/// (FTS5 sözdizim hatası aramayı çökertir → builder DAİMA geçerli ifade üretmeli).
final class FtsQueryBuilderTests: XCTestCase {

    // MARK: - Test yardımcıları

    private func msg(_ id: String, subject: String, body: String) -> MessageRecord {
        MessageRecord(
            id: id, messageID: "<\(id)@t>", accountID: "ACC", mailbox: "INBOX",
            filePath: "/tmp/\(id)", fromName: "Gönderen", fromAddress: "g@x.com", toField: nil,
            ccField: nil, subject: subject, date: Date(), snippet: body, body: body,
            indexedAt: Date(), attachments: nil)
    }

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-fts-\(UUID().uuidString).sqlite"))
    }

    /// İçinde "fatura", "reklam", "son odeme" geçen iki örnek mailli depo.
    private func seededStore() throws -> IndexStore {
        let store = try makeStore()
        try store.upsert([
            msg("A", subject: "Fatura bilgisi", body: "son odeme tarihi yaklasiyor"),
            msg("B", subject: "Reklam kampanya", body: "fatura indirim reklam firsati"),
        ])
        return store
    }

    // MARK: - Temiz çıktı / regresyon kilidi (gelişmiş sözdizimi YOK)

    func testTekTerimEskiDavranislaBirebir() {
        // Tek çıplak terim → `"fatura"*` (mevcut ftsPattern ile BİREBİR).
        XCTAssertEqual(FtsQueryBuilder.build("fatura"), "\"fatura\"*")
        XCTAssertEqual(FtsQueryBuilder.build("fatura"), IndexStore.ftsPattern("fatura"))
    }

    func testCokTerimAndBirlesimi() {
        // Çok terim → boşlukla birleşen önekler (FTS5 örtük AND), mevcut davranışla aynı.
        XCTAssertEqual(FtsQueryBuilder.build("fatura odeme"), "\"fatura\"* \"odeme\"*")
        XCTAssertEqual(FtsQueryBuilder.build("fatura odeme"), IndexStore.ftsPattern("fatura odeme"))
    }

    func testNormalSorgularBirebirFtsPattern() {
        // Gelişmiş sözdizimi içermeyen sorgularda çıktı mevcut ftsPattern ile birebir kalmalı.
        for q in ["merhaba", "ali veli", "e-posta adresi", "  bosluklu   sorgu  ", "son: odeme"] {
            XCTAssertEqual(FtsQueryBuilder.build(q), IndexStore.ftsPattern(q), "regresyon: \(q)")
        }
    }

    // MARK: - Gelişmiş sözdizimi

    func testTamIfadeOnekYok() {
        // Tırnak içi tam ifade → FTS5 phrase, sondaki `*` (önek) YOK.
        XCTAssertEqual(FtsQueryBuilder.build("\"son odeme\""), "\"son odeme\"")
        XCTAssertFalse(FtsQueryBuilder.build("\"son odeme\"").hasSuffix("*"))
    }

    func testDislamaNotUretir() {
        // `-reklam` (pozitifle birlikte) → `NOT` ifadesi üretir, dışlanan terimi içerir.
        let expr = FtsQueryBuilder.build("fatura -reklam")
        XCTAssertTrue(expr.contains("NOT"), "dışlama NOT içermeli: \(expr)")
        XCTAssertTrue(expr.contains("reklam"), "dışlanan terim ifadede olmalı: \(expr)")
        XCTAssertTrue(expr.contains("\"fatura\"*"), "pozitif önek korunmalı: \(expr)")
    }

    func testKarisikSorgu() {
        // Pozitif önek + dışlama + tam ifade bir arada.
        let expr = FtsQueryBuilder.build("fatura -reklam \"son odeme\"")
        XCTAssertTrue(expr.contains("\"fatura\"*"), expr)
        XCTAssertTrue(expr.contains("\"son odeme\""), expr)            // phrase, öneksiz
        XCTAssertFalse(expr.contains("\"son odeme\"*"), expr)          // öneksiz olmalı
        XCTAssertTrue(expr.contains("NOT"), expr)
    }

    func testTurkceKarakterlerKorunur() {
        // Diyakritikler (ç,ş,ğ,ü,ö,ı,İ) ifadede aynen yer almalı.
        XCTAssertEqual(FtsQueryBuilder.build("gümüş"), "\"gümüş\"*")
        let expr = FtsQueryBuilder.build("\"İş Bankası\" -şubat")
        XCTAssertTrue(expr.contains("\"İş Bankası\""), expr)
        XCTAssertTrue(expr.contains("şubat"), expr)
    }

    // MARK: - Uç durumlar (çökme YOK)

    func testBosVeYalnizBoslukBosDoner() {
        XCTAssertEqual(FtsQueryBuilder.build(""), "")
        XCTAssertEqual(FtsQueryBuilder.build("    "), "")
    }

    func testYalnizDislamaCokmez() throws {
        // Yalnız dışlama FTS5'te tek başına geçersiz → güvenli geri-düşüş (terimi arar), çökmez.
        let store = try seededStore()
        XCTAssertNoThrow(try store.search(query: "-reklam", filter: .init(), limit: 10))
    }

    func testBosTirnakCokmez() throws {
        let store = try seededStore()
        for q in ["\"\"", "\"", "\"   \"", "-", "- -"] {
            XCTAssertNoThrow(try store.search(query: q, filter: .init(), limit: 10), "çökmemeli: \(q)")
        }
    }

    // MARK: - Gerçek FTS5'te sözdizimi geçerliliği

    func testCesitliGirdilerFTS5teGecerli() throws {
        // Her girdi gerçek bir FTS5 MATCH ile çalıştırılır; sözdizim hatası throw eder → test düşer.
        let store = try seededStore()
        let inputs = [
            "fatura", "fatura odeme", "\"son odeme\"", "fatura -reklam",
            "fatura -reklam \"son odeme\"", "-reklam", "\"İş Bankası\"",
            "gümüş çağrı", "son: odeme", "e-posta",
        ]
        for q in inputs {
            XCTAssertNoThrow(try store.search(query: q, filter: .init(), limit: 10), "geçersiz FTS5: \(q)")
        }
    }

    func testOzelKarakterlerFTS5teGecerli() throws {
        // FTS5 özel karakterleri (* " ( ) : ^ -) uygunsuz yerlerde bile çökertmemeli.
        let store = try seededStore()
        let tricky = [
            "fatura -reklam(x)", "a(b):c^d", "\"a:b (c)\"", "fatura* odeme",
            "\"x\" ***", "*** -y", "--cift", "c++ dili", "^baslangic",
        ]
        for q in tricky {
            XCTAssertNoThrow(try store.search(query: q, filter: .init(), limit: 10), "geçersiz FTS5: \(q)")
        }
    }

    // MARK: - Davranışın doğruluğu (gerçek sonuçlar)

    func testDislamaSonucuGercektenAyiklar() throws {
        // "fatura" iki mailde de geçer; "-reklam" yalnız B'yi eler → sadece A kalmalı.
        let store = try seededStore()
        let hepsi = try store.search(query: "fatura", filter: .init(), limit: 10)
        XCTAssertEqual(Set(hepsi.map(\.id)), ["A", "B"], "dışlamasız iki mail de gelmeli")

        let haricli = try store.search(query: "fatura -reklam", filter: .init(), limit: 10)
        XCTAssertEqual(haricli.map(\.id), ["A"], "-reklam B'yi elemeli")
    }

    func testTamIfadeSiralamayaDuyarli() throws {
        // "son odeme" bitişik A'da var; ters sıra "odeme son" hiçbir maile uymamalı (phrase düzeni).
        let store = try seededStore()
        let dogruSira = try store.search(query: "\"son odeme\"", filter: .init(), limit: 10)
        XCTAssertEqual(dogruSira.map(\.id), ["A"])

        let tersSira = try store.search(query: "\"odeme son\"", filter: .init(), limit: 10)
        XCTAssertTrue(tersSira.isEmpty, "tam ifade sıraya duyarlı olmalı: \(tersSira.map(\.id))")
    }
}
