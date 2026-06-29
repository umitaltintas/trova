import Foundation

/// Apple Mail'in `message://` derin-link şemasıyla belirli bir maili native Mail.app'te açar.
///
/// Şema Mac OS X Leopard'dan beri desteklenir: `message://%3C<MESSAGE-ID>%3E` —
/// köşeli parantezler `%3C`/`%3E` ile, Message-ID'nin kendisi ise yüzde-kodlanır.
/// Mailleri Mail'in kendi yerel deposundan okuduğumuz için Message-ID'ler birebir eşleşir.
public enum MailLink {
    /// Köşeli parantezli/parantezsiz bir Message-ID'den Mail.app derin-link URL'i üretir.
    /// Boş ya da geçersizse `nil` döner.
    public static func appleMailURL(messageID: String?) -> URL? {
        guard let raw = messageID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        // Köşeli parantezleri soy.
        var core = raw
        if core.hasPrefix("<") { core.removeFirst() }
        if core.hasSuffix(">") { core.removeLast() }
        core = core.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return nil }

        // RFC822 ayırıcıları (@ vb.) URL otoritesinde karışmasın diye unreserved dışını yüzde-kodla.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = core.addingPercentEncoding(withAllowedCharacters: unreserved),
              !encoded.isEmpty else { return nil }

        return URL(string: "message://%3C\(encoded)%3E")
    }
}
