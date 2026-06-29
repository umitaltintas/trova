import Foundation

/// Uzun metni örtüşmeli parçalara böler (gömme token sınırını aşan mailler için).
public enum TextChunker {
    public static func chunks(_ text: String, size: Int = 1500, overlap: Int = 200,
                              maxChunks: Int = 6) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > size else { return [trimmed] }

        let chars = Array(trimmed)
        var result: [String] = []
        var start = 0
        while start < chars.count, result.count < maxChunks {
            let end = Swift.min(start + size, chars.count)
            result.append(String(chars[start..<end]))
            if end == chars.count { break }
            start = end - overlap
        }
        return result
    }
}

/// Eksik mailleri gömer. Uzun mailler parçalanır, parça vektörleri ortalanır.
/// Tüm parçalar (mesajlar arası) tek `embedBatch` çağrısında gönderilir → API verimliliği korunur.
public enum EmbeddingRunner {
    @discardableResult
    public static func run(
        store: IndexStore,
        embedder: EmbeddingProvider,
        messageBatch: Int = 48,
        cancel: CancellationFlag? = nil,
        progress: ((_ processed: Int, _ total: Int) -> Void)? = nil
    ) throws -> Int {
        let pending = try store.messagesMissingVectors()
        let total = pending.count
        var processed = 0

        for group in pending.chunkedInto(messageBatch) {
            if cancel?.isCancelled == true { break }

            // Düz parça listesi + her mesajın parça aralığı.
            var chunkTexts: [String] = []
            var spans: [(id: String, range: Range<Int>)] = []
            for item in group {
                let pieces = TextChunker.chunks(item.text)
                let start = chunkTexts.count
                chunkTexts.append(contentsOf: pieces.isEmpty ? [" "] : pieces)
                spans.append((item.id, start..<chunkTexts.count))
            }

            let vectors = try embedder.embedBatch(chunkTexts)
            let records = spans.map { span in
                (id: span.id, vector: averageNormalized(Array(vectors[span.range])))
            }
            try store.upsertVectors(records)

            processed += group.count
            progress?(processed, total)
        }
        return processed
    }

    /// Parça vektörlerinin ortalamasını alıp L2 normalize eder (kosinüs için).
    static func averageNormalized(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        guard vectors.count > 1 else { return first }

        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors where vector.count == sum.count {
            for i in sum.indices { sum[i] += vector[i] }
        }
        var norm: Float = 0
        for value in sum { norm += value * value }
        norm = norm.squareRoot()
        if norm > 0 { for i in sum.indices { sum[i] /= norm } }
        return sum
    }
}

private extension Array {
    func chunkedInto(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: Swift.max(1, size)).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
