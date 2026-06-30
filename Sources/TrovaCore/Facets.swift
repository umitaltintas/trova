import Foundation

/// Bir daraltma facet'i: tek bir gönderen ve eldeki sonuçlarda kaç hit'e sahip olduğu.
public struct Facet: Equatable, Sendable {
    /// Gösterilecek gönderen değeri (fromName boş değilse o, yoksa fromAddress).
    public let value: String
    /// Bu gönderene ait hit sayısı (filtre öncesi sonuç kümesinden).
    public let count: Int
    public init(value: String, count: Int) {
        self.value = value
        self.count = count
    }
}

/// Arama sonuçlarından istemci tarafı gönderen facet'leri türeten saf yardımcı.
/// Yeniden sorgu YAPMAZ; yalnız eldeki `[SearchHit]` dizisi üzerinde çalışır.
public enum Facets {
    // Türkçe locale: "İ"→"i", "I"→"ı" gibi dönüşümleri tutarlı kıldığından gruplama anahtarı
    // ve büyük/küçük harf duyarsız karşılaştırmalar için tek kaynak burasıdır.
    private static let locale = Locale(identifier: "tr_TR")

    /// Bir hit'in gösterilecek gönderen etiketi: `fromName` boş değilse o, yoksa `fromAddress`.
    /// İkisi de boş/anonimse `nil` (facet'lere dahil edilmez).
    private static func display(_ hit: SearchHit) -> String? {
        if let name = hit.fromName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let addr = hit.fromAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !addr.isEmpty {
            return addr
        }
        return nil
    }

    /// Gruplama/karşılaştırma anahtarı: gösterim değerinin Türkçe locale'de küçük harfli hali.
    private static func key(_ display: String) -> String {
        display.lowercased(with: locale)
    }

    /// Sonuçlardaki en sık gönderenleri sayılı facet'ler olarak döndürür.
    /// - Gösterilecek gönderen = `fromName` boş değilse o, yoksa `fromAddress`.
    /// - Gruplama küçük harfe (Türkçe locale) göre yapılır → aynı gönderenin farklı harf
    ///   büyüklüğündeki yazımları tek grupta birleşir; temsilci olarak ilk görülen yazım kullanılır.
    /// - Sıralama: `count` azalan; eşitlikte gösterim anahtarına göre alfabetik.
    /// - Boş/anonim gönderenler atlanır. En çok `limit` facet döner.
    public static func senders(_ hits: [SearchHit], limit: Int = 6) -> [Facet] {
        var counts: [String: Int] = [:]      // anahtar → sayı
        var labels: [String: String] = [:]   // anahtar → temsilci gösterim (ilk görülen yazım)
        for hit in hits {
            guard let display = display(hit) else { continue }
            let k = key(display)
            counts[k, default: 0] += 1
            if labels[k] == nil { labels[k] = display }
        }
        return counts.keys
            .sorted { a, b in
                if counts[a]! != counts[b]! { return counts[a]! > counts[b]! }  // sayı azalan
                return a < b                                                    // eşitlik → alfabetik
            }
            .prefix(limit)
            .map { Facet(value: labels[$0]!, count: counts[$0]!) }
    }

    /// Verilen gönderene (gösterim değeri, büyük/küçük harf duyarsız) ait hit'leri döndürür.
    /// İstemci tarafı filtre — yeniden sorgu yapmaz, girdi sırasını korur.
    public static func filter(_ hits: [SearchHit], bySender sender: String) -> [SearchHit] {
        let target = key(sender)
        return hits.filter { hit in
            guard let display = display(hit) else { return false }
            return key(display) == target
        }
    }
}
