import Foundation

/// Dışa aktarılacak bir sohbet turu (soru + yanıt + kaynak mailler).
public struct ExportedTurn: Sendable {
    public let question: String
    public let answer: String
    public let citations: [SearchHit]
    public init(question: String, answer: String, citations: [SearchHit] = []) {
        self.question = question; self.answer = answer; self.citations = citations
    }
}

/// Arama/AI çıktısını paylaşılabilir Markdown metnine dönüştürür (panoya kopyalama veya .md kaydı için).
/// Saf metin üretimi — yan etkisiz, test edilebilir.
public enum MarkdownExporter {

    /// AI yanıtını soru + yanıt + kaynak mailler olarak Markdown'a döker.
    /// Kaynak yoksa "Kaynaklar" bölümü atlanır.
    public static func answer(question: String, answer: String, citations: [SearchHit]) -> String {
        var out = "# \(trimmedOrPlaceholder(question, "Soru"))\n\n"
        out += "\(answer.trimmingCharacters(in: .whitespacesAndNewlines))\n"

        if !citations.isEmpty {
            out += "\n## Kaynaklar\n\n"
            for (i, hit) in citations.enumerated() {
                out += "\(i + 1). \(citationLine(hit))\n"
            }
        }
        out += "\n---\n_Trova ile dışa aktarıldı_\n"
        return out
    }

    /// Tüm bir "Sor" sohbetini (soru/yanıt/kaynak turları) tek bir Markdown belgesine döker.
    public static func conversation(_ turns: [ExportedTurn], title: String = "Trova sohbeti") -> String {
        guard !turns.isEmpty else { return "# \(title)\n\n_(boş sohbet)_\n" }
        var out = "# \(title)\n"
        for (i, turn) in turns.enumerated() {
            out += "\n## \(i + 1). \(trimmedOrPlaceholder(turn.question, "Soru"))\n\n"
            out += "\(turn.answer.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            if !turn.citations.isEmpty {
                out += "\n**Kaynaklar:**\n"
                for hit in turn.citations { out += "- \(citationLine(hit))\n" }
            }
        }
        out += "\n---\n_Trova ile dışa aktarıldı_\n"
        return out
    }

    /// Tek bir maili başlık + üstbilgi + gövde olarak Markdown'a döker.
    public static func email(_ hit: SearchHit, body: String?) -> String {
        var out = "# \(trimmedOrPlaceholder(hit.subject ?? "", "(konu yok)"))\n\n"

        let sender = displaySender(hit)
        out += "**Gönderen:** \(sender)\n"
        if let date = formatted(hit.date) { out += "**Tarih:** \(date)\n" }
        out += "**Kutu:** \(hit.mailbox)\n"
        if !hit.attachments.isEmpty {
            out += "**Ekler:** \(hit.attachments.joined(separator: ", "))\n"
        }

        let text = (body?.isEmpty == false ? body! : hit.snippet)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        out += "\n---\n\n\(text)\n"
        return out
    }

    // MARK: - Yardımcılar

    private static func citationLine(_ hit: SearchHit) -> String {
        var parts = ["**\(trimmedOrPlaceholder(hit.subject ?? "", "(konu yok)"))**"]
        parts.append(displaySender(hit))
        if let date = formatted(hit.date) { parts.append(date) }
        parts.append("`\(hit.mailbox)`")
        return parts.joined(separator: " · ")
    }

    private static func displaySender(_ hit: SearchHit) -> String {
        if let name = hit.fromName, !name.isEmpty {
            if let addr = hit.fromAddress, !addr.isEmpty { return "\(name) <\(addr)>" }
            return name
        }
        if let addr = hit.fromAddress, !addr.isEmpty { return addr }
        return "Bilinmeyen gönderen"
    }

    private static func formatted(_ date: Date?) -> String? {
        date?.formatted(date: .abbreviated, time: .shortened)
    }

    private static func trimmedOrPlaceholder(_ s: String, _ placeholder: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? placeholder : t
    }
}
