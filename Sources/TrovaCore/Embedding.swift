import Foundation
import NaturalLanguage

/// Metni sabit boyutlu bir vektöre gömen sağlayıcı. Yerel model ile API tabanlı
/// (OpenAI/Voyage) sağlayıcı arasında geçişi soyutlar.
public protocol EmbeddingProvider: Sendable {
    var dimension: Int { get }
    func embed(_ text: String) throws -> [Float]
    /// Toplu gömme. API sağlayıcıları için tek istekte çok metin → büyük hız kazancı.
    func embedBatch(_ texts: [String]) throws -> [[Float]]
}

public extension EmbeddingProvider {
    func embedBatch(_ texts: [String]) throws -> [[Float]] {
        try texts.map { try embed($0) }   // varsayılan: tek tek (yerel model için yeterli)
    }
}

/// Apple'ın yerleşik çok dilli `NLContextualEmbedding` modeliyle (offline, anahtarsız)
/// gömme üretir. `.turkish` dili, hem Türkçe hem İngilizceyi kapsayan Latin-yazımlı çok
/// dilli modele çözülür (mailler karışık dilli); model kimliğini/boyutunu değiştirmemek
/// için bilerek dil-bazlı kurucu korunur (bkz. VectorMath / message_vector boyut filtresi).
/// Token vektörleri ortalanıp (mean-pool) L2 normalize edilir; böylece nokta çarpımı
/// doğrudan kosinüs benzerliğini verir. Boyut çalışma zamanında modelden alınır. Modelin
/// token sınırını (~256) aşan uzun metin, `WordChunker` ile kelime bazlı parçalanır; parça
/// vektörleri token sayısıyla ağırlıklı ortalanıp yeniden normalize edilir (kuyruk kaybolmaz).
public final class LocalEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    public enum Failure: Error, LocalizedError {
        case modelUnavailable   // bu macOS/dil için model hiç kurulamıyor
        case assetsUnavailable  // model var ama cihaz-üstü varlıklar (bir kerelik indirme) yok
        case downloadFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelUnavailable:
                return "Yerel gömme modeli bu sistemde kullanılamıyor."
            case .assetsUnavailable:
                return "Yerel gömme modeli varlıkları indirilmemiş. Ayarlar › Embedding'den "
                     + "\"Yerel model varlıklarını indir\" ile bir kerelik indirin."
            case let .downloadFailed(message):
                return "Yerel gömme modeli varlıkları indirilemedi: \(message)"
            }
        }
    }

    private let embedding: NLContextualEmbedding
    private let language: NLLanguage
    private let lock = NSLock()   // NLContextualEmbedding iş parçacığı-güvenli değil
    public let dimension: Int

    public init(language: NLLanguage = .turkish) throws {
        guard let model = NLContextualEmbedding(language: language) else {
            throw Failure.modelUnavailable
        }
        guard model.hasAvailableAssets else {
            throw Failure.assetsUnavailable
        }
        try model.load()
        self.embedding = model
        self.language = language
        self.dimension = model.dimension
    }

    /// Yerel model varlıkları (bir kerelik indirme) cihazda hazır mı — ağ/indirme YAPMAZ.
    /// UI'da "indir" düğmesini göstermek ve teşhis için kullanılır.
    public static func assetsAvailable(language: NLLanguage = .turkish) -> Bool {
        NLContextualEmbedding(language: language)?.hasAvailableAssets ?? false
    }

    /// Yerel model varlıklarını (yoksa) indirir. Bir kere, küçük, anahtarsız. Zaten varsa
    /// hemen döner. `requestAssets()` async'tir ve tamamlanana dek bekler; çevrimdışıysa/
    /// varlık yoksa/hata olursa anlaşılır bir `Failure` atar.
    public static func downloadAssets(language: NLLanguage = .turkish) async throws {
        guard let model = NLContextualEmbedding(language: language) else {
            throw Failure.modelUnavailable
        }
        if model.hasAvailableAssets { return }
        do {
            switch try await model.requestAssets() {
            case .available:    return
            case .notAvailable: throw Failure.downloadFailed("bu cihaz için varlık yok")
            case .error:        throw Failure.downloadFailed("indirme hatası")
            @unknown default:   throw Failure.downloadFailed("beklenmeyen durum")
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.downloadFailed(error.localizedDescription)
        }
    }

    public func embed(_ text: String) throws -> [Float] {
        // Metni token sınırına saygıyla kelime bazlı parçala (bkz. WordChunker). Eskiden
        // `prefix(2000)` ile karakter bazlı kırpılıyordu; 2000 karakter Türkçe'de 256 token'ı
        // aştığından uzun maillerin kuyruğu sessizce düşüyordu.
        let pieces = WordChunker.chunks(text)
        guard !pieces.isEmpty else {
            return [Float](repeating: 0, count: dimension)   // boş / yalnız boşluk metin
        }

        // Tek parça: mevcut mean-pool yoluyla birebir aynı sonuç (regresyon yok).
        if pieces.count == 1 {
            return try embedChunk(pieces[0]).vector
        }

        // Çok parça: her parçayı ayrı göm, parça vektörlerini modelin ürettiği token sayısıyla
        // ağırlıklı ortala (daha uzun parça daha çok ağırlık), sonucu L2 normalize et. Böylece
        // sonuç, tüm metni tek seferde gömmenin mean-pool'una yaklaşırken boyut 512 kalır.
        var accumulator = [Float](repeating: 0, count: dimension)
        var weightSum: Float = 0
        for piece in pieces {
            let (vector, tokens) = try embedChunk(piece)
            guard tokens > 0 else { continue }
            let weight = Float(tokens)
            for i in accumulator.indices { accumulator[i] += weight * vector[i] }
            weightSum += weight
        }
        guard weightSum > 0 else { return accumulator }

        var norm: Float = 0
        for value in accumulator { norm += value * value }
        norm = norm.squareRoot()
        if norm > 0 { for i in accumulator.indices { accumulator[i] /= norm } }
        return accumulator
    }

    /// Token sınırına sığan tek bir parçayı gömer: token vektörlerini ortalar (mean-pool) ve
    /// L2 normalize eder. Dönüş: (normalize vektör, ortalamaya giren token sayısı). Token sayısı
    /// çok parçalı gömmede ağırlık olarak kullanılır. Girdi boşsa sıfır vektör + 0 token döner.
    private func embedChunk(_ input: String) throws -> (vector: [Float], tokens: Int) {
        lock.lock()
        defer { lock.unlock() }

        let result = try embedding.embeddingResult(for: input, language: language)
        var sum = [Float](repeating: 0, count: dimension)
        var count = 0
        result.enumerateTokenVectors(in: input.startIndex..<input.endIndex) { vector, _ in
            for i in 0..<min(vector.count, sum.count) { sum[i] += Float(vector[i]) }
            count += 1
            return true
        }
        guard count > 0 else { return (sum, 0) }

        var norm: Float = 0
        for i in sum.indices { sum[i] /= Float(count); norm += sum[i] * sum[i] }
        norm = norm.squareRoot()
        if norm > 0 { for i in sum.indices { sum[i] /= norm } }
        return (sum, count)
    }
}
