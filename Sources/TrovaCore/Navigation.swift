import Foundation

/// Liste içinde klavyeyle (önceki/sonraki) gezinme için saf yardımcı.
/// UI'dan bağımsızdır; yalnızca sıralı id listesi üzerinde komşu seçimini hesaplar.
public enum Navigation {
    /// Sıralı id listesinde `current`'tan `delta` kadar (genelde +1/-1) komşu id'yi döndürür.
    /// Uçlarda kenetlenir (wrap YOK). Liste boşsa nil. current nil/listede yoksa: delta>0 → ilk, delta<0 → son.
    public static func adjacent(ids: [String], current: String?, delta: Int) -> String? {
        if ids.isEmpty { return nil }
        // current yok veya listede değilse: yöne göre uçtan başla.
        guard let current, let index = ids.firstIndex(of: current) else {
            return delta > 0 ? ids.first : ids.last
        }
        // Yeni indeksi geçerli aralığa kenetle (uçlarda aynı id'yi döndürür, nil değil).
        let target = min(max(index + delta, 0), ids.count - 1)
        return ids[target]
    }
}
