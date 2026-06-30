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

/// "Bugün" brifingindeki tek bir triyaj maddesi (gönderen + konu + yaş etiketi).
/// `ageLabel` boşsa dışa aktarımda parantezli yaş bölümü gösterilmez.
public struct DigestItem: Equatable, Sendable {
    public let from: String
    public let subject: String
    public let ageLabel: String
    public init(from: String, subject: String, ageLabel: String) {
        self.from = from; self.subject = subject; self.ageLabel = ageLabel
    }
}

/// Dışa aktarılacak bir mail listesi maddesi (gönderen + konu + tarih etiketi + opsiyonel kutu).
/// Arama sonuçları, bir kişinin mailleri ve "Benzer mailler" listeleri için ortak madde tipi.
/// `mailbox` nil (veya boş) ise dışa aktarımda kutu bölümü ( · <kutu>) gösterilmez.
public struct ExportedListItem: Equatable, Sendable {
    public let from: String
    public let subject: String
    public let dateLabel: String
    public let mailbox: String?
    public init(from: String, subject: String, dateLabel: String, mailbox: String? = nil) {
        self.from = from; self.subject = subject; self.dateLabel = dateLabel; self.mailbox = mailbox
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

    /// "Bugün" brifingini başlık + brifing metni + iki triyaj bölümü olarak Markdown'a döker.
    /// Brifing boşsa atlanır ama başlık yine üretilir. Listeler boşsa bölüm yine yazılır
    /// ve `_(yok)_` satırı eklenir (bölümler tutarlı kalsın).
    public static func digest(title: String, briefing: String,
                              needsReply: [DigestItem], waitingOn: [DigestItem]) -> String {
        var out = "# \(trimmedOrPlaceholder(title, "Bugün"))\n"
        let brief = briefing.trimmingCharacters(in: .whitespacesAndNewlines)
        if !brief.isEmpty { out += "\n\(brief)\n" }
        out += digestSection("Yanıt gerekiyor", needsReply)
        out += digestSection("Yanıt bekliyor", waitingOn)
        out += "\n---\n_Trova ile dışa aktarıldı_\n"
        return out
    }

    /// Bir mail listesini (arama sonuçları / kişi mailleri / benzer mailler) başlık + madde sayısı +
    /// maddelere döker. Her madde: `- **<gönderen>** — <konu>` ardından alt satırda tarih etiketi
    /// (kutu varsa ` · <kutu>`). Liste boşsa başlık altına `_(kayıt yok)_` yazılır (altbilgi atlanır).
    public static func emailList(title: String, items: [ExportedListItem]) -> String {
        let heading = trimmedOrPlaceholder(title, "Liste")
        guard !items.isEmpty else { return "# \(heading)\n\n_(kayıt yok)_\n" }
        var out = "# \(heading)\n\n_\(items.count) kayıt_\n\n"
        out += items.map(listLine).joined(separator: "\n\n")
        out += "\n\n---\n_Trova ile dışa aktarıldı_\n"
        return out
    }

    // MARK: - Yardımcılar

    /// Bir triyaj bölümünü başlık + maddelerle yazar; liste boşsa `_(yok)_` koyar.
    private static func digestSection(_ heading: String, _ items: [DigestItem]) -> String {
        var out = "\n## \(heading)\n\n"
        guard !items.isEmpty else { return out + "_(yok)_\n" }
        for item in items { out += "- \(digestLine(item))\n" }
        return out
    }

    /// Tek bir triyaj maddesini `- **<gönderen>** — <konu> _(<yaş>)_` biçimine getirir.
    /// Yaş etiketi boşsa parantezli kısım atlanır.
    private static func digestLine(_ item: DigestItem) -> String {
        var line = "**\(inlineClean(item.from))** — \(inlineClean(item.subject))"
        let age = item.ageLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !age.isEmpty { line += " _(\(age))_" }
        return line
    }

    /// Tek bir mail listesi maddesini iki satıra döker: `- **<gönderen>** — <konu>` (markdown sert
    /// satır sonu) ardından girintili tarih etiketi; kutu varsa ` · <kutu>` eklenir. Boş kutu atlanır.
    private static func listLine(_ item: ExportedListItem) -> String {
        var line = "- **\(inlineClean(item.from))** — \(inlineClean(item.subject))  \n  \(inlineClean(item.dateLabel))"
        if let mailbox = item.mailbox {
            let clean = inlineClean(mailbox)
            if !clean.isEmpty { line += " · \(clean)" }
        }
        return line
    }

    /// Tek satırlık alanlardan (gönderen/konu) iç satır sonlarını temizler; markdown'a dokunmaz.
    private static func inlineClean(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
