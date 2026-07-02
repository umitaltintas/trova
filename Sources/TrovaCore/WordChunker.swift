import Foundation
import NaturalLanguage

/// Metni, yerel gömme modelinin token sınırına saygı gösterecek biçimde KELİME
/// sınırlarından parçalara böler (saf, deterministik, test edilebilir).
///
/// Neden gerekli: `NLContextualEmbedding(.turkish)` sabit bir azami dizi uzunluğuna
/// (~256 token) sahiptir. Bu sınırı aşan metnin kuyruğu vektöre hiç girmez — sessizce
/// düşer. Eskiden metin karakter bazlı (`prefix(2000)`) kırpılıyordu; 2000 karakter
/// Türkçe'de 256 token'ı rahatça aşar, dolayısıyla uzun maillerin kuyruğu aramada
/// kayboluyordu. Burada kelimelere göre bölerek her parçanın modele TAM girmesini
/// garanti ederiz; parça vektörleri çağıran tarafında ağırlıklı ortalanır.
///
/// Parça boyutu neden ~120 kelime? Türkçe eklemeli bir dildir; tek kelime kolayca birden
/// çok subword token'a bölünür (kötü durumda ~2 token/kelime). 256 / 2 ≈ 128 kelime;
/// güvenli marj için 120'ye yuvarlıyoruz — böylece 120 kelimelik bir parça pratikte
/// ~240 token'ı aşmaz ve model kuyruğu kesmez.
///
/// Üst sınır neden 8 parça? 8 × 120 = 960 kelime, çok uzun bir maili bile kapsar; ötesi
/// bilinçli olarak düşürülür ki dev mailler gömme süresini patlatmasın. Kaynak metin
/// üst katmanda (EmbeddingRunner.TextChunker) zaten karakter bazlı bir kez bölündüğünden
/// bu inç sınırı pratikte nadiren devreye girer.
public enum WordChunker {
    /// Parça başına azami kelime sayısı (256 token sınırına güvenli marj — bkz. tür yorumu).
    public static let defaultWordsPerChunk = 120
    /// Azami parça sayısı — dev mailler için gömme süresini sınırlar.
    public static let defaultMaxChunks = 8

    /// Metni kelime sınırlarından en çok `maxChunks` parçaya böler; her parça en çok
    /// `wordsPerChunk` kelime içerir ve kelime bütünlüğü asla bozulmaz.
    ///
    /// - Boş / yalnız boşluk metin → boş dizi (`[]`).
    /// - Sınırdan kısa (ya da kelime tokenı üretmeyen, ör. salt noktalama) metin →
    ///   tek parça: kırpılmamış, boşlukları budanmış tüm metin.
    /// - Parametreler test edilebilirlik için dışarı açıktır (küçük değerlerle hızlı,
    ///   deterministik birim testi).
    public static func chunks(_ text: String,
                              wordsPerChunk: Int = defaultWordsPerChunk,
                              maxChunks: Int = defaultMaxChunks) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, wordsPerChunk > 0, maxChunks > 0 else {
            return trimmed.isEmpty ? [] : [trimmed]
        }

        // Kelime aralıklarını NLTokenizer ile bul (Türkçe/Latin sözcük sınırlarına duyarlı;
        // boşluk ve noktalamayı sözcük saymaz).
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed
        var wordRanges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            wordRanges.append(range)
            return true
        }

        // Sınırı aşmayan (ya da hiç kelime içermeyen) metin tek parçadır.
        guard wordRanges.count > wordsPerChunk else { return [trimmed] }

        var result: [String] = []
        var index = 0
        while index < wordRanges.count, result.count < maxChunks {
            let upper = Swift.min(index + wordsPerChunk, wordRanges.count)
            // Parça = ilk kelimenin başından son kelimenin sonuna; aradaki boşluk/noktalama
            // korunur, kelimeler asla ortadan bölünmez.
            let lo = wordRanges[index].lowerBound
            let hi = wordRanges[upper - 1].upperBound
            result.append(String(trimmed[lo..<hi]))
            index = upper
        }
        return result
    }
}
