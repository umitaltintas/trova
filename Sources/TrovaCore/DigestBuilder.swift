import Foundation

/// Son gelen maillerden Türkçe, temaya göre gruplanmış kısa bir markdown brifing üretir.
/// Getirme (hangi mailler) çağırana aittir; burada yalnızca metin LLM ile yazılır.
public struct DigestBuilder {
    let llm: OpenRouterClient

    public init(llm: OpenRouterClient) { self.llm = llm }

    /// Verilen mailleri (konu + gönderen + tarih + kısa içerik) listeleyip LLM'den
    /// temaya göre gruplanmış, sonunda "Yapılacaklar / yanıt bekleyenler" bölümlü bir
    /// brifing ister. Mail yoksa LLM'e gitmeden dostça bir mesaj döndürür.
    public func build(_ hits: [SearchHit]) throws -> String {
        guard !hits.isEmpty else { return "Yeni mail yok." }
        return try llm.complete(messages: [
            .init(role: "system", content: Self.systemPrompt),
            .init(role: "user", content: Self.buildPrompt(hits)),
        ])
    }

    static let systemPrompt = """
        Sen bir e-posta asistanısın. Sana kullanıcının son gelen e-postaları verilir. \
        Bunları Türkçe, kısa ve okunması kolay bir markdown brifinge dönüştür. \
        E-postaları temaya/konuya göre grupla ve her grubu kısa bir başlıkla (##) ver. \
        Önemsiz veya otomatik bildirimleri tek satırda özetle, şişirme. \
        En sonda "## Yapılacaklar / yanıt bekleyenler" başlıklı, kullanıcının aksiyon \
        alması gereken maddeleri madde madde listeleyen kısa bir bölüm ekle. \
        Uydurma; yalnızca sana verilen bilgilere dayan.
        """

    static func buildPrompt(_ hits: [SearchHit]) -> String {
        var lines = ["Son gelen e-postalar:", ""]
        for hit in hits {
            let date = hit.date.map { ISO8601DateFormatter().string(from: $0) } ?? "?"
            let from = hit.fromName ?? hit.fromAddress ?? "?"
            lines.append("- Konu: \(hit.subject ?? "(konu yok)") | Kimden: \(from) | Tarih: \(date)")
            let snippet = hit.snippet.replacingOccurrences(of: "\n", with: " ")
            if !snippet.isEmpty { lines.append("  İçerik: \(String(snippet.prefix(160)))") }
        }
        lines.append("")
        lines.append("Yukarıdaki maillerden Türkçe bir günlük brifing yaz.")
        return lines.joined(separator: "\n")
    }
}
