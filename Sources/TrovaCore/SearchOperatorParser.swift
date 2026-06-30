import Foundation

/// Arama sorgusundan çıkarılan Gmail-tarzı operatörler + temizlenmiş metin.
public struct SearchOperators: Equatable, Sendable {
    public var fromContains: String?     // from:/gönderen: → gönderen filtresi
    public var hasAttachment: Bool       // has:attachment / has:ek → yalnızca ekli mailler
    public var cleaned: String           // operatörler çıkarıldıktan sonra kalan arama metni
}

/// Sorgudaki `from:ali`, `gönderen:veli`, `has:attachment`, `has:ek` gibi operatörleri ayrıştırır.
/// Saf — yan etkisiz, test edilebilir. Türkçe doğal dil tarih ayrıştırıcısıyla zincirlenir.
public enum SearchOperatorParser {
    public static func parse(_ query: String) -> SearchOperators {
        var fromContains: String?
        var hasAttachment = false
        var kept: [String] = []

        for token in query.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init) {
            let lower = token.lowercased(with: Locale(identifier: "tr_TR"))

            if lower.hasPrefix("from:") || lower.hasPrefix("gönderen:") || lower.hasPrefix("gonderen:") {
                // Değer orijinal büyük/küçük harfiyle korunur (e-posta/ad olabilir).
                if let colon = token.firstIndex(of: ":") {
                    let value = String(token[token.index(after: colon)...])
                    if !value.isEmpty { fromContains = value }
                }
                continue
            }
            if lower == "has:attachment" || lower == "has:ek" || lower == "has:ekli" || lower == "ek:var" {
                hasAttachment = true
                continue
            }
            kept.append(token)
        }

        return SearchOperators(fromContains: fromContains, hasAttachment: hasAttachment,
                               cleaned: kept.joined(separator: " "))
    }
}
