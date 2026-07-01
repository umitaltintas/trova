import Foundation

/// Bir konuşmadaki (aynı `threadKey`) mailleri okunabilir bir "zaman çizelgesine" çeviren saf,
/// yan etkisiz, deterministik bir modül. Okuma panelindeki dikey konuşma akışı bunu kullanır;
/// çekirdek olduğu için test edilebilir. `ThreadGrouping` konuşmaları BİRBİRİNDEN ayırır; bu modül
/// ise TEK bir konuşmanın içini kronolojik akışa dizer.
///
/// İki adım:
///  1. RFC822 `messageID`'ye göre TEKİLLEŞTİR — aynı mantıksal mail birden çok kutuda (Gelen +
///     "Tümü"/arşiv gibi) kopya olarak durabilir. `messageID` nil ya da boş olanlar anahtarsızdır
///     ve ELENMEZ (her biri korunur). Aynı `messageID`'nin ilk görülen (girdi sırasında en baştaki)
///     kopyası tutulur; gerisi atılır → deterministik.
///  2. Kronolojik ARTAN sırala — en eski üstte, konuşma yukarıdan aşağı okunur. Tarihi nil olanlar
///     en sona gider. Eşit tarihlerde girdi sırası korunur (kararlı).
public enum ConversationTimeline {

    /// `messages`'i tekilleştirip kronolojik artan sıraya dizer.
    ///
    /// - `messageID` (RFC822) dolu olan kopyalardan yalnız ilk görüleni tutulur; nil/boş
    ///   `messageID`'ler anahtarsız sayılıp hepsi korunur.
    /// - En eski mail üstte, en yeni altta; tarihsiz (`date == nil`) mailler en sonda.
    /// - Sıralama kararlıdır: eşit tarihte (veya iki tarihsizde) girdi sırası korunur.
    public static func timeline(_ messages: [SearchHit]) -> [SearchHit] {
        // 1) messageID dedup — girdi sırasında gez, non-nil/non-boş anahtarın ilk kopyasını tut.
        //    Orijinal indeksi de sakla: sonraki sıralamada eşit tarih için kararlı tie-break.
        var seen: Set<String> = []
        var kept: [(offset: Int, hit: SearchHit)] = []
        kept.reserveCapacity(messages.count)
        for (offset, hit) in messages.enumerated() {
            let key = hit.messageID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if key.isEmpty {
                kept.append((offset, hit))          // anahtarsız → her zaman korunur
            } else if seen.insert(key).inserted {
                kept.append((offset, hit))          // bu messageID'nin ilk görülen kopyası
            }
            // else: aynı messageID'nin sonraki kopyası → atla.
        }

        // 2) Kronolojik artan sırala; tarihsizler sona; eşitlikte girdi sırası (kararlı).
        return kept
            .sorted { olderFirst(($0.offset, $0.hit.date), ($1.offset, $1.hit.date)) }
            .map(\.hit)
    }

    /// "En eski önce" karşılaştırıcısı: daha küçük tarih önce gelir; `nil` her zaman sona gider;
    /// eşit tarihte (veya ikisi de `nil`) küçük `offset` (girdi sırası) önce gelir → kararlı.
    private static func olderFirst(_ a: (offset: Int, date: Date?),
                                   _ b: (offset: Int, date: Date?)) -> Bool {
        switch (a.date, b.date) {
        case let (l?, r?):
            if l == r { return a.offset < b.offset }
            return l < r
        case (nil, nil):
            return a.offset < b.offset
        case (nil, _):
            return false          // a tarihsiz → sona
        case (_, nil):
            return true           // b tarihsiz → a önce
        }
    }
}
