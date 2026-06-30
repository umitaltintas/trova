import Foundation

/// Bir `.emlx` dosyasından çıkarılan ham e-posta alanları.
public struct ParsedEmail: Sendable {
    public var messageID: String?
    public var fromName: String?
    public var fromAddress: String?
    public var to: String?
    public var cc: String?
    public var subject: String?
    public var date: Date?
    public var body: String
    public var inReplyTo: String?        // yanıtlanan Message-ID
    public var references: [String]      // konu zinciri Message-ID'leri
    public var attachments: [String]     // ek dosya adları
    public var flags: Int?               // .emlx plist trailer'ındaki ham `flags` bitfield (yoksa nil)

    /// Ham `flags` bitfield'ından çözülen okundu/bayraklı/yanıtlandı durumu (flags yoksa nil).
    public var emailFlags: EmailFlags? { flags.map(EmailFlags.init(rawValue:)) }

    public init(messageID: String? = nil, fromName: String? = nil, fromAddress: String? = nil,
                to: String? = nil, cc: String? = nil, subject: String? = nil,
                date: Date? = nil, body: String = "",
                inReplyTo: String? = nil, references: [String] = [], attachments: [String] = [],
                flags: Int? = nil) {
        self.messageID = messageID
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.to = to
        self.cc = cc
        self.subject = subject
        self.date = date
        self.body = body
        self.inReplyTo = inReplyTo
        self.references = references
        self.attachments = attachments
        self.flags = flags
    }
}

/// Bir e-posta ekinin adı, türü ve ham byte'ları.
public struct EmailAttachment: Sendable {
    public let filename: String
    public let mimeType: String
    public let data: Data
}

/// `.emlx` (Apple Mail) ve genel RFC822 mesajlarını ayrıştırır.
///
/// MIME çok parçalılığı, `base64`/`quoted-printable` aktarım kodlaması,
/// IANA charset çözümü (Türkçe `iso-8859-9`/`windows-1254` dahil) ve
/// RFC 2047 encoded-word başlıkları desteklenir.
public enum EMLXParser {

    public static func parse(data: Data) -> ParsedEmail {
        var email = parseRFC822(stripEMLXEnvelope(data))
        email.flags = extractFlags(data)   // RFC822 mesajından sonraki plist trailer'dan
        return email
    }

    public static func parse(fileURL: URL) throws -> ParsedEmail {
        parse(data: try Data(contentsOf: fileURL))
    }

    // MARK: - HTML gövde (detay görünümü için)

    /// Mailin `text/html` parçasını (varsa) ham olarak döndürür — şeritlenmeden.
    public static func extractHTMLBody(data: Data) -> String? {
        let rfc = stripEMLXEnvelope(data)
        let raw = String(data: rfc, encoding: .isoLatin1) ?? String(decoding: rfc, as: UTF8.self)
        let (headerBlock, body) = splitHeaderBody(raw)
        let headers = parseHeaders(headerBlock)
        return htmlPart(
            contentType: headers["content-type"] ?? "text/plain",
            transferEncoding: headers["content-transfer-encoding"] ?? "",
            body: body)
    }

    static func htmlPart(contentType: String, transferEncoding: String, body: String) -> String? {
        let ct = parseContentType(contentType)
        if ct.type == "multipart", let boundary = ct.boundary {
            var found: String?
            for part in splitMultipart(body: body, boundary: boundary) {
                let (partHeader, partBody) = splitHeaderBody(part)
                let headers = parseHeaders(partHeader)
                if let html = htmlPart(
                    contentType: headers["content-type"] ?? "text/plain",
                    transferEncoding: headers["content-transfer-encoding"] ?? "",
                    body: partBody) {
                    found = html   // son/iç içe text/html'i tercih et
                }
            }
            return found
        }
        guard ct.full == "text/html" else { return nil }
        return decodeCharset(decodeTransferEncoding(body, encoding: transferEncoding), charset: ct.charset)
    }

