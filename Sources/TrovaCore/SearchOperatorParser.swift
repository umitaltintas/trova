import Foundation

/// Arama sorgusundan çıkarılan Gmail-tarzı operatörler + temizlenmiş metin.
public struct SearchOperators: Equatable, Sendable {
    public var fromContains: String?           // from:/gönderen: → gönderen filtresi
    public var hasAttachment: Bool             // has:attachment / has:ek → yalnızca ekli mailler
    public var attachmentKind: AttachmentKind? // has:pdf / ek:görsel / tür:tablo → ek türü filtresi (nil → etkisiz)
    public var cleaned: String                 // operatörler çıkarıldıktan sonra kalan arama metni
}

/// Sorgudaki `from:ali`, `gönderen:veli`, `has:attachment`, `has:ek`, ayrıca tür belirten
/// `has:pdf` / `ek:görsel` / `tür:tablo` gibi operatörleri ayrıştırır.
/// Saf — yan etkisiz, test edilebilir. Türkçe doğal dil tarih ayrıştırıcısıyla zincirlenir.
public enum SearchOperatorParser {
    public static func parse(_ query: String) -> SearchOperators {
        var fromContains: String?
        var hasAttachment = false
        var attachmentKind: AttachmentKind?
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
            // Tür belirtmeden "ekli" — KORUNUR (mevcut davranış).
            if lower == "has:attachment" || lower == "has:ek" || lower == "has:ekli" || lower == "ek:var" {
                hasAttachment = true
                continue
            }
            // Tür belirten ek operatörleri: has:<tür> / ek:<tür> / tür:<tür>.
            // Yalnız bilinen bir türe çözülürse token tüketilir; çözülmezse aramada kalır.
            if lower.hasPrefix("has:") || lower.hasPrefix("ek:")
                || lower.hasPrefix("tür:") || lower.hasPrefix("tur:") {
                if let colon = token.firstIndex(of: ":"),
                   let kind = Self.attachmentKind(forTerm: String(token[token.index(after: colon)...])) {
                    attachmentKind = kind
                    continue
                }
            }
            kept.append(token)
        }

        return SearchOperators(fromContains: fromContains, hasAttachment: hasAttachment,
                               attachmentKind: attachmentKind, cleaned: kept.joined(separator: " "))
    }

    /// Bir tür belirtecini (Türkçe/İngilizce eş anlamlılar) ek kategorisine eşler; tanınmazsa nil.
    /// Türkçe küçük harf indirgemesi (İ→i) yapılır; diakritikli ("görsel", "arşiv") biçimler desteklenir.
    static func attachmentKind(forTerm term: String) -> AttachmentKind? {
        switch term.lowercased(with: Locale(identifier: "tr_TR")) {
        case "pdf":
            return .pdf
        case "görsel", "gorsel", "image", "resim", "foto", "fotoğraf", "fotograf":
            return .image
        case "tablo", "sheet", "excel", "spreadsheet":
            return .sheet
        case "belge", "doc", "document", "word", "metin":
            return .doc
        case "sunum", "presentation", "slayt":
            return .presentation
        case "arşiv", "arsiv", "archive", "zip":
            return .archive
        case "ses", "audio":
            return .audio
        case "video":
            return .video
        case "kod", "code":
            return .code
        default:
            return nil
        }
    }
}
