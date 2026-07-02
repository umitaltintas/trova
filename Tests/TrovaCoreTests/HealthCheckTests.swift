import XCTest
@testable import TrovaCore

final class HealthCheckTests: XCTestCase {

    /// Test girdisi üretici — yalnızca ilgilenilen alanlar geçilir, gerisi makul varsayılan.
    private func input(
        readable: Bool = true, located: Bool = true, indexed: Int = 100,
        vectors: Int = 100, llm: Bool = true, embedder: Bool = true, local: Bool = false,
        autoEmbed: Bool = true
    ) -> HealthInput {
        HealthInput(mailStoreReadable: readable, mailStoreLocated: located,
                    indexedCount: indexed, vectorCount: vectors, llmConfigured: llm,
                    embedderConfigured: embedder, usesLocalEmbedder: local, autoEmbedEnabled: autoEmbed)
    }

    // MARK: - Tam Disk Erişimi

    func testNoAccessFailsAndBlocksSetup() {
        let r = HealthCheck.evaluate(input(readable: false))
        XCTAssertEqual(r.item("fda")?.status, .fail)
        XCTAssertFalse(r.isReady)
        XCTAssertTrue(r.needsSetup)
        XCTAssertEqual(r.overall, .fail)
        // Erişim yokken "store" maddesi hiç üretilmez (anlamsız).
        XCTAssertNil(r.item("store"))
        // İndeks maddesi ön koşula düşürülür (fail değil, warn).
        XCTAssertEqual(r.item("index")?.status, .warn)
    }

    // MARK: - Erişim var, indeks boş

    func testAccessButNoIndexNeedsSetup() {
        let r = HealthCheck.evaluate(input(indexed: 0, vectors: 0))
        XCTAssertEqual(r.item("fda")?.status, .ok)
        XCTAssertEqual(r.item("store")?.status, .ok)
        XCTAssertEqual(r.item("index")?.status, .fail)
        XCTAssertFalse(r.isReady)
        XCTAssertTrue(r.needsSetup)
    }

    func testStoreMissingFailsWhenReadable() {
        let r = HealthCheck.evaluate(input(located: false, indexed: 0, vectors: 0))
        XCTAssertEqual(r.item("store")?.status, .fail)
    }

    // MARK: - İndeks var, vektör yok

    func testIndexedButNoVectorsIsReadyButWarns() {
        let r = HealthCheck.evaluate(input(vectors: 0))
        XCTAssertTrue(r.isReady)            // arama (FTS) yapılabilir
        XCTAssertFalse(r.needsSetup)
        XCTAssertEqual(r.item("vectors")?.status, .warn)
        XCTAssertEqual(r.overall, .warn)
    }

    func testPartialVectorCoverageWarns() {
        let r = HealthCheck.evaluate(input(indexed: 100, vectors: 50))
        XCTAssertEqual(r.item("vectors")?.status, .warn)
        XCTAssertTrue(r.item("vectors")?.detail.contains("50") ?? false)
    }

    // MARK: - Otomatik gömme nüansı (kısmi kapsam metni)

    /// Otomatik gömme AÇIK + sağlayıcı varken metin "kendiliğinden tamamlanır" der (elle Gömme değil).
    func testPartialCoverageWithAutoEmbedMentionsAutomatic() {
        let r = HealthCheck.evaluate(input(indexed: 100, vectors: 50, autoEmbed: true))
        let detail = r.item("vectors")?.detail ?? ""
        XCTAssertTrue(detail.contains("otomatik"))
        XCTAssertFalse(detail.contains("\"Gömme\" çalıştırın"))
    }

    /// Otomatik gömme KAPALIYSA klasik "Gömme çalıştırın" yönlendirmesi kalır.
    func testPartialCoverageWithoutAutoEmbedAsksManualEmbed() {
        let r = HealthCheck.evaluate(input(indexed: 100, vectors: 50, autoEmbed: false))
        XCTAssertTrue((r.item("vectors")?.detail ?? "").contains("\"Gömme\" çalıştırın"))
    }

    /// Ayar açık olsa da sağlayıcı yoksa otomatik gömme tamamlayamaz → elle Gömme yönlendirmesi kalır.
    func testPartialCoverageAutoEmbedButNoProviderAsksManualEmbed() {
        let r = HealthCheck.evaluate(input(indexed: 100, vectors: 50, embedder: false, autoEmbed: true))
        XCTAssertTrue((r.item("vectors")?.detail ?? "").contains("\"Gömme\" çalıştırın"))
    }

    func testFullCoverageIsOk() {
        let r = HealthCheck.evaluate(input(indexed: 100, vectors: 100))
        XCTAssertEqual(r.item("vectors")?.status, .ok)
    }

    func testNinetyPercentCoverageIsOk() {
        let r = HealthCheck.evaluate(input(indexed: 100, vectors: 90))
        XCTAssertEqual(r.item("vectors")?.status, .ok)
    }

    // MARK: - Sağlayıcılar

    func testMissingLLMKeyWarns() {
        let r = HealthCheck.evaluate(input(llm: false))
        XCTAssertEqual(r.item("llm")?.status, .warn)
    }

    func testLocalEmbedderWarns() {
        let r = HealthCheck.evaluate(input(local: true))
        XCTAssertEqual(r.item("embedder")?.status, .warn)
    }

    func testCloudEmbedderIsOk() {
        let r = HealthCheck.evaluate(input(local: false))
        XCTAssertEqual(r.item("embedder")?.status, .ok)
    }

    func testNoEmbedderConfiguredOmitsItem() {
        let r = HealthCheck.evaluate(input(embedder: false))
        XCTAssertNil(r.item("embedder"))
    }

    // MARK: - Tamamen kurulu

    func testFullyConfiguredIsAllOk() {
        let r = HealthCheck.evaluate(input())
        XCTAssertTrue(r.isReady)
        XCTAssertFalse(r.needsSetup)
        XCTAssertEqual(r.overall, .ok)
        XCTAssertTrue(r.items.allSatisfy { $0.status == .ok })
    }
}
