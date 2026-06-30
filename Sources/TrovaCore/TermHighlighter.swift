import Foundation

/// Metin İÇİNDEKİ bir vurgu aralığı. Ofsetler Character (grafem) birimindedir; böylece hem
/// `AttributedString` (Character-tabanlı) hem de NSRange'e (UTF-16) güvenle çevrilebilir.
public struct HighlightRange: Equatable, Sendable {
    public let start: Int   // metindeki başlangıç karakter ofseti
    public let length: Int  // vurgunun karakter uzunluğu
    public init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }
}

/// Verilen metinde, arama terimlerinin TÜM geçişlerini (Türkçe yerele duyarlı, büyük/küçük harf
/// DUYARSIZ) bulup vurgu aralıkları olarak döndüren saf (yan etkisiz) yardımcı. Okuma panelinde
/// tam gövde vurgusu için kullanılır (SnippetExtractor ile aynı eşleştirme: `TermMatching`).
///
/// - Çakışan veya bitişik eşleşmeler tek bir aralığa birleştirilir (görsel olarak temiz vurgu).
/// - Boş metin veya boş terim listesi → []. Çok kısa/boş terimleri ÇAĞIRAN eler (`highlightTerms`
///   zaten <2 harfli token'ları ve operatör/tarih kelimelerini ayıklar).
public enum TermHighlighter {
    /// `text` içinde `terms`'ün tüm geçişlerini bulur; örtüşen/bitişik aralıkları birleştirip
    /// `start` artan sırada döndürür. Ofsetler `text`'in Character indekslerine göredir.
    public static func ranges(in text: String, terms: [String]) -> [HighlightRange] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }
        let normTerms = TermMatching.normalize(terms)
        guard !normTerms.isEmpty else { return [] }

        let (lowerChars, map) = TermMatching.lowercaseWithMap(chars)
        let matches = TermMatching.findMatches(lowerChars: lowerChars, mapToOrig: map,
                                               origCount: chars.count, terms: normTerms)
        guard !matches.isEmpty else { return [] }
        return merge(matches)
    }

    /// `lo` sırasına göre gelen eşleşmeleri tek aralıklara indirger: örtüşen (`lo < hi`) veya
    /// bitişik (`lo == hi`) eşleşmeler birleşir; aralarında boşluk olanlar ayrı kalır.
    private static func merge(_ matches: [TermMatching.Match]) -> [HighlightRange] {
        var result: [HighlightRange] = []
        var curLo = matches[0].lo
        var curHi = matches[0].hi
        for m in matches.dropFirst() {
            if m.lo <= curHi {
                curHi = max(curHi, m.hi)          // örtüşen/bitişik → genişlet
            } else {
                result.append(HighlightRange(start: curLo, length: curHi - curLo))
                curLo = m.lo; curHi = m.hi
            }
        }
        result.append(HighlightRange(start: curLo, length: curHi - curLo))
        return result
    }
}
