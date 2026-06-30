import Foundation

/// RFC 6068 `mailto:` bağlantıları üretir — bulunan/okunan maile "Yanıtla" ya da
/// "Yeni e-posta" ile native Mail.app oluşturma penceresi açmak için.
///
/// Tamamen yereldir: yalnız bir URL kurar. Hiçbir şey GÖNDERMEZ, Mail deposuna YAZMAZ;
/// kullanıcının önüne dolu bir oluşturma penceresi getirir, gerisi kullanıcıdadır.
public enum MailtoLink {

    /// Verilen alanlardan RFC 6068 uyumlu bir `mailto:` URL'i kurar.
    ///
    /// - Boş/yalnızca-boşluk alanlar atlanır; çoklu alıcı virgülle ayrılır.
    /// - `subject`/`body` sorgu (query) bileşeni olarak yüzde-kodlanır:
    ///   boşluk `%20`, `&` → `%26`, `?` → `%3F`, satır sonu `%0A`, Türkçe karakterler UTF-8 ile.
    /// - `to` boş olsa bile yalnız `subject`/`body`/`cc` ile geçerli bir URL üretilebilir
    ///   (alıcısız yeni e-posta); ancak anlamlı hiçbir alan yoksa `nil` döner.
    public static func url(to: [String], cc: [String] = [],
                           subject: String? = nil, body: String? = nil) -> URL? {
        // Adresleri temizle: her birini kırp, boşları at.
        let cleanTo = to.map(trimmed).filter { !$0.isEmpty }
        let cleanCc = cc.map(trimmed).filter { !$0.isEmpty }
        let cleanSubject = subject.map(trimmed).flatMap { $0.isEmpty ? nil : $0 }
        // Gövdedeki satır sonları/iç boşluklar korunur; yalnız tümüyle boşsa atlanır.
        let cleanBody = body.flatMap { trimmed($0).isEmpty ? nil : $0 }

        // Sorgu alanları (cc/subject/body) sırayla eklenir; & ile birleştirilir.
        var query: [String] = []
        if !cleanCc.isEmpty {
            query.append("cc=" + cleanCc.map(encodeAddress).joined(separator: ","))
        }
        if let cleanSubject {
            query.append("subject=" + encodeField(cleanSubject))
        }
        if let cleanBody {
            query.append("body=" + encodeField(cleanBody))
        }

        // Anlamlı hiçbir alan yoksa URL üretme.
        guard !cleanTo.isEmpty || !query.isEmpty else { return nil }

        var string = "mailto:" + cleanTo.map(encodeAddress).joined(separator: ",")
        if !query.isEmpty { string += "?" + query.joined(separator: "&") }
        return URL(string: string)
    }

    /// Yanıt konusu üretir: konuda zaten bir yanıt/iletme öneki (Re:/Yan:/RE:/Fwd:/İlt: …)
    /// varsa olduğu gibi bırakır (çift önek yok); yoksa başına `"Yan: "` ekler.
    /// Önek tespiti tek kaynaktan gelir: `EMLXParser.hasReplyPrefix`.
    public static func replySubject(_ subject: String) -> String {
        let base = trimmed(subject)
        return EMLXParser.hasReplyPrefix(base) ? base : "Yan: " + base
    }

    // MARK: - Yüzde-kodlama (RFC 6068)

    /// `unreserved` (ALPHA / DIGIT / `-` `.` `_` `~`) korunur, gerisi yüzde-kodlanır.
    /// Sorgu alanlarında boşluk `%20`, `&`/`?`/`=` ve satır sonları güvenle kaçışlanır.
    private static let fieldAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Adreslerde ayrıca `@` okunur kalsın diye korunur (örn. `ali@ornek.com`).
    private static let addressAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~@")

    private static func encodeField(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: fieldAllowed) ?? s
    }

    private static func encodeAddress(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: addressAllowed) ?? s
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
