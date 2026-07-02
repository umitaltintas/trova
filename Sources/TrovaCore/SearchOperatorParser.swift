import Foundation

/// Arama sorgusundan çıkarılan açık alan operatörleri + temizlenmiş metin.
public struct SearchOperators: Equatable, Sendable {
    public var fromContains: String?           // kimden:/from:/gönderen: → gönderen filtresi
    public var mailboxContains: String?        // kutu:/mailbox: → posta kutusu (parça, büyük/küçük harf duyarsız) filtresi
    public var hasAttachment: Bool             // has:attachment / has:ek / ek:var → yalnızca ekli mailler
    public var attachmentKind: AttachmentKind? // ek:/attachment:/tür:/has: <tür> → ek türü filtresi (nil → etkisiz)
    public var cleaned: String                 // operatörler çıkarıldıktan sonra kalan arama metni
}

/// Sorgudaki açık alan operatörlerini ayrıştırır (Türkçe birincil, İngilizce eş anlamlı):
/// - `kimden:` / `from:` / `gönderen:` → gönderen daraltması,
/// - `kutu:` / `mailbox:` → posta kutusu daraltması,
/// - `ek:` / `attachment:` / `tür:` / `has:` <tür> → ek türü; `has:attachment`/`ek:var` → herhangi ek.
///
/// Değer çift tırnaklı olabilir (`kimden:"Ali Veli"`), boşluk içeren adları tek belirteç yapar.
/// Operatör adları büyük/küçük harf duyarsızdır (tr_TR indirgemesi: `Kimden:` de çalışır); değerin
/// harf durumu KORUNUR (e-posta/ad olabilir). Aynı alan birden çok kez verilirse SON açık değer
/// kazanır — açık operatör, aynı alandaki her tür çıkarımı ezer (deterministik, belgeli kural).
/// Tanınmayan operatör/ek türü → belirteç aramada kalır (hata verilmez).
/// Saf — yan etkisiz, test edilebilir. Türkçe doğal dil tarih ayrıştırıcısıyla zincirlenir.
public enum SearchOperatorParser {
    private static let trLocale = Locale(identifier: "tr_TR")

    public static func parse(_ query: String) -> SearchOperators {
        var fromContains: String?
        var mailboxContains: String?
        var hasAttachment = false
        var attachmentKind: AttachmentKind?
        var kept: [String] = []

        for token in tokenize(query) {
            // Tırnak/tire ile başlayan belirteçler operatör DEĞİLDİR (gelişmiş FTS söz dizimi:
            // "tam ifade", -hariç); ayrıca kolonu olmayan belirteç de öyle → aramada korunur.
            guard let first = token.first, first != "\"", first != "-",
                  let colon = token.firstIndex(of: ":") else {
                kept.append(token); continue
            }
            let key = String(token[..<colon]).lowercased(with: trLocale)
            let value = unquote(String(token[token.index(after: colon)...]))

            switch key {
            case "kimden", "from", "gönderen", "gonderen":
                if !value.isEmpty { fromContains = value }   // değersizse belirteci yut (mevcut davranış)
            case "kutu", "mailbox":
                if !value.isEmpty { mailboxContains = value }
            default:
                switch attachmentOperator(key: key, value: value) {
                case .any:
                    hasAttachment = true
                case .kind(let kind):
                    attachmentKind = kind
                case .none:
                    kept.append(token)   // tanınmayan operatör/tür → aramada kalır
                }
            }
        }

        return SearchOperators(fromContains: fromContains, mailboxContains: mailboxContains,
                               hasAttachment: hasAttachment, attachmentKind: attachmentKind,
                               cleaned: kept.joined(separator: " "))
    }

    /// Ek operatörünün sonucu: herhangi-ek, belirli tür ya da tanınmadı (`none`).
    private enum AttachmentOutcome { case any, kind(AttachmentKind), none }

    /// `has:`/`ek:`/`attachment:`/`tür:` operatörünü çözümler; başka anahtar → `none`.
    /// `has:attachment`/`has:ek`/`has:ekli`/`ek:var` = herhangi ek; `<anahtar>:<tür>` = tür filtresi.
    private static func attachmentOperator(key: String, value: String) -> AttachmentOutcome {
        let low = value.lowercased(with: trLocale)
        switch key {
        case "has":
            if low == "attachment" || low == "ek" || low == "ekli" { return .any }
        case "ek":
            if low == "var" { return .any }
        case "attachment", "tür", "tur":
            break
        default:
            return .none
        }
        if let kind = attachmentKind(forTerm: value) { return .kind(kind) }
        return .none
    }

    /// Sorguyu boşlukla ayrılmış belirteçlere böler; çift tırnak İÇİNDEKİ boşluk belirteci BÖLMEZ
    /// (`kimden:"Ali Veli"` tek belirteç). Tırnaklar belirteçte korunur — operatör değeri `unquote`
    /// ile temizlenir, serbest metin ise FtsQueryBuilder'ın gelişmiş söz dizimine olduğu gibi geçer.
    private static func tokenize(_ query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for ch in query {
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
            } else if !inQuotes && (ch == " " || ch == "\t" || ch == "\n") {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Değerin baş/sondaki çift tırnaklarını temizler (`"Ali Veli"` → `Ali Veli`).
    private static func unquote(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// Bir tür belirtecini (Türkçe/İngilizce eş anlamlılar) ek kategorisine eşler; tanınmazsa nil.
    /// Türkçe küçük harf indirgemesi (İ→i) yapılır; diakritikli ("görsel", "arşiv") biçimler desteklenir.
    /// `public`: `trova attachments --kind` da AYNI eşlemeyi kullansın (tek kaynak, app ile tutarlı).
    public static func attachmentKind(forTerm term: String) -> AttachmentKind? {
        switch term.lowercased(with: trLocale) {
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
