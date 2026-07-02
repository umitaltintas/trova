import XCTest
@testable import TrovaCore

/// Cihaz-üstü `NLContextualEmbedding` tabanlı yerel gömme sağlayıcısının çekirdek
/// sözleşmesini doğrular: boyut > 0, L2 normalizasyon (~1.0), aynı girdi → aynı vektör
/// (deterministik) ve anlamsal olarak benzer iki Türkçe cümlenin kosinüs benzerliğinin
/// alakasız bir çiftten belirgin yüksek olması.
///
/// Model varlıkları (bir kerelik indirme) test ortamında yoksa test ATLANIR — burada
/// `requestAssets` ÇAĞRILMAZ (ağ/indirme yok, asılı kalma yok); yalnız yapıcı denenir.
final class ContextualEmbedderTests: XCTestCase {

    private func makeProvider() throws -> LocalEmbeddingProvider {
        do { return try LocalEmbeddingProvider() }
        catch { throw XCTSkip("Yerel gömme modeli varlıkları yok: \(error.localizedDescription)") }
    }

    /// İki L2-normalize vektörün kosinüs benzerliği = nokta çarpımı.
    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        XCTAssertEqual(a.count, b.count)
        return zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    func testDimensionIsPositive() throws {
        let provider = try makeProvider()
        XCTAssertGreaterThan(provider.dimension, 0)
    }

    func testVectorIsL2Normalized() throws {
        let provider = try makeProvider()
        let v = try provider.embed("Bugün hava çok güzel, dışarı çıkalım.")
        XCTAssertEqual(v.count, provider.dimension)
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        XCTAssertEqual(norm, 1.0, accuracy: 1e-3, "L2 norm ~1.0 olmalı, oldu: \(norm)")
    }

    func testDeterministic() throws {
        let provider = try makeProvider()
        let text = "Fatura son ödeme tarihi bu hafta doluyor."
        let a = try provider.embed(text)
        let b = try provider.embed(text)
        XCTAssertEqual(a, b, "Aynı girdi aynı vektörü vermeli (deterministik).")
    }

    func testSimilarSentencesRankAboveUnrelated() throws {
        let provider = try makeProvider()
        // Aynı fikri farklı sözcüklerle anlatan iki cümle (benzer) vs. tamamen farklı konu (alakasız).
        let a = try provider.embed("Yarınki toplantı saat üçte başlayacak.")
        let b = try provider.embed("Görüşmemiz yarın öğleden sonra üçte yapılacak.")
        let c = try provider.embed("Kızarmış patates için patatesleri ince ince dilimleyin.")

        let related = cosine(a, b)
        let unrelated = cosine(a, c)
        XCTAssertGreaterThan(related, unrelated,
            "Benzer çift (\(related)) alakasız çiftten (\(unrelated)) yüksek olmalı.")
    }

    /// Modelin token sınırını aşacak kadar uzun (parçalamayı tetikleyen) bir metnin gömmesi de
    /// boyut olarak doğru ve L2 normalize (~1.0) olmalıdır — çok parçalı ağırlıklı ortalama yolu.
    func testLongTextEmbeddingIsNormalized() throws {
        let provider = try makeProvider()
        let long = Self.longTurkishText
        XCTAssertGreaterThan(WordChunker.chunks(long).count, 1,
            "Test metni birden çok parçaya bölünmeli (parçalama yolu tetiklenmeli).")

        let v = try provider.embed(long)
        XCTAssertEqual(v.count, provider.dimension)
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        XCTAssertEqual(norm, 1.0, accuracy: 1e-3, "L2 norm ~1.0 olmalı, oldu: \(norm)")
    }

    /// Uzun bir metnin (çok parçalı) gömmesi, kendi ilk parçasının gömmesine, alakasız bir
    /// metinden belirgin biçimde daha yakın olmalı — parçalama anlamı korur, bozmaz.
    func testLongTextCloserToOwnFirstChunkThanUnrelated() throws {
        let provider = try makeProvider()
        let long = Self.longTurkishText
        let pieces = WordChunker.chunks(long)
        XCTAssertGreaterThan(pieces.count, 1)

        let whole = try provider.embed(long)
        let firstChunk = try provider.embed(pieces[0])
        let unrelated = try provider.embed(
            "Kızarmış patates için patatesleri ince ince dilimleyin, tuzlayıp kızgın yağda kızartın.")

        let ownChunk = cosine(whole, firstChunk)
        let toUnrelated = cosine(whole, unrelated)
        XCTAssertGreaterThan(ownChunk, toUnrelated,
            "Uzun metin kendi ilk parçasına (\(ownChunk)) alakasızdan (\(toUnrelated)) yakın olmalı.")
    }

    /// Parçalamayı tetiklemeye yetecek (>120 kelime) tutarlı Türkçe metin: aynı konulu bir
    /// paragrafın birkaç kez tekrarı — hem sınırı aşar hem de ilk parçayla konu bütünlüğü taşır.
    private static let longTurkishText: String = {
        let paragraph = """
        Bu hafta yürüttüğümüz proje toplantısında ekip üyeleri yol haritasını gözden geçirdi ve \
        önümüzdeki çeyrek için öncelikleri belirledi. Mühendisler yeni arama özelliğinin performansını \
        ölçtü, tasarımcılar kullanıcı arayüzü taslaklarını sundu, proje yöneticisi ise teslim tarihlerini \
        ve olası riskleri paylaştı. Toplantı sonunda herkesin görev listesi güncellendi ve bir sonraki \
        değerlendirme için ortak bir takvim oluşturuldu.
        """
        return Array(repeating: paragraph, count: 4).joined(separator: " ")
    }()
}
