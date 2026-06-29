import Foundation

public enum SearchMode: String, Sendable, CaseIterable {
    case fts        // sadece tam metin (anahtar kelime)
    case semantic   // sadece anlamsal (vektör)
    case hybrid     // ikisinin RRF ile birleşimi
}

/// FTS5 ve vektör aramasını birleştiren arama servisi.
public struct Searcher {
    let store: IndexStore
    let embedder: EmbeddingProvider?
    let reranker: Reranker?

    public init(store: IndexStore, embedder: EmbeddingProvider? = nil,
                reranker: Reranker? = nil) {
        self.store = store
        self.embedder = embedder
        self.reranker = reranker
    }

    public func search(_ query: String, mode: SearchMode,
                       filter: SearchFilter = .init(), limit: Int) throws -> [SearchHit] {
        let allowed = filter.isEmpty ? nil : try store.idsMatching(filter)
        // Yeniden sıralayıcı varsa daha geniş bir aday havuzu çek; yoksa davranış aynen korunur.
        let pool = reranker == nil ? limit : max(limit, 40)
        switch mode {
        case .fts:
            // Kelime araması yeniden sıralanmaz.
            return try store.search(query: query, filter: filter, limit: limit)

        case .semantic:
            guard let embedder else { return try store.search(query: query, filter: filter, limit: limit) }
            let ranked = try store.vectorSearch(query: try embedder.embed(query),
                                                limit: pool, allowedIDs: allowed)
            let meta = try store.hits(forIDs: ranked.map(\.id))
            let hits = ranked.compactMap { hit in
                meta[hit.id].map { withScore($0, Double(hit.score)) }
            }
            return try reranked(query, hits, limit: limit)

        case .hybrid:
            guard let embedder else { return try store.search(query: query, filter: filter, limit: limit) }
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
            return try reranked(query, hits, limit: limit)
        }
    }

    /// Yeniden sıralayıcı varsa adayları LLM ile yeniden sıralar; yoksa olduğu gibi döndürür.
    private func reranked(_ query: String, _ hits: [SearchHit], limit: Int) throws -> [SearchHit] {
        guard let reranker else { return hits }
        return try reranker.rerank(query: query, candidates: hits, topK: limit)
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
