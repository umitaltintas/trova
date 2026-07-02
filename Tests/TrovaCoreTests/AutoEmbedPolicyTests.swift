import XCTest
@testable import TrovaCore

final class AutoEmbedPolicyTests: XCTestCase {

    /// Sağlayıcı kurulamıyorsa (yerel varlık yok VE bulut anahtarı yok) hiçbir şey gömülmez.
    func testNoProviderReturnsZero() {
        XCTAssertEqual(AutoEmbedPolicy.batchSize(providerAvailable: false, enabled: true,
                                                 missingCount: 500, batchLimit: 400), 0)
    }

    /// Ayar kapalıysa (kullanıcı otomatik gömmeyi kapatmış) hiçbir şey gömülmez.
    func testDisabledReturnsZero() {
        XCTAssertEqual(AutoEmbedPolicy.batchSize(providerAvailable: true, enabled: false,
                                                 missingCount: 500, batchLimit: 400), 0)
    }

    /// Eksik mail yoksa (kapsam zaten tam) gömülecek bir şey yoktur.
    func testNoMissingReturnsZero() {
        XCTAssertEqual(AutoEmbedPolicy.batchSize(providerAvailable: true, enabled: true,
                                                 missingCount: 0, batchLimit: 400), 0)
    }

    /// Eksik sayı parti sınırını aşıyorsa yalnız sınır kadar gömülür (kalanı sonraki dalgaya).
    func testMissingAboveLimitReturnsLimit() {
        XCTAssertEqual(AutoEmbedPolicy.batchSize(providerAvailable: true, enabled: true,
                                                 missingCount: 1000, batchLimit: 400), 400)
    }

    /// Eksik sayı parti sınırının altındaysa hepsi tek dalgada gömülür.
    func testMissingBelowLimitReturnsAll() {
        XCTAssertEqual(AutoEmbedPolicy.batchSize(providerAvailable: true, enabled: true,
                                                 missingCount: 120, batchLimit: 400), 120)
    }

    /// Eksik sayı tam sınıra eşitse sınır kadar (tam) döner.
    func testMissingEqualsLimitReturnsLimit() {
        XCTAssertEqual(AutoEmbedPolicy.batchSize(providerAvailable: true, enabled: true,
                                                 missingCount: 400, batchLimit: 400), 400)
    }

    /// Savunmacı: geçersiz (0/negatif) parti sınırı iş yaptırmaz (sonsuz/anlamsız döngü olmasın).
    func testNonPositiveLimitReturnsZero() {
        XCTAssertEqual(AutoEmbedPolicy.batchSize(providerAvailable: true, enabled: true,
                                                 missingCount: 500, batchLimit: 0), 0)
        XCTAssertEqual(AutoEmbedPolicy.batchSize(providerAvailable: true, enabled: true,
                                                 missingCount: 500, batchLimit: -10), 0)
    }
}
