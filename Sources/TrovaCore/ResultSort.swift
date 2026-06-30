import Foundation

/// Arama sonuçlarının kullanıcı tarafından seçilen sıralama düzeni.
public enum ResultSort: String, CaseIterable, Sendable {
    case relevance   // alaka — arama motorunun verdiği sıra (varsayılan)
    case newest      // en yeni önce
    case oldest      // en eski önce

    /// Kullanıcıya gösterilecek Türkçe etiket.
    public var label: String {
        switch self {
        case .relevance: return "Alaka"
        case .newest:    return "En yeni"
        case .oldest:    return "En eski"
        }
    }
}

/// `SearchHit` listesini seçilen düzene göre sıralayan saf yardımcı.
public enum ResultSorter {
    /// Sonuçları `order` düzenine göre sıralar:
    /// - `relevance`: girdi sırasını AYNEN korur (alaka sırası bozulmaz).
    /// - `newest`: tarihe göre azalan (en yeni başta).
    /// - `oldest`: tarihe göre artan (en eski başta).
    ///
    /// Tarihi olmayan (`nil`) sonuçlar HER İKİ yönde de listenin SONUNA gider.
    /// Sıralama kararlıdır: eşit tarihli (veya ikisi de `nil`) sonuçlar girdi
    /// sırasını korur. `resultSort` değişimi yeniden sorgu gerektirmez; aynı
    /// listeyi yeniden sıralamak için kullanılır.
    public static func sort(_ hits: [SearchHit], by order: ResultSort) -> [SearchHit] {
        switch order {
        case .relevance:
            return hits
        case .newest, .oldest:
            let ascending = (order == .oldest)
            // Kararlılık için her sonuca girdi indeksini iliştiririz; eşitlikte
            // (aynı tarih veya iki nil) bu indekse göre çözeriz.
            return hits.enumerated()
                .sorted { lhs, rhs in
                    switch (lhs.element.date, rhs.element.date) {
                    case let (l?, r?):
                        if l == r { return lhs.offset < rhs.offset }   // eşit tarih → girdi sırası
                        return ascending ? (l < r) : (l > r)
                    case (nil, nil):
                        return lhs.offset < rhs.offset                  // ikisi de nil → girdi sırası
                    case (nil, _):
                        return false                                   // nil her zaman sona
                    case (_, nil):
                        return true
                    }
                }
                .map(\.element)
        }
    }
}
