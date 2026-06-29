import Foundation

/// Sıralı arama sonuçlarını thread (konuşma) bazında çeşitlendirir.
///
/// E-posta aramasına özgü bir sorun: aynı konuşmanın birbirine çok benzeyen
/// onlarca mesajı en üst sıraları tıkayıp farklı/ilgili başka konuşmaları aşağı
/// iter. Bu, MMR (Maximal Marginal Relevance) ailesinden, vektör gerektirmeyen
/// hafif bir çeşitlendirmedir: her thread'den en çok `maxPerThread` mesaj tutar,
/// üst sıradakileri koruyarak fazlalıkları atar ve daha derin havuzdan farklı
/// konuşmalarla doldurur.
public enum ResultDiversifier {
    /// - Parameters:
    ///   - hits: alaka sırasına göre dizili adaylar (genelde `limit`'ten geniş bir havuz).
    ///   - maxPerThread: aynı thread'den izin verilen en fazla sonuç (≥1).
    ///   - limit: döndürülecek sonuç sayısı.
    /// `threadKey`'i olmayan (boş/nil) sonuçlar her zaman benzersiz konuşma sayılır.
    public static func diversify(_ hits: [SearchHit], maxPerThread: Int, limit: Int) -> [SearchHit] {
        guard maxPerThread > 0 else { return Array(hits.prefix(limit)) }
        var counts: [String: Int] = [:]
        var result: [SearchHit] = []
        result.reserveCapacity(min(limit, hits.count))
        for hit in hits {
            if result.count >= limit { break }
            if let key = hit.threadKey, !key.isEmpty {
                let seen = counts[key, default: 0]
                if seen >= maxPerThread { continue }   // bu thread'den kota doldu, atla
                counts[key] = seen + 1
            }
            result.append(hit)
        }
        return result
    }
}
