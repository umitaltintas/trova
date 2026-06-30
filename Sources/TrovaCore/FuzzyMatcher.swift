import Foundation

/// Komut paleti / hızlı filtreleme için basit altdizi (subsequence) tabanlı bulanık eşleştirme.
/// Sorgu, adayda sırayla (ardışık şart değil) geçiyorsa bir skor döner; geçmiyorsa nil.
/// Yüksek skor = daha iyi eşleşme: ardışıklık, kelime başı ve erken konum ödüllendirilir.
public enum FuzzyMatcher {
    public static func score(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.lowercased(with: Locale(identifier: "tr_TR")))
        let c = Array(candidate.lowercased(with: Locale(identifier: "tr_TR")))
        if q.isEmpty { return 0 }            // boş sorgu her şeyi nötr skorla eşler
        guard q.count <= c.count else { return nil }

        var qi = 0
        var total = 0
        var streak = 0
        var prevMatch = -2
        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            var bonus = 1
            if prevMatch == ci - 1 { streak += 1; bonus += streak * 2 } else { streak = 0 }
            if ci == 0 || c[ci - 1] == " " { bonus += 5 }   // kelime başı eşleşmesi
            if ci < 4 { bonus += (4 - ci) }                 // erken konum
            total += bonus
            prevMatch = ci
            qi += 1
        }
        return qi == q.count ? total : nil
    }

    /// Adayları sorguya göre filtreleyip skora göre azalan sırada döndürür (eşleşmeyenler atılır).
    /// Boş sorguda sıra korunur. `key` her öğeden eşleştirilecek metni verir.
    public static func rank<T>(_ query: String, _ items: [T], key: (T) -> String) -> [T] {
        if query.isEmpty { return items }
        return items
            .compactMap { item -> (item: T, score: Int)? in
                score(query, key(item)).map { (item, $0) }
            }
            .sorted { $0.score > $1.score }
            .map(\.item)
    }
}
