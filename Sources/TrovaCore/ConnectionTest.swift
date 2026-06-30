import Foundation

/// Bir sağlayıcıya yapılan canlı bağlantı testinin durumu.
public enum ConnectionStatus: Equatable, Sendable {
    case ok            // 2xx — istek başarılı
    case unauthorized  // 401/403 — anahtar geçersiz/yetkisiz
    case notFound      // 404 — model/uç nokta yok
    case network       // taşıma katmanı hatası (DNS/offline/timeout)
    case unknown       // diğer HTTP kodları veya çözümlenemeyen hata
}

/// Tek bir servisin (LLM / embedding) bağlantı testi sonucu — UI'da satır satır gösterilir.
public struct ConnectionResult: Equatable, Sendable {
    public let service: String
    public let status: ConnectionStatus
    public let detail: String
    public init(service: String, status: ConnectionStatus, detail: String) {
        self.service = service
        self.status = status
        self.detail = detail
    }
}

/// HTTP durum/hata → Türkçe kullanıcı mesajı. Çekirdek mantık SAF (ağsız) → test edilebilir.
/// Asıl ağ isteği app katmanında (AppModel) atılır; burada yalnız sınıflandırma/mesaj üretilir.
public enum ConnectionTest {

    /// HTTP durum kodu (varsa) ve hata açıklamasından bağlantı durumunu sınıflandırır.
    /// 2xx→ok, 401/403→unauthorized, 404→notFound, kod yoksa ağ açıklaması→network, diğer→unknown.
    public static func classify(statusCode: Int?, errorDescription: String?) -> ConnectionStatus {
        if let code = statusCode {
            switch code {
            case 200..<300: return .ok
            case 401, 403:  return .unauthorized
            case 404:       return .notFound
            default:        return .unknown
            }
        }
        if let description = errorDescription, isNetworkFailure(description) { return .network }
        return .unknown
    }

    /// Bir duruma karşılık gelen, servis adını içeren Türkçe kullanıcı mesajı üretir.
    public static func message(service: String, status: ConnectionStatus, detail: String?) -> String {
        switch status {
        case .ok:           return "\(service): Bağlantı başarılı"
        case .unauthorized: return "\(service): Geçersiz API anahtarı"
        case .notFound:     return "\(service): Model/uç nokta bulunamadı"
        case .network:      return "\(service): Ağa ulaşılamadı"
        case .unknown:
            let raw = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let raw, !raw.isEmpty { return "\(service): Bilinmeyen hata — \(raw.prefix(200))" }
            return "\(service): Bilinmeyen hata"
        }
    }

    /// `complete`/`embed` çağrısının sonucundan (başarı → error=nil) tam bir `ConnectionResult` kurar.
    /// HTTP kodunu önce bilinen hata tiplerinden (`EmbeddingError`/`HTTPClientError`), olmazsa hata
    /// mesajındaki "HTTP <kod>" deseninden çıkarır; çıkaramazsa ağ/bilinmeyen olarak değerlendirir.
    public static func result(service: String, error: Error?) -> ConnectionResult {
        guard let error else {
            return ConnectionResult(service: service, status: .ok,
                                    detail: message(service: service, status: .ok, detail: nil))
        }
        let description = describe(error)
        let status = classify(statusCode: httpStatus(from: error, description: description),
                              errorDescription: description)
        return ConnectionResult(service: service, status: status,
                                detail: message(service: service, status: status, detail: description))
    }

    // MARK: - Yardımcılar (saf)

    /// Bir hatadan HTTP durum kodunu çıkarır: önce bilinen tipler, sonra "HTTP <kod>" metin deseni.
    static func httpStatus(from error: Error, description: String) -> Int? {
        if let embed = error as? EmbeddingError, case let .http(status, _) = embed { return status }
        if let http = error as? HTTPClientError, case let .http(status, _) = http { return status }
        return statusCode(fromText: description)
    }

    /// "HTTP 401: ..." gibi bir metnin içindeki ilk durum kodunu (üç haneli) ayrıştırır.
    static func statusCode(fromText text: String) -> Int? {
        guard let range = text.range(of: #"HTTP\s+\d{3}"#, options: .regularExpression) else { return nil }
        return Int(text[range].suffix(3))
    }

    private static func describe(_ error: Error) -> String {
        (error as? CustomStringConvertible)?.description ?? "\(error)"
    }

    /// Açıklama bir ağ/taşıma katmanı hatasına mı işaret ediyor (kod yokken network ayrımı için).
    /// Çekirdek `transport` hataları "Ağ hatası: …" ile başlar; URLSession metinleri için ek işaretler.
    private static func isNetworkFailure(_ description: String) -> Bool {
        let lower = description.lowercased()
        let markers = ["ağ hatası", "offline", "internet", "hostname", "timed out",
                       "could not connect", "network connection", "host"]
        return markers.contains { lower.contains($0) }
    }
}
