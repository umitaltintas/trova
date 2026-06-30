import Foundation

/// Snippet metni İÇİNDEKİ bir vurgu aralığı. Ofsetler Character (grafem) birimindedir;
/// böylece AttributedString gibi Character-tabanlı görünümlere doğrudan haritalanır.
public struct SnippetHighlight: Equatable, Sendable {
    public let start: Int   // snippet.text içindeki başlangıç karakter ofseti
    public let length: Int  // vurgunun karakter uzunluğu
    public init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }
}

/// Bir arama sonucu için seçilmiş gövde parçası + içindeki terim vurguları.
public struct Snippet: Equatable, Sendable {
    public let text: String
    public let highlights: [SnippetHighlight]
    public init(text: String, highlights: [SnippetHighlight]) {
        self.text = text
        self.highlights = highlights
    }
}

/// Gövdeden, sorgu terimlerini en yoğun içeren okunabilir bir pencere seçip terim
/// konumlarını vurgu aralığı olarak döndüren saf (yan etkisiz) yardımcı.
///
/// - Eşleştirme büyük/küçük harf DUYARSIZdır ve Türkçe yerele dikkatlidir (İ/ı, ş, ğ, ç, ö, ü).
/// - Ofsetler Character birimindedir; küçük/büyük harf eşlemesi karakter sayısını
///   değiştirebileceğinden eşleşmeler bir indeks haritasıyla orijinal metne taşınır.
/// - Kısa terimleri (1 harf) ve operatör/tarih kelimelerini ÇAĞIRAN taraf elemelidir;
///   bu tip yalnız kendisine verilen `terms` listesini kullanır.
public enum SnippetExtractor {
    private static let locale = Locale(identifier: "tr_TR")
    private static let ellipsis = "…"

    /// En çok DISTINCT terim eşleşmesi içeren ~`maxLength`'lik pencereyi seçer; kelime
    /// sınırında kırpar; gerekirse baş/sona "…" ekler. Vurgu ofsetleri snippet metnine göredir.
    ///
    /// - Boş gövde → boş Snippet.
    /// - Eşleşme yoksa → baştan `maxLength` karakter (kırpıldıysa "…"), vurgular boş.
    /// - Çok terim → en yoğun (en çok farklı terim içeren) pencere.
    public static func make(body: String, terms: [String], maxLength: Int = 200) -> Snippet {
        let chars = Array(body)
        guard !chars.isEmpty else { return Snippet(text: "", highlights: []) }
        let maxLen = max(1, maxLength)

        // Terimleri normalize et: küçük harf (Türkçe), boşları/kopyaları ele.
        let normTerms = normalize(terms)
        guard !normTerms.isEmpty else { return leadingSnippet(chars: chars, maxLen: maxLen) }

        // Gövdeyi karakter karakter küçük harfe indir ve her küçük-harf karakterinin
        // orijinal karakter indeksini izle (Türkçe eşleme 1:1 olmayabilir).
        let (lowerChars, mapToOrig) = lowercaseWithMap(chars)
        let matches = findMatches(lowerChars: lowerChars, mapToOrig: mapToOrig,
                                  origCount: chars.count, terms: normTerms)
        guard !matches.isEmpty else { return leadingSnippet(chars: chars, maxLen: maxLen) }

        // En yoğun çekirdek aralığı seç, sonra bütçeye göre bağlamla genişlet.
        let core = bestWindow(matches: matches, maxLen: maxLen)
        return buildSnippet(chars: chars, matches: matches,
                            coreLo: core.lo, coreHi: core.hi, maxLen: maxLen)
    }

    // MARK: - Yardımcılar

    private struct Match { let lo: Int; let hi: Int; let termIndex: Int }   // orijinal karakter aralığı [lo, hi)

