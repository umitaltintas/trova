import Foundation

/// Bir konuşmanın (`ConversationTimeline` sırasıyla: tekilleştirilmiş, kronolojik artan) TAMAMINI
/// tek bir paylaşılabilir belgeye — Markdown ya da CSV — döken saf, yan etkisiz, deterministik modül.
/// Okuma panelindeki "KONUŞMA" bölümünün "Dışa aktar" menüsü bunu kullanır; çekirdek olduğu için
/// test edilebilir.
///
/// Gövde yükleme/IO çağırana aittir: her mesaj `(hit, opsiyonel gövde)` olarak buraya gelir. Sıralama
/// da çağıranın işidir (`ConversationTimeline.timeline`); bu modül girdi sırasını AYNEN korur.
/// Tarihler `RelativeTime.absolute` ile mutlak ve locale'den bağımsız biçimlenir; deterministik test
/// için `calendar` enjekte edilebilir.
public enum ConversationExporter {

    /// Bir konuşma mesajı: arama sonucu + (varsa) yüklenmiş tam gövde. CSV yalnız `hit`'i kullanır.
    public typealias Message = (hit: SearchHit, body: String?)

    /// Konuşmayı Markdown belgesine döker.
    /// - Başlık: `# <konu — boşsa "(konu yok)">`, altında `_N mesaj_` (tarih varsa ` · <ilk> – <son>`).
    /// - Her mesaj: `## <gönderen adı/adresi — yoksa "—"> — <mutlak tarih / "tarih yok">`, ardından
    ///   gövde (gövde nil/boşsa snippet, o da boşsa `_(gövde yok)_`). Mesajlar `---` ile ayrılır.
    public static func markdown(subject: String?,
                               messages: [Message],
                               calendar: Calendar = .current) -> String {
        var out = "# \(trimmedOrPlaceholder(subject ?? "", "(konu yok)"))\n\n"
        out += metaLine(messages, calendar: calendar) + "\n"
        guard !messages.isEmpty else { return out }
        let blocks = messages.map { block($0, calendar: calendar) }
        out += "\n" + blocks.joined(separator: "\n\n---\n\n") + "\n"
        return out
    }

    /// Konuşmayı elektronik tabloya uygun CSV'ye döker. Sütunlar: Tarih, Gönderen, Adres, Konu, Özet.
    /// Kaçış/ayırıcı (virgül, RFC 4180, BOM) uygulamanın diğer CSV'leriyle tutarlı olsun diye
    /// `CsvExporter`'a devredilir. "Özet" mesajın snippet'idir (tam gövde hücreye taşınmaz).
    public static func csv(messages: [Message],
                          calendar: Calendar = .current) -> String {
        let headers = ["Tarih", "Gönderen", "Adres", "Konu", "Özet"]
        let rows = messages.map { message -> [String] in
            let hit = message.hit
            let date = hit.date.map { RelativeTime.absolute($0, calendar: calendar) } ?? ""
            return [date, hit.fromName ?? "", hit.fromAddress ?? "", hit.subject ?? "", hit.snippet]
        }
        return CsvExporter.csv(headers: headers, rows: rows)
    }

    // MARK: - Yardımcılar

    /// Başlık altı özet satırı: `_N mesaj_`; en az bir tarih varsa ` · <ilk> – <son>` eklenir
    /// (ilk = en eski, son = en yeni). İkisi aynıysa aralık yerine tek tarih yazılır.
    private static func metaLine(_ messages: [Message], calendar: Calendar) -> String {
        var meta = "_\(messages.count) mesaj"
        let dates = messages.compactMap { $0.hit.date }
        if let first = dates.min(), let last = dates.max() {
            let a = RelativeTime.absolute(first, calendar: calendar)
            let b = RelativeTime.absolute(last, calendar: calendar)
            meta += " · " + (a == b ? a : "\(a) – \(b)")
        }
        return meta + "_"
    }

    /// Tek bir mesajı `## <gönderen> — <tarih>` başlığı + gövde bloğuna çevirir.
    private static func block(_ message: Message, calendar: Calendar) -> String {
        let when = message.hit.date.map { RelativeTime.absolute($0, calendar: calendar) } ?? "tarih yok"
        return "## \(displayName(message.hit)) — \(when)\n\n\(messageBody(message.body, snippet: message.hit.snippet))"
    }

    /// Gönderen adı (boşsa adres, o da boşsa `—`). Markdown başlığında tek satırlık kullanılır.
    private static func displayName(_ hit: SearchHit) -> String {
        if let name = hit.fromName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let addr = hit.fromAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !addr.isEmpty {
            return addr
        }
        return "—"
    }

    /// Gövde metni: dolu gövde varsa o; yoksa snippet; o da boşsa `_(gövde yok)_`.
    private static func messageBody(_ body: String?, snippet: String) -> String {
        if let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            return body
        }
        let snip = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return snip.isEmpty ? "_(gövde yok)_" : snip
    }

    private static func trimmedOrPlaceholder(_ s: String, _ placeholder: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? placeholder : t
    }
}
