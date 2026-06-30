import Foundation

/// Aynı konuya ait mailleri ("Re:", "Ynt:", "Fwd:" gibi önekler farklı olsa da) tek bir
/// konuşma altında toplayan saf, yan etkisiz, deterministik bir modül. Arama sonuçlarını
/// (`SearchHit` dizisi) gruplu göstermek için kullanılır; çekirdek olduğu için test edilebilir.
///
/// İki adımlı çalışır:
///  1. `normalizeSubject` ile bir konunun baştaki yanıt/iletme öneklerini soyup gövdeyi bulur.
///  2. `group` ile gövdeyi büyük/küçük harf ve boşluk duyarsız (Türkçe locale) bir anahtara
///     indirger ve aynı anahtara düşen hit'leri tek `ThreadGroup` altında toplar.
public enum ThreadGrouping {

    /// Türkçe büyük/küçük harf dönüşümü için sabit locale ("İ"→"i", "I"→"ı").
    /// Anahtar karşılaştırması ve önek tanıma bu locale'i kullanır.
    private static let turkish = Locale(identifier: "tr_TR")

    /// Boş (yalnız öneklerden ibaret) konuların gruplandığı sabit anahtar/gösterim.
    public static let emptyKey = "(konu yok)"

    /// Tanınan yanıt/iletme önekleri — Türkçe locale ile küçük harfe indirilmiş biçimleriyle.
    /// İngilizce: re, fwd/fw; Türkçe: ynt (yanıt), yan, ilt/ılt (ilet — "İlt" ve "Ilt" ayrı
    /// küçük-harf biçimleri verir), cevap; Almanca: aw, wg; İsveççe: sv.
    private static let knownPrefixes: Set<String> = [
        "re", "fwd", "fw",
        "ynt", "yan", "ilt", "ılt", "cevap",
        "aw", "sv", "wg",
    ]

    /// Baştaki bir öneki (harf öbeği + opsiyonel "[2]"/"(3)" sayacı + ":") yakalar.
    /// Yalnız `\p{L}+` (Unicode harfleri) + iki nokta gerekir; sayaç isteğe bağlıdır.
    private static let prefixRegex = try! NSRegularExpression(
        pattern: "^\\s*(\\p{L}+)\\s*(?:\\[\\s*\\d+\\s*\\]|\\(\\s*\\d+\\s*\\))?\\s*:",
        options: [])

