import Foundation

public enum SearchMode: String, Sendable, CaseIterable {
    case fts        // sadece tam metin (anahtar kelime)
    case semantic   // sadece anlamsal (vektör)
    case hybrid     // ikisinin RRF ile birleşimi
}

/// FTS5 ve vektör aramasını birleştiren arama servisi.
public struct Searcher: Sendable {
    let store: IndexStore
    let embedder: EmbeddingProvider?
    let reranker: Reranker?
    /// Thread başına en fazla sonuç (çeşitlendirme). nil → çeşitlendirme kapalı (davranış aynı).
    let maxPerThread: Int?

    public init(store: IndexStore, embedder: EmbeddingProvider? = nil,
                reranker: Reranker? = nil, maxPerThread: Int? = nil) {
        self.store = store
        self.embedder = embedder
        self.reranker = reranker
        self.maxPerThread = maxPerThread
    }

    public func search(_ query: String, mode: SearchMode,
                       filter: SearchFilter = .init(), limit: Int) throws -> [SearchHit] {
        let allowed = filter.isEmpty ? nil : try store.idsMatching(filter)
        // Rerank ya da çeşitlendirme açıksa daha geniş bir aday havuzu çek (araştırma: havuz
        // derinliği sıralamada belirleyici, ~50-100 aralığı). İkisi de kapalıysa davranış aynen korunur.
        let wantPool = reranker != nil || maxPerThread != nil
        let pool = wantPool ? max(limit, 60) : limit
        switch mode {
        case .fts:
            // Kelime araması yeniden sıralanmaz; çeşitlendirme için yine de derin havuz çekilir.
            let hits = try store.search(query: query, filter: filter, limit: pool)
            return finalize(hits, limit: limit)

        case .semantic:
            guard let embedder else {
                return finalize(try store.search(query: query, filter: filter, limit: pool), limit: limit)
            }
            let ranked = try store.vectorSearch(query: try embedder.embed(query),
                                                limit: pool, allowedIDs: allowed)
            let meta = try store.hits(forIDs: ranked.map(\.id))
            let hits = ranked.compactMap { hit in
                meta[hit.id].map { withScore($0, Double(hit.score)) }
            }
            return finalize(try rerankedPool(query, hits, pool: pool), limit: limit)

        case .hybrid:
            guard let embedder else {
                return finalize(try store.search(query: query, filter: filter, limit: pool), limit: limit)
            }
            let ftsHits = try store.search(query: query, filter: filter, limit: max(pool, 50))
            let vecHits = try store.vectorSearch(query: try embedder.embed(query),
                                                 limit: max(pool, 50), allowedIDs: allowed)

            let fused = RRF.fuse([ftsHits.map(\.id), vecHits.map(\.id)])
            let topIDs = Array(fused.prefix(pool)).map(\.id)
            let meta = try store.hits(forIDs: topIDs)
            // Vurgulu parçayı (snippet) FTS sonucundan al; yoksa kayıttaki snippet'i kullan.
            let ftsSnippet = Dictionary(ftsHits.map { ($0.id, $0.snippet) }, uniquingKeysWith: { a, _ in a })

            let hits = fused.prefix(pool).compactMap { item -> SearchHit? in
                guard let m = meta[item.id] else { return nil }
                let snippet = ftsSnippet[item.id].flatMap { $0.isEmpty ? nil : $0 } ?? m.snippet
                return SearchHit(
                    id: m.id, subject: m.subject, fromName: m.fromName, fromAddress: m.fromAddress,
                    mailbox: m.mailbox, date: m.date, snippet: snippet, score: item.score,
                    threadKey: m.threadKey, attachments: m.attachments)
            }
            return finalize(try rerankedPool(query, hits, pool: pool), limit: limit)
        }
    }

    /// Yeniden sıralayıcı varsa havuzun tamamını LLM ile yeniden sıralar (çeşitlendirme için
    /// `limit` yerine `pool` döner); yoksa olduğu gibi bırakır.
    private func rerankedPool(_ query: String, _ hits: [SearchHit], pool: Int) throws -> [SearchHit] {
        guard let reranker else { return hits }
        return try reranker.rerank(query: query, candidates: hits, topK: pool)
    }

    /// Sıralı havuzu son hâline indirger: çeşitlendirme açıksa thread bazında çeşitlendirir,
    /// değilse ilk `limit` sonucu döndürür.
    private func finalize(_ hits: [SearchHit], limit: Int) -> [SearchHit] {
        if let maxPerThread {
            return ResultDiversifier.diversify(hits, maxPerThread: maxPerThread, limit: limit)
        }
        return Array(hits.prefix(limit))
    }

    private func withScore(_ hit: SearchHit, _ score: Double) -> SearchHit {
        SearchHit(id: hit.id, subject: hit.subject, fromName: hit.fromName,
                  fromAddress: hit.fromAddress, mailbox: hit.mailbox, date: hit.date,
                  snippet: hit.snippet, score: score,
                  threadKey: hit.threadKey, attachments: hit.attachments)
    }
}

/// Reciprocal Rank Fusion: sıralı listeleri skor normalizasyonu olmadan birleştirir.
/// Yalnızca sıra konumuna bakar, bu yüzden bm25 ile kosinüs gibi farklı ölçekli
/// skorları güvenle harmanlar.
public enum RRF {
    public static func fuse(_ rankings: [[String]], k: Double = 60) -> [(id: String, score: Double)] {
        var scores: [String: Double] = [:]
        for ranking in rankings {
            for (index, id) in ranking.enumerated() {
                scores[id, default: 0] += 1.0 / (k + Double(index + 1))
            }
        }
        return scores.sorted { $0.value > $1.value }.map { (id: $0.key, score: $0.value) }
    }
}
