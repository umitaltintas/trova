import Foundation

public struct RankedEmail: Sendable {
    public let hit: SearchHit
    public let relevance: Double
    public let reason: String
}

public struct AgentAnswer: Sendable {
    public let summary: String
    public let ranked: [RankedEmail]
}

/// Doğal dil sorusunu yanıtlayan agent:
/// hibrit getir → LLM ile alakaya göre sırala + Türkçe özetle.
/// Getirme yalnızca iyi *recall* sağlar (FTS); nihai *alaka sıralaması* LLM'dedir,
/// bu da zayıf embedding'i telafi eder.
public struct MailAgent {
    let searcher: Searcher
    let llm: OpenRouterClient

    public init(store: IndexStore, embedder: EmbeddingProvider?, llm: OpenRouterClient) {
        self.searcher = Searcher(store: store, embedder: embedder)
        self.llm = llm
    }

    public func ask(_ question: String, candidateCount: Int = 30, topK: Int = 8) throws -> AgentAnswer {
        let candidates = try searcher.search(question, mode: .hybrid, limit: candidateCount)
        guard !candidates.isEmpty else {
            return AgentAnswer(summary: "Bu sorguyla eşleşen mail bulunamadı.", ranked: [])
        }
        let content = try llm.complete(messages: [
            .init(role: "system", content: Self.systemPrompt),
            .init(role: "user", content: Self.buildPrompt(question: question, candidates: candidates, topK: topK)),
        ])
        return try Self.parseAnswer(content, candidates: candidates)
    }

    static let systemPrompt = """
        Sen bir e-posta arama asistanısın. Sana kullanıcının sorusu ve numaralandırılmış \
        aday e-postalar verilir. Soruyla GERÇEKTEN alakalı olanları seç, alakaya göre sırala \
        ve Türkçe kısa bir özet yaz. Alakasız adayları dahil etme.
        SADECE şu şemada geçerli JSON döndür, başka hiçbir şey yazma:
        {"summary": "kısa Türkçe özet", "results": [{"ref": <numara>, "relevance": <0..1>, "reason": "<kısa gerekçe>"}]}
        """

    static func buildPrompt(question: String, candidates: [SearchHit], topK: Int) -> String {
        var lines = ["Soru: \(question)", "", "Aday e-postalar:"]
        for (index, hit) in candidates.enumerated() {
            let date = hit.date.map { ISO8601DateFormatter().string(from: $0) } ?? "?"
            let from = hit.fromName ?? hit.fromAddress ?? "?"
            lines.append("[\(index + 1)] Konu: \(hit.subject ?? "(yok)") | Kimden: \(from) | Tarih: \(date) | Kutu: \(hit.mailbox)")
            let snippet = hit.snippet.replacingOccurrences(of: "\n", with: " ")
            if !snippet.isEmpty { lines.append("    İçerik: \(String(snippet.prefix(300)))") }
        }
        lines.append("")
        lines.append("En alakalı en fazla \(topK) e-postayı 'ref' numarasıyla döndür.")
        return lines.joined(separator: "\n")
    }

    static func parseAnswer(_ content: String, candidates: [SearchHit]) throws -> AgentAnswer {
        let json = extractJSON(content)
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.badResponse(content)
        }
        let summary = (root["summary"] as? String) ?? ""
        let results = (root["results"] as? [[String: Any]]) ?? []

        var ranked: [RankedEmail] = []
        for item in results {
            guard let ref = (item["ref"] as? NSNumber)?.intValue, ref >= 1, ref <= candidates.count else { continue }
            let relevance = (item["relevance"] as? NSNumber)?.doubleValue ?? 0
            let reason = (item["reason"] as? String) ?? ""
            ranked.append(RankedEmail(hit: candidates[ref - 1], relevance: relevance, reason: reason))
        }
        ranked.sort { $0.relevance > $1.relevance }
        return AgentAnswer(summary: summary, ranked: ranked)
    }

    /// Model JSON'u ```fence``` veya açıklama metniyle sarabilir; ilk {…son } bloğunu çıkarır.
    static func extractJSON(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let open = s.firstIndex(of: "{"), let close = s.lastIndex(of: "}"), open < close else { return s }
        return String(s[open...close])
    }
}
