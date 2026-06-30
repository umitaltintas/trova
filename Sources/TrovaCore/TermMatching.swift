import Foundation

/// Türkçe yerele duyarlı, büyük/küçük harf DUYARSIZ terim eşleştirme için paylaşılan saf (yan
/// etkisiz) yardımcı. Hem `SnippetExtractor` (en yoğun pencere seçimi) hem de `TermHighlighter`
/// (tüm gövdede vurgu) aynı eşleştirme mantığını buradan kullanır — kopyalama değil, tek kaynak.
///
/// - Ofsetler Character (grafem) birimindedir; Türkçe küçük/büyük harf eşlemesi karakter sayısını
///   değiştirebileceğinden eşleşmeler bir indeks haritasıyla orijinal metne taşınır (İ/ı, ş, ğ…).
enum TermMatching {
    /// Eşleştirmede kullanılan Türkçe yerel (İ/ı davranışı için kritik).
    static let locale = Locale(identifier: "tr_TR")

    /// Bir terim eşleşmesi: orijinal metindeki karakter aralığı [lo, hi) + hangi terim (termIndex).
    struct Match: Equatable { let lo: Int; let hi: Int; let termIndex: Int }

    /// Terimleri küçük harfe (Türkçe) indirip kırpar, boşları atar ve tekilleştirir.
    static func normalize(_ terms: [String]) -> [[Character]] {
        var seen = Set<String>()
        var result: [[Character]] = []
        for term in terms {
            let trimmed = term.lowercased(with: locale)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted { result.append(Array(trimmed)) }
        }
        return result
    }

    /// Küçük harfli karakter dizisi + her küçük-harf karakterinin orijinal indeksine haritası.
    static func lowercaseWithMap(_ chars: [Character]) -> (lower: [Character], map: [Int]) {
        var lower: [Character] = []
        var map: [Int] = []
        lower.reserveCapacity(chars.count)
        map.reserveCapacity(chars.count)
        for (i, ch) in chars.enumerated() {
            for lc in String(ch).lowercased(with: locale) {
                lower.append(lc)
                map.append(i)
            }
        }
        return (lower, map)
    }

    /// Tüm terimlerin (terim başına örtüşmeyen) eşleşmelerini orijinal karakter aralığı olarak bulur.
    /// Sonuç `lo` (eşitlikte `hi`) artan sıraya göre sıralanır.
    static func findMatches(lowerChars: [Character], mapToOrig: [Int],
                            origCount: Int, terms: [[Character]]) -> [Match] {
        var matches: [Match] = []
        let m = lowerChars.count
        for (ti, term) in terms.enumerated() {
            let t = term.count
            guard t > 0, t <= m else { continue }
            var k = 0
            while k <= m - t {
                var j = 0
                while j < t && lowerChars[k + j] == term[j] { j += 1 }
                if j == t {
                    let lo = mapToOrig[k]
                    let hi = (k + t - 1) < mapToOrig.count ? mapToOrig[k + t - 1] + 1 : origCount
                    matches.append(Match(lo: lo, hi: hi, termIndex: ti))
                    k += t                 // aynı terim için bir sonraki örtüşmeyen eşleşmeye atla
                } else {
                    k += 1
                }
            }
        }
        matches.sort { $0.lo != $1.lo ? $0.lo < $1.lo : $0.hi < $1.hi }
        return matches
    }
}