    private static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    /// Terimleri küçük harfe indirip kırpar, boşları atar ve tekilleştirir.
    private static func normalize(_ terms: [String]) -> [[Character]] {
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
    private static func lowercaseWithMap(_ chars: [Character]) -> (lower: [Character], map: [Int]) {
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
    private static func findMatches(lowerChars: [Character], mapToOrig: [Int],
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

    /// Genişliği `maxLen`'i aşmayan ve en çok DISTINCT terim içeren eşleşme öbeğinin
    /// orijinal karakter aralığını [lo, hi) döndürür (eşitlikte daha çok eşleşme kazanır).
    private static func bestWindow(matches: [Match], maxLen: Int) -> (lo: Int, hi: Int) {
        var best = (distinct: -1, total: 0, lo: matches[0].lo, hi: matches[0].hi)
        var termCounts: [Int: Int] = [:]
        var l = 0
        for r in matches.indices {
            termCounts[matches[r].termIndex, default: 0] += 1
            // Çekirdek genişliği bütçeyi aşıyorsa soldan daralt (en az bir eşleşme kalsın).
            while l < r && matches[r].hi - matches[l].lo > maxLen {
                let key = matches[l].termIndex
                if let c = termCounts[key] {
                    if c <= 1 { termCounts[key] = nil } else { termCounts[key] = c - 1 }
                }
                l += 1
            }
            let distinct = termCounts.count
            let total = r - l + 1
            if distinct > best.distinct || (distinct == best.distinct && total > best.total) {
                best = (distinct, total, matches[l].lo, matches[r].hi)
            }
        }
        return (best.lo, best.hi)
    }

    /// Çekirdek aralığı bağlamla `maxLen`'e kadar genişletir, kelime sınırına hizalar,
    /// "…" ekler ve vurguları snippet metnine göre konumlandırır.
    private static func buildSnippet(chars: [Character], matches: [Match],
                                     coreLo: Int, coreHi: Int, maxLen: Int) -> Snippet {
        let n = chars.count
        let coreWidth = coreHi - coreLo
        // Kalan bütçeyi iki yana bağlam olarak dağıt.
        let remaining = max(0, maxLen - coreWidth)
        let leftPad = remaining / 2
        let rightPad = remaining - leftPad
        var lo = max(0, coreLo - leftPad)
        var hi = min(n, coreHi + rightPad)
        // Kelime ortasından kırpmamak için sınırlara hizala (çekirdeği koruyarak).
        lo = snapLeft(chars: chars, lo: lo, limit: coreLo)
        hi = snapRight(chars: chars, hi: hi, limit: coreHi)
        // Baş/sondaki boşlukları buda.
        while lo < coreLo && chars[lo].isWhitespace { lo += 1 }
        while hi > coreHi && chars[hi - 1].isWhitespace { hi -= 1 }

        let needLead = lo > 0
        let needTrail = hi < n
        var text = ""
        if needLead { text += ellipsis }
        text += String(chars[lo..<hi])
        if needTrail { text += ellipsis }

        let offset = needLead ? ellipsis.count : 0     // "…" tek Character → ofset +1
        var highlights: [SnippetHighlight] = []
        for match in matches where match.lo >= lo && match.hi <= hi {
            highlights.append(SnippetHighlight(start: match.lo - lo + offset,
                                               length: match.hi - match.lo))
        }
        highlights.sort { $0.start < $1.start }
        return Snippet(text: text, highlights: highlights)
    }

    /// Sol kenarı kelime başına ileri taşır (kısmi baş kelimeyi atar); `limit`'i (çekirdek) geçmez.
    private static func snapLeft(chars: [Character], lo: Int, limit: Int) -> Int {
        var lo = lo
        while lo > 0 && lo < limit && isWord(chars[lo - 1]) && isWord(chars[lo]) { lo += 1 }
        return lo
    }

    /// Sağ kenarı kelime sonuna geri taşır (kısmi son kelimeyi atar); `limit`'in (çekirdek) altına inmez.
    private static func snapRight(chars: [Character], hi: Int, limit: Int) -> Int {
        var hi = hi
        while hi < chars.count && hi > limit && isWord(chars[hi - 1]) && isWord(chars[hi]) { hi -= 1 }
        return hi
    }

    /// Eşleşme yokken: baştan `maxLen` karakter; kelime sınırında kırpar ve kırpıldıysa "…" ekler.
    private static func leadingSnippet(chars: [Character], maxLen: Int) -> Snippet {
        let n = chars.count
        if n <= maxLen { return Snippet(text: String(chars), highlights: []) }
        var hi = snapRight(chars: chars, hi: maxLen, limit: 1)
        while hi > 1 && chars[hi - 1].isWhitespace { hi -= 1 }
        return Snippet(text: String(chars[0..<hi]) + ellipsis, highlights: [])
    }
}
