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

/// Apple'ın yerleşik çok dilli `NLContextualEmbedding` modeliyle (512-d, offline,
/// Türkçe destekli) gömme üretir. Token vektörleri ortalanıp L2 normalize edilir;
/// böylece nokta çarpımı doğrudan kosinüs benzerliğini verir.
public final class LocalEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    public enum Failure: Error { case modelUnavailable }

    private let embedding: NLContextualEmbedding
    private let language: NLLanguage
    private let lock = NSLock()   // NLContextualEmbedding iş parçacığı-güvenli değil
    public let dimension: Int

    public init(language: NLLanguage = .turkish) throws {
        guard let model = NLContextualEmbedding(language: language),
              model.hasAvailableAssets else {
            throw Failure.modelUnavailable
        }
        try model.load()
        self.embedding = model
        self.language = language
        self.dimension = model.dimension
    }

    public func embed(_ text: String) throws -> [Float] {
        let input = String(text.prefix(2000))   // ~512 token sınırı için kırp
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [Float](repeating: 0, count: dimension)
        }

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
        guard count > 0 else { return sum }

        var norm: Float = 0
        for i in sum.indices { sum[i] /= Float(count); norm += sum[i] * sum[i] }
        norm = norm.squareRoot()
        if norm > 0 { for i in sum.indices { sum[i] /= norm } }
        return sum
    }
}
