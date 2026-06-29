import Foundation

/// İlk aşama getirme sonuçlarını sorguya alaka düzeyine göre yeniden sıralayan servis.
public protocol Reranker: Sendable {
    /// `candidates` listesini `query`'ye göre alakaya göre yeniden sıralar; ilk `topK`'yı döndürür.
    func rerank(query: String, candidates: [SearchHit], topK: Int) throws -> [SearchHit]
}

/// RankGPT tarzı listwise LLM yeniden sıralayıcı.
/// Adayları numaralandırıp modele alaka sırasını sorar, dönen permütasyonu uygular.
/// Herhangi bir hata veya bozuk çıktıda adayları olduğu gibi (ilk `topK`) döndürür — asla çökmez.
public final class LLMReranker: Reranker, @unchecked Sendable {
    private let llm: OpenRouterClient
    private let snippetLimit: Int

    public init(llm: OpenRouterClient, snippetLimit: Int = 200) {
        self.llm = llm
        self.snippetLimit = snippetLimit
    }

    public func rerank(query: String, candidates: [SearchHit], topK: Int) throws -> [SearchHit] {
        // En az iki aday yoksa yeniden sıralamanın anlamı yok.
        guard candidates.count > 1 else { return Array(candidates.prefix(topK)) }

        let messages = [
            ChatMessage(role: "system", content: Self.systemPrompt),
            ChatMessage(role: "user", content: prompt(query: query, candidates: candidates)),
        ]

        // Ağ/çözümleme hatalarında sessizce ilk aşama sırasını koru (graceful).
        guard let raw = try? llm.complete(messages: messages) else {
            return Array(candidates.prefix(topK))
        }

        let order = Self.parseOrder(raw, count: candidates.count)
        guard !order.isEmpty else { return Array(candidates.prefix(topK)) }

        return Array(order.map { candidates[$0] }.prefix(topK))
    }

    /// Türkçe listwise istem: adayları numaralandırıp en alakalıdan en alakasıza sırasını ister.
    private func prompt(query: String, candidates: [SearchHit]) -> String {
        let items = candidates.enumerated().map { index, hit -> String in
            let subject = (hit.subject?.isEmpty == false ? hit.subject : nil) ?? "(konu yok)"
            let snippet = hit.snippet
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(snippetLimit)
            return "[\(index + 1)] Konu: \(subject)\n    Özet: \(snippet)"
        }.joined(separator: "\n")

        return """
            Sorgu: \(query)

            Adaylar:
            \(items)

            Yukarıdaki \(candidates.count) adayı sorguya alaka düzeyine göre EN ALAKALIDAN EN
            ALAKASIZA doğru sırala. YALNIZCA aday numaralarını virgülle ayırarak yaz (örn. 3,1,5,2).
            Başka hiçbir metin, açıklama veya gerekçe yazma.
            """
    }

    private static let systemPrompt =
        "Sen bir arama sonucu yeniden sıralayıcısısın. Verilen adayları sorguya alakaya göre "
        + "sıralar ve yalnızca virgülle ayrılmış aday numaralarını döndürürsün."

    /// Modelin döndürdüğü metinden 1 tabanlı numaraları SIRAYLA ayıklar; tekrarları ve
    /// aralık dışını eler, 0 tabanlı indekslere çevirir, sonra modelin atladığı adayları
    /// (özgün sıralarını koruyarak) sona ekler. Hiç geçerli numara yoksa boş dizi döner.
    static func parseOrder(_ text: String, count: Int) -> [Int] {
        var seen = Set<Int>()
        var order: [Int] = []
        var current = ""
        // Metni tarayıp ardışık rakam gruplarını sırayla aday numarası olarak topla.
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                appendNumber(current, count: count, seen: &seen, order: &order)
                current = ""
            }
        }
        if !current.isEmpty { appendNumber(current, count: count, seen: &seen, order: &order) }

        guard !order.isEmpty else { return [] }

        // Modelin atladığı adayları özgün sırayla sona ekle (hiçbir aday kaybolmasın).
        for index in 0..<count where !seen.contains(index) { order.append(index) }
        return order
    }

    private static func appendNumber(_ token: String, count: Int,
                                     seen: inout Set<Int>, order: inout [Int]) {
        guard let value = Int(token) else { return }
        let index = value - 1                       // 1 tabanlı → 0 tabanlı
        guard index >= 0, index < count, !seen.contains(index) else { return }
        seen.insert(index)
        order.append(index)
    }
}
