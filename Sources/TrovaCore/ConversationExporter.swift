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

    /// Bir kişiyle olan yazışmanın TAMAMINI, konuşmalara (thread) gruplanmış TEK bir Markdown
    /// belgesine döker. Kişi bölümündeki "Tüm yazışma" dışa aktarımı bunu kullanır; çekirdek olduğu
    /// için test edilebilir.
    ///
    /// Belge yapısı:
    ///  - `# <kişi adı / adres>` başlığı; hem ad hem adres varsa altında `_<adres>_`.
    ///  - Özet satırı: `_N mesaj · <ilk tarih> – <son tarih>_` (tek tarihte aralık yerine tek tarih;
    ///    hiç tarih yoksa yalnız sayı). `truncatedTotal` verilir ve belgedeki mesaj sayısından
    ///    büyükse, ayrı bir italik notta "toplam M mesajın en yenileri" bilgisi eklenir.
    ///  - Her konuşma bir `## <konu — boşsa "(konu yok)">` başlığı; altında `_K mesaj_`, ardından o
    ///    konuşmanın mesajları KRONOLOJİK (en eski üstte) `### <gönderen> — <tarih>` + gövde
    ///    bloklarıyla, `---` ile ayrılmış olarak.
    ///
    /// Sıra: Konuşmalar `ThreadGrouping.group` düzeninde (en son etkinliği en yeni olan üstte —
    /// uygulama genelindeki "en yeni önce" kuralı) gelir; konuşma İÇİ ise `ConversationTimeline` ile
    /// en eski üstte okunur (thread yukarıdan aşağı okunur). `N` (özet) belgede gerçekten yer alan
    /// mesaj sayısıdır — timeline aynı `messageID`'nin kopyalarını eleyebileceğinden başlık ile gövde
    /// her zaman tutarlıdır. Gövde/IO çağırana aittir; bu modül saf ve deterministiktir.
    public static func personMarkdown(personName: String?,
                                      personAddress: String,
                                      messages: [Message],
                                      truncatedTotal: Int? = nil,
                                      calendar: Calendar = .current) -> String {
        let address = personAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (personName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = !name.isEmpty ? name : (address.isEmpty ? "(kişi yok)" : address)

        // id → gövde eşlemesi: gruplama SearchHit üzerinde yapılır, gövdeler burada geri bağlanır.
        var bodyByID: [String: String] = [:]
        for message in messages where message.body != nil { bodyByID[message.hit.id] = message.body }

        // Konuşmalara grupla (konu normalizasyonu + temsilci konu ThreadGrouping'ten gelir), her
        // konuşma içini kronolojik akışa diz. `emitted` = belgede gerçekten yer alan mesajlar.
        let groups = ThreadGrouping.group(messages.map(\.hit))
        let orderedGroups = groups.map { ConversationTimeline.timeline($0.members) }
        let emitted = orderedGroups.flatMap { $0 }

        var out = "# \(title)\n\n"
        if !name.isEmpty, !address.isEmpty { out += "_\(address)_\n\n" }
        out += metaLine(emitted.map { (hit: $0, body: nil) }, calendar: calendar) + "\n"
        if let truncatedTotal, truncatedTotal > emitted.count {
            out += "\n_(Toplam \(truncatedTotal) mesajın en yeni \(emitted.count) tanesi dışa aktarıldı.)_\n"
        }
        guard !emitted.isEmpty else { return out }

        let sections = zip(groups, orderedGroups).map { group, ordered -> String in
            let blocks = ordered.map { hit in
                block((hit: hit, body: bodyByID[hit.id]), heading: "###", calendar: calendar)
            }
            return "## \(group.representativeSubject)\n\n_\(ordered.count) mesaj_\n\n"
                + blocks.joined(separator: "\n\n---\n\n")
        }
        out += "\n" + sections.joined(separator: "\n\n") + "\n"
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

    /// Tek bir mesajı `<heading> <gönderen> — <tarih>` başlığı + gövde bloğuna çevirir. `heading`
    /// başlık düzeyini verir: tek konuşma dökümünde `##`, kişi (çok konuşmalı) dökümünde `###`.
    private static func block(_ message: Message, heading: String = "##", calendar: Calendar) -> String {
        let when = message.hit.date.map { RelativeTime.absolute($0, calendar: calendar) } ?? "tarih yok"
        return "\(heading) \(displayName(message.hit)) — \(when)\n\n\(messageBody(message.body, snippet: message.hit.snippet))"
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