    /// Bir konunun baştaki yanıt/iletme öneklerini (büyük/küçük harf duyarsız, TEKRARLI biçimde)
    /// soyup gövdeyi döndürür. Örn. "Re: Fwd: Ynt: konu" → "konu", "Re[2]: x" → "x".
    /// Yalnız tanınan önekler ("Re", "Ynt", "İlt", "AW" …) soyulur; rastgele "Kelime:" soyulmaz.
    /// Baş/son boşluklar kırpılır. Boş ya da yalnız öneklerden ibaret konu → boş string döner.
    public static func normalizeSubject(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // En baştaki tanınan öneki soy; soydukça yeni önek açığa çıkabilir → döngü.
        while let range = leadingPrefixRange(in: s) {
            s = String(s[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    /// `s`'in başında tanınan bir önek varsa o önek+ayraç bölgesini, yoksa nil döner.
    private static func leadingPrefixRange(in s: String) -> Range<String.Index>? {
        guard !s.isEmpty else { return nil }
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = prefixRegex.firstMatch(in: s, options: [], range: full) else { return nil }
        let wordRange = match.range(at: 1)
        guard wordRange.location != NSNotFound else { return nil }
        let word = ns.substring(with: wordRange).lowercased(with: turkish)
        guard knownPrefixes.contains(word) else { return nil }
        return Range(match.range, in: s)
    }

    /// Bir ham konudan gruplama anahtarını üretir: önekleri soyar, boşlukları teke indirip kırpar,
    /// Türkçe locale ile küçük harfe çevirir. Sonuç boşsa `emptyKey` döner. Böylece "RE:  Konu" ve
    /// "konu" aynı anahtara düşer.
    public static func groupKey(for raw: String?) -> String {
        let body = normalizeSubject(raw ?? "")
        let collapsed = body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let key = collapsed.lowercased(with: turkish)
        return key.isEmpty ? emptyKey : key
    }

    /// Bir konuşma grubu: aynı normalize anahtarına düşen mailler.
    public struct ThreadGroup: Sendable, Identifiable {
        /// Normalize edilmiş gruplama anahtarı (büyük/küçük harf ve boşluk duyarsız).
        public let key: String
        /// Gösterim için en yeni üyenin ORİJİNAL konusu (önekleriyle). Konu yoksa `emptyKey`.
        public let representativeSubject: String
        /// Grup üyeleri, en yeniden eskiye sıralı (tarihsizler en sonda).
        public let members: [SearchHit]
        /// Grubun en yeni üyesinin tarihi (hepsi tarihsizse nil).
        public let latestDate: Date?
        /// Üye sayısı.
        public var count: Int { members.count }
        /// Okunmamış üye sayısı (isRead == false olanlar; isRead nil → sayılmaz).
        public let unreadCount: Int

        /// `Identifiable` — ForEach için kararlı kimlik (anahtarın kendisi).
        public var id: String { key }

        public init(key: String, representativeSubject: String, members: [SearchHit],
                    latestDate: Date?, unreadCount: Int) {
            self.key = key
            self.representativeSubject = representativeSubject
            self.members = members
            self.latestDate = latestDate
            self.unreadCount = unreadCount
        }
    }

    /// `hits`'i normalize anahtara göre konuşmalara toplar.
    ///
    /// - Üyeler grup içinde en yeniden eskiye sıralanır; tarihsiz (`nil`) üyeler en sona gider.
    /// - Gruplar `latestDate`'e göre AZALAN sıralanır (en yeni konuşma üstte); tarihsiz gruplar
    ///   en sona gider.
    /// - Sıralama kararlıdır: eşit tarihte girdi sırası korunur (orijinal index ile tie-break).
    public static func group(_ hits: [SearchHit]) -> [ThreadGroup] {
        // Anahtar → (ilk görülme indeksi, üyeler[(index, hit)]). Sözlük sırası deterministik değil;
        // hem grup içi hem gruplar arası sıralamayı sonra orijinal index'e göre kararlı yaparız.
        struct Bucket { var firstIndex: Int; var members: [(offset: Int, hit: SearchHit)] }
        var buckets: [String: Bucket] = [:]
        var order: [String] = []   // ilk görülme sırası (deterministik gezinme için)

        for (offset, hit) in hits.enumerated() {
            let key = groupKey(for: hit.subject)
            if buckets[key] != nil {
                buckets[key]!.members.append((offset, hit))
            } else {
                buckets[key] = Bucket(firstIndex: offset, members: [(offset, hit)])
                order.append(key)
            }
        }

        var groups: [ThreadGroup] = []
        groups.reserveCapacity(order.count)
        for key in order {
            guard let bucket = buckets[key] else { continue }
            // Üyeleri en yeniden eskiye sırala (tarihsizler sona, eşitlikte girdi sırası).
            let sorted = bucket.members
                .sorted { newerFirst(($0.offset, $0.hit.date), ($1.offset, $1.hit.date)) }
            let members = sorted.map(\.hit)
            let newest = members[0]   // grup en az bir üye içerir
            let latestDate = newest.date
            let unread = members.reduce(0) { $0 + (($1.isRead == false) ? 1 : 0) }
            groups.append(ThreadGroup(
                key: key,
                representativeSubject: newest.subject ?? emptyKey,
                members: members,
                latestDate: latestDate,
                unreadCount: unread))
        }

        // Gruplar arası: latestDate azalan, tarihsizler sona, eşitlikte ilk görülme sırası.
        return groups
            .enumerated()
            .sorted { lhs, rhs in
                // İlk görülme indeksini buckets'tan al (kararlı tie-break).
                let li = buckets[lhs.element.key]?.firstIndex ?? lhs.offset
                let ri = buckets[rhs.element.key]?.firstIndex ?? rhs.offset
                return newerFirst((li, lhs.element.latestDate), (ri, rhs.element.latestDate))
            }
            .map(\.element)
    }

    /// "En yeni önce" karşılaştırıcısı: daha büyük tarih önce gelir; `nil` her zaman sona gider;
    /// eşit tarihte (veya ikisi de `nil`) küçük `offset` (girdi sırası) önce gelir → kararlı.
    private static func newerFirst(_ a: (offset: Int, date: Date?),
                                   _ b: (offset: Int, date: Date?)) -> Bool {
        switch (a.date, b.date) {
        case let (l?, r?):
            if l == r { return a.offset < b.offset }
            return l > r
        case (nil, nil):
            return a.offset < b.offset
        case (nil, _):
            return false          // a tarihsiz → sona
        case (_, nil):
            return true           // b tarihsiz → a önce
        }
    }
}
