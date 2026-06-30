import Foundation

/// Pseudo-relevance feedback (PRF) sorgu genişletme: ilk getirme sonuçlarının metinlerinden,
/// özgün sorguda olmayan en ayırt edici terimleri çıkarır. Bu terimler sorguya eklenince
/// kelime dağarcığı boşlukları kapanır (recall artar). Çoklu-sorgu üretiminin aksine LLM
/// gerektirmez ve uydurma yapmaz — yalnızca zaten getirilmiş belgelerin kelimelerini kullanır.
///
/// Saf — yan etkisiz, deterministik (eşitlikler alfabetik çözülür), test edilebilir.
public enum QueryExpander {
    /// Türkçe + birkaç İngilizce yaygın durdurma kelimesi (genişletmeye katılmaz).
    static let stopwords: Set<String> = [
        "ve", "veya", "ile", "için", "bu", "şu", "bir", "da", "de", "ki", "mı", "mi", "mu", "mü",
        "ama", "fakat", "çok", "daha", "en", "gibi", "kadar", "sonra", "önce", "ya", "ne", "her",
        "hiç", "ben", "sen", "biz", "siz", "onlar", "var", "yok", "olarak", "ise", "ya da", "ancak",
        "hem", "değil", "diye", "göre", "üzere", "şey", "olan", "oldu", "bana", "sana", "the", "and",
        "for", "with", "you", "your", "are", "was", "this", "that", "from", "have", "has",
    ]

    /// - Parameters:
    ///   - query: özgün sorgu (terimleri genişletmeden çıkarılır).
    ///   - docs: ilk getirmedeki belge metinleri (konu + snippet vb.).
    ///   - maxTerms: eklenecek en fazla terim sayısı.
    /// Terimler belge frekansına (kaç belgede geçtiği), eşitlikte toplam frekansa, sonra
    /// alfabetik sıraya göre seçilir.
    public static func expansionTerms(query: String, docs: [String], maxTerms: Int = 4) -> [String] {
        let queryTerms = Set(tokenize(query))
        var docFreq: [String: Int] = [:]
        var totalFreq: [String: Int] = [:]

        for doc in docs {
            let tokens = tokenize(doc)
            var seenInDoc: Set<String> = []
            for token in tokens {
                guard token.count >= 3, !queryTerms.contains(token),
                      !stopwords.contains(token), Int(token) == nil else { continue }
                totalFreq[token, default: 0] += 1
                if seenInDoc.insert(token).inserted { docFreq[token, default: 0] += 1 }
            }
        }

        return docFreq.keys
            .sorted { a, b in
                if docFreq[a] != docFreq[b] { return docFreq[a]! > docFreq[b]! }
                if totalFreq[a] != totalFreq[b] { return totalFreq[a]! > totalFreq[b]! }
                return a < b
            }
            .prefix(maxTerms)
            .map { $0 }
    }

    /// Metni küçük harfli (tr) kelime belirteçlerine ayırır (harf/rakam dışı her şey ayraç).
    static func tokenize(_ text: String) -> [String] {
        text.lowercased(with: Locale(identifier: "tr_TR"))
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
