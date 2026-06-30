import Foundation

/// Otomatik arama geçmişi: kullanıcı arama yaptıkça sorgular en yeni başta tutulur.
/// Saf bir değer tipi — büyük/küçük harf duyarsız tekrarları eler ve `limit`'e göre kırpar.
public struct RecentSearches: Equatable, Sendable {
    /// Geçmiş sorgular, en yeni başta.
    public private(set) var items: [String]
    /// Saklanacak en fazla sorgu sayısı (en az 1).
    public let limit: Int

    public init(items: [String] = [], limit: Int = 10) {
        // Limit en az 1 olmalı; geçersiz değerleri 1'e yükselt.
        self.limit = max(1, limit)
        // Girişi temizle: trim, boşları at, tekrarları (case-insensitive) ele, sonra kırp.
        self.items = Self.normalize(items, limit: self.limit)
    }

    /// Yeni bir sorguyu en başa ekler. Boş/whitespace sorgu yok sayılır;
    /// var olan aynı sorgu (case-insensitive) eski konumundan kaldırılıp başa taşınır.
    public mutating func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Aynı sorgunun eski kaydını kaldır (büyük/küçük harf duyarsız).
        let key = Self.foldKey(trimmed)
        items.removeAll { Self.foldKey($0) == key }
        // En başa ekle ve limit aşılırsa en eskileri (sondan) at.
        items.insert(trimmed, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    /// Tüm geçmişi temizler.
    public mutating func clear() {
        items.removeAll()
    }

    // MARK: - Yardımcılar

    /// Bir sorguyu karşılaştırma anahtarına çevirir (Türkçe duyarlı küçük harf).
    private static func foldKey(_ s: String) -> String {
        s.lowercased(with: Locale(identifier: "tr_TR"))
    }

    /// Listeyi normalize eder: trim, boşları at, ilk göründüğünü koruyarak tekrarları ele, limit'e kırp.
    private static func normalize(_ raw: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let key = foldKey(trimmed)
            if seen.contains(key) { continue }   // ilk görüleni koru, sonrakileri at
            seen.insert(key)
            result.append(trimmed)
            if result.count == limit { break }
        }
        return result
    }
}