    /// E-posta HTML'ini güvenli hale getirir: script/style/iframe ve **uzak görselleri**
    /// (izleme pikselleri) ve olay işleyicilerini kaldırır.
    public static func sanitizeEmailHTML(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "iframe", "object", "embed", "link", "meta"] {
            s = s.replacingOccurrences(of: "(?is)<\(tag)[^>]*>.*?</\(tag)>", with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "(?is)<\(tag)[^>]*/?>", with: "", options: .regularExpression)
        }
        // Uzak görseller (izleme) — http(s) kaynaklı img'leri kaldır.
        s = s.replacingOccurrences(of: "(?is)<img[^>]+src=[\"']?https?://[^>]*>", with: "", options: .regularExpression)
        // Olay işleyicileri ve javascript: şeması.
        s = s.replacingOccurrences(of: "(?is)\\son\\w+\\s*=\\s*\"[^\"]*\"", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?is)\\son\\w+\\s*=\\s*'[^']*'", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)javascript:", with: "", options: .regularExpression)
        return s
    }

    // MARK: - emlx zarfı

    /// `.emlx` = ilk satırda byte sayısı, ardından o uzunlukta RFC822 mesajı, sonra plist.
    static func stripEMLXEnvelope(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard let nl = bytes.firstIndex(of: 0x0A) else { return data }
        let firstLine = String(decoding: bytes[..<nl], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        guard let count = Int(firstLine), count > 0 else { return data }  // zarf yoksa tümü mesaj
        let start = nl + 1
        let end = min(start + count, bytes.count)
        guard start < end else { return data }
        return Data(bytes[start..<end])
    }

    /// `.emlx` mesajının ardından gelen plist trailer'ından ham `flags` bitfield'ını çıkarır.
    /// Zarf yoksa, trailer yoksa ya da `flags` anahtarı bulunamazsa nil döner — asla crash etmez.
    static func extractFlags(_ data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard let nl = bytes.firstIndex(of: 0x0A) else { return nil }
        let firstLine = String(decoding: bytes[..<nl], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        guard let count = Int(firstLine), count > 0 else { return nil }  // zarf yoksa trailer da yok
        let trailerStart = nl + 1 + count
        guard trailerStart < bytes.count else { return nil }              // mesajdan sonrası boş
        var slice = bytes[trailerStart...]
        // Plist başlangıcına ('<') kadar olan boşluk/yeni satırları at.
        guard let lt = slice.firstIndex(of: 0x3C) else { return nil }
        slice = slice[lt...]
        let trailer = Data(slice)

        // 1) Tam plist ayrıştırması (en güvenli yol).
        if let dict = try? PropertyListSerialization.propertyList(from: trailer, format: nil)
            as? [String: Any] {
            if let n = dict["flags"] as? Int { return n }
            if let n = dict["flags"] as? NSNumber { return n.intValue }
        }
        // 2) Yedek: doğrudan <key>flags</key><integer>…</integer> desenini yakala.
        let raw = String(decoding: trailer, as: UTF8.self)
        if let r = raw.range(of: "<key>flags</key>\\s*<integer>(-?[0-9]+)</integer>",
                             options: .regularExpression),
           let numR = raw[r].range(of: "-?[0-9]+", options: .regularExpression) {
            return Int(raw[r][numR])
        }
        return nil
    }

    // MARK: - RFC822

    static func parseRFC822(_ data: Data) -> ParsedEmail {
        // Latin1 byte ↔ skalar birebir olduğundan yapısal ayrıştırmayı Latin1 string
        // üzerinde kayıpsız yaparız; gerçek charset çözümü yaprak parçada uygulanır.
        let raw = String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
        let (headerBlock, body) = splitHeaderBody(raw)
        let headers = parseHeaders(headerBlock)

        var email = ParsedEmail()
        email.messageID = headers["message-id"]?
            .trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        email.subject = headers["subject"].map(decodeEncodedWords)
        email.to = headers["to"].map(decodeEncodedWords)
        email.cc = headers["cc"].map(decodeEncodedWords)
        if let from = headers["from"] {
            let (name, addr) = parseAddress(decodeEncodedWords(from))
            email.fromName = name
            email.fromAddress = addr
        }
        email.date = headers["date"].flatMap(parseDate)
        email.inReplyTo = headers["in-reply-to"].flatMap { angleIDs($0).first }
        email.references = headers["references"].map(angleIDs) ?? []

        let contentType = headers["content-type"] ?? "text/plain"
        email.body = collapseWhitespace(extractText(
            contentType: contentType,
            transferEncoding: headers["content-transfer-encoding"] ?? "",
            body: body))
        email.attachments = attachmentNames(contentType: contentType, body: body)
        return email
    }

    /// `<a@x> <b@y>` → `["a@x", "b@y"]`
    static func angleIDs(_ value: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "<([^>]+)>") else { return [] }
        let ns = value as NSString
        return re.matches(in: value, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces) }
    }

    /// Yanıt/iletme öneki deseni (Re:/Aw:/Yan:/Fwd:/İlt: …) — thread anahtarı VE yanıt
    /// konusu için tek kaynak. Türkçe-yerel küçük harfe indirgenmiş konu üzerinde eşleşir.
    static let replyPrefixPattern =
        "^\\s*(re|aw|wg|fwd?|fw|ilt|yan|ynt|yanıt|iletildi|sv|antw)(\\[\\d+\\])?\\s*:\\s*"

    /// Konuda zaten bir yanıt/iletme öneki var mı (büyük/küçük harf duyarsız, Türkçe-yerel).
    /// `MailtoLink.replySubject` bununla çift önek eklemekten kaçınır.
    public static func hasReplyPrefix(_ subject: String) -> Bool {
        let s = subject.lowercased(with: Locale(identifier: "tr"))
        return s.range(of: replyPrefixPattern, options: .regularExpression) != nil
    }

    /// Konu önekini sadeleştirir (Re:/Fwd:/Yan:/İlt: vb.) — thread anahtarı için.
    /// Türkçe-yerel lowercase ile başlar (İ→i, I→ı) ki "İlt:" gibi önekler eşleşsin.
    public static func normalizeSubject(_ subject: String?) -> String {
        guard let subject else { return "" }
        var s = subject.lowercased(with: Locale(identifier: "tr"))
        while let r = s.range(of: replyPrefixPattern, options: .regularExpression) {
            s.removeSubrange(r)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// MIME parçalarındaki ek dosya adlarını toplar.
    static func attachmentNames(contentType: String, body: String) -> [String] {
        let ct = parseContentType(contentType)
        guard ct.type == "multipart", let boundary = ct.boundary else { return [] }
        var names: [String] = []
        for part in splitMultipart(body: body, boundary: boundary) {
            let (partHeader, partBody) = splitHeaderBody(part)
            let headers = parseHeaders(partHeader)
            let partType = headers["content-type"] ?? "text/plain"
            if parseContentType(partType).type == "multipart" {
                names += attachmentNames(contentType: partType, body: partBody)
            } else if let name = attachmentFilename(
                contentType: partType, disposition: headers["content-disposition"]) {
                names.append(name)
            }
        }
        return names
    }

    /// Eklerin adlarını VE ham byte'larını çıkarır (OCR/metin çıkarımı için).
    public static func extractAttachments(data: Data) -> [EmailAttachment] {
        let rfc = stripEMLXEnvelope(data)
        let raw = String(data: rfc, encoding: .isoLatin1) ?? String(decoding: rfc, as: UTF8.self)
        let (headerBlock, body) = splitHeaderBody(raw)
        let headers = parseHeaders(headerBlock)
        return collectAttachments(contentType: headers["content-type"] ?? "text/plain", body: body)
    }

    static func collectAttachments(contentType: String, body: String) -> [EmailAttachment] {
        let ct = parseContentType(contentType)
        guard ct.type == "multipart", let boundary = ct.boundary else { return [] }
        var result: [EmailAttachment] = []
        for part in splitMultipart(body: body, boundary: boundary) {
            let (partHeader, partBody) = splitHeaderBody(part)
            let headers = parseHeaders(partHeader)
            let partType = headers["content-type"] ?? "text/plain"
            if parseContentType(partType).type == "multipart" {
                result += collectAttachments(contentType: partType, body: partBody)
            } else if let name = attachmentFilename(
                contentType: partType, disposition: headers["content-disposition"]) {
                let bytes = decodeTransferEncoding(
                    partBody, encoding: headers["content-transfer-encoding"] ?? "")
                result.append(EmailAttachment(
                    filename: name, mimeType: parseContentType(partType).full, data: bytes))
            }
        }
        return result
    }

    static func attachmentFilename(contentType: String?, disposition: String?) -> String? {
        if let disposition {
            let params = parseContentType(disposition).params
            if disposition.lowercased().contains("attachment") || params["filename"] != nil {
                if let filename = params["filename"] { return decodeEncodedWords(filename) }
            }
        }
        if let contentType, let name = parseContentType(contentType).params["name"] {
            return decodeEncodedWords(name)
        }
        return nil
    }

    static func splitHeaderBody(_ raw: String) -> (header: String, body: String) {
        if let r = raw.range(of: "\r\n\r\n") {
            return (String(raw[..<r.lowerBound]), String(raw[r.upperBound...]))
        }
        if let r = raw.range(of: "\n\n") {
            return (String(raw[..<r.lowerBound]), String(raw[r.upperBound...]))
        }
        return (raw, "")
    }

    static func parseHeaders(_ block: String) -> [String: String] {
        let normalized = block.replacingOccurrences(of: "\r\n", with: "\n")
        var unfolded: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, first == " " || first == "\t", !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                unfolded.append(String(line))
            }
        }
        var headers: [String: String] = [:]
        for line in unfolded {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[name] == nil { headers[name] = value }  // ilk değeri tut
        }
        return headers
    }

    // MARK: - Gövde / MIME

    struct ContentType {
        var type: String
        var subtype: String
        var params: [String: String]
        var full: String { "\(type)/\(subtype)" }
        var boundary: String? { params["boundary"] }
        var charset: String? { params["charset"] }
    }

    static func parseContentType(_ value: String) -> ContentType {
        let parts = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let mime = (parts.first ?? "text/plain").lowercased()
        let slash = mime.split(separator: "/", maxSplits: 1)
        let type = slash.first.map(String.init) ?? "text"
        let subtype = slash.count > 1 ? String(slash[1]) : "plain"

        var params: [String: String] = [:]
        for p in parts.dropFirst() {
            guard let eq = p.firstIndex(of: "=") else { continue }
            let key = p[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var val = p[p.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if val.count >= 2, val.hasPrefix("\""), val.hasSuffix("\"") {
                val = String(val.dropFirst().dropLast())
            }
            params[key] = String(val)
        }
        return ContentType(type: type, subtype: subtype, params: params)
    }

    static func extractText(contentType: String, transferEncoding: String, body: String) -> String {
        let ct = parseContentType(contentType)

        if ct.type == "multipart", let boundary = ct.boundary {
            var plain: [String] = []
            var html: [String] = []
            for part in splitMultipart(body: body, boundary: boundary) {
                let (partHeader, partBody) = splitHeaderBody(part)
                let headers = parseHeaders(partHeader)
                let partCT = parseContentType(headers["content-type"] ?? "text/plain")
                let text = extractText(
                    contentType: headers["content-type"] ?? "text/plain",
                    transferEncoding: headers["content-transfer-encoding"] ?? "",
                    body: partBody)
                guard !text.isEmpty else { continue }
                if partCT.full == "text/html" { html.append(text) } else { plain.append(text) }
            }
            if ct.subtype == "alternative" {
                return plain.first ?? html.first ?? ""   // düz metni HTML'e tercih et
            }
            return (plain + html).joined(separator: "\n\n")
        }

        // Yaprak parça
        let decoded = decodeTransferEncoding(body, encoding: transferEncoding)
        let text = decodeCharset(decoded, charset: ct.charset)
        return ct.full == "text/html" ? stripHTML(text) : text
    }

    static func splitMultipart(body: String, boundary: String) -> [String] {
        let delimiter = "--" + boundary
        var parts: [String] = []
        var current: [String]? = nil
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if trimmed == delimiter || trimmed == delimiter + "--" {
                if let c = current { parts.append(c.joined(separator: "\n")) }
                current = (trimmed == delimiter + "--") ? nil : []  // "--" kapanış sınırı
            } else {
                current?.append(line)
            }
        }
        return parts
    }

    // MARK: - Kod çözücüler

    static func decodeTransferEncoding(_ body: String, encoding: String) -> Data {
        let latin1 = body.data(using: .isoLatin1) ?? Data(body.utf8)
        switch encoding.lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64":
            let cleaned = body.components(separatedBy: .whitespacesAndNewlines).joined()
            return Data(base64Encoded: cleaned) ?? latin1
        case "quoted-printable":
            return decodeQuotedPrintable([UInt8](latin1))
        default:
            return latin1  // 7bit / 8bit / binary / yok
        }
    }

    static func decodeQuotedPrintable(_ bytes: [UInt8]) -> Data {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x3D {  // '='
                if i + 1 < bytes.count, bytes[i + 1] == 0x0A { i += 2; continue }            // =\n
                if i + 2 < bytes.count, bytes[i + 1] == 0x0D, bytes[i + 2] == 0x0A { i += 3; continue } // =\r\n
                if i + 2 < bytes.count, let hi = hexValue(bytes[i + 1]), let lo = hexValue(bytes[i + 2]) {
                    out.append(hi << 4 | lo); i += 3; continue
                }
                out.append(b); i += 1
            } else {
                out.append(b); i += 1
            }
        }
        return Data(out)
    }

    static func hexValue(_ b: UInt8) -> UInt8? {
        switch b {
        case 0x30...0x39: return b - 0x30
        case 0x41...0x46: return b - 0x41 + 10
        case 0x61...0x66: return b - 0x61 + 10
        default: return nil
        }
    }

    /// IANA charset adıyla (CoreFoundation üzerinden) byte'ları metne çevirir.
    /// `iso-8859-9`, `windows-1254` gibi Türkçe kodlamalar otomatik desteklenir.
    static func decodeCharset(_ data: Data, charset: String?) -> String {
        if let cs = charset?.trimmingCharacters(in: .whitespaces), !cs.isEmpty {
            let cfEnc = CFStringConvertIANACharSetNameToEncoding(cs as CFString)
            if cfEnc != kCFStringEncodingInvalidId {
                let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
                if let s = String(data: data, encoding: String.Encoding(rawValue: nsEnc)) { return s }
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    /// RFC 2047 encoded-word başlıklarını çözer: `=?charset?B/Q?...?=`
    static func decodeEncodedWords(_ input: String) -> String {
        // Bitişik encoded-word'ler arasındaki boşluk yok sayılır (RFC 2047 §6.2).
        var s = input
        if let glue = try? NSRegularExpression(pattern: "\\?=\\s+=\\?") {
            s = glue.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "?==?")
        }
        guard let re = try? NSRegularExpression(
            pattern: "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?=") else { return s }

        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }

        var result = ""
        var last = 0
        for m in matches {
            if m.range.location > last {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            }
            let charset = ns.substring(with: m.range(at: 1))
            let enc = ns.substring(with: m.range(at: 2)).uppercased()
            let text = ns.substring(with: m.range(at: 3))
            let data: Data
            if enc == "B" {
                data = Data(base64Encoded: text) ?? Data()
            } else {  // Q: '_' = boşluk, ardından quoted-printable
                let q = text.replacingOccurrences(of: "_", with: " ")
                data = decodeQuotedPrintable([UInt8](q.data(using: .isoLatin1) ?? Data(q.utf8)))
            }
            result += decodeCharset(data, charset: charset)
            last = m.range.location + m.range.length
        }
        if last < ns.length { result += ns.substring(from: last) }
        return result
    }

    static func parseAddress(_ s: String) -> (name: String?, address: String?) {
        let str = s.trimmingCharacters(in: .whitespaces)
        if let lt = str.range(of: "<"),
           let gt = str.range(of: ">", range: lt.upperBound..<str.endIndex) {
            let addr = String(str[lt.upperBound..<gt.lowerBound]).trimmingCharacters(in: .whitespaces)
            let name = String(str[..<lt.lowerBound])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.isEmpty ? nil : name, addr.isEmpty ? nil : addr)
        }
        if str.contains("@") { return (nil, str) }
        return (str.isEmpty ? nil : str, nil)
    }

    private static let dateFormatters: [DateFormatter] = {
        ["EEE, d MMM yyyy HH:mm:ss Z",
         "d MMM yyyy HH:mm:ss Z",
         "EEE, d MMM yyyy HH:mm Z",
         "EEE, d MMM yyyy HH:mm:ss"].map { format in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = format
            return df
        }
    }()

    static func parseDate(_ s: String) -> Date? {
        var str = s
        if let paren = str.range(of: " (") { str = String(str[..<paren.lowerBound]) }  // "(UTC)" vb. at
        str = str.trimmingCharacters(in: .whitespaces)
        for df in dateFormatters {
            if let d = df.date(from: str) { return d }
        }
        return nil
    }

    static func stripHTML(_ html: String) -> String {
        var s = html.replacingOccurrences(
            of: "(?s)<(script|style)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
                        "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }

    static func collapseWhitespace(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
    }
}
