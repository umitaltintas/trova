import Foundation

/// Bir e-posta konusunun (thread) tek mesajı — özetleyiciye verilen girdi.
public struct ThreadEntry: Sendable, Equatable {
    public let from: String?
    public let date: Date?
    public let body: String
    public init(from: String?, date: Date?, body: String) {
        self.from = from; self.date = date; self.body = body
    }
}

/// Bir e-posta konusunun tüm mesajlarını LLM ile Türkçe, kısa bir markdown özetine dönüştürür
/// (ne hakkında, alınan kararlar, yapılacaklar). Getirme (hangi mesajlar/gövdeler) çağırana aittir.
public struct ThreadSummarizer {
    let llm: OpenRouterClient

    public init(llm: OpenRouterClient) { self.llm = llm }

    public func summarize(_ entries: [ThreadEntry]) throws -> String {
        guard !entries.isEmpty else { return "Özetlenecek mesaj yok." }
        return try llm.complete(messages: [
            .init(role: "system", content: Self.systemPrompt),
            .init(role: "user", content: Self.buildPrompt(entries)),
        ])
    }

    static let systemPrompt = """
        Sen bir e-posta asistanısın. Sana tek bir e-posta KONUSUNUN (thread) mesajları \
        eskiden yeniye sırayla verilir. Bunları Türkçe, kısa bir markdown özetine dönüştür: \
        konunun ne hakkında olduğu, alınan/önemli kararlar ve varsa yapılacaklar. \
        En fazla birkaç madde; şişirme, tekrar etme. Yalnızca verilen bilgilere dayan, uydurma.
        """

    static func buildPrompt(_ entries: [ThreadEntry]) -> String {
        var lines = ["Konu mesajları (eskiden yeniye):", ""]
        for (i, entry) in entries.enumerated() {
            let date = entry.date.map { ISO8601DateFormatter().string(from: $0) } ?? "?"
            lines.append("[\(i + 1)] Kimden: \(entry.from ?? "?") | Tarih: \(date)")
            let body = entry.body
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            lines.append(body.isEmpty ? "  (boş)" : "  \(String(body.prefix(800)))")
        }
        lines.append("")
        lines.append("Bu konuyu Türkçe, kısa bir markdown özetiyle anlat.")
        return lines.joined(separator: "\n")
    }
}
