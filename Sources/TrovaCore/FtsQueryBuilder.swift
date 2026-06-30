import Foundation

/// Kullanıcının serbest-metin arama sorgusunu GEÇERLİ bir FTS5 MATCH ifadesine çevirir.
///
/// Desteklenen gelişmiş sözdizimi:
/// - `"tam ifade"` → FTS5 ifade (phrase) sorgusu; tokenlar art arda eşleşmeli, **önek `*` YOK**.
/// - `-terim`      → DIŞLAMA; FTS5 `NOT` ile (örn. pozitif `"a"*`, dışlama `NOT "c"*`).
/// - çıplak terim  → `"terim"*`; sondaki `*` ile Türkçe önek araması KORUNUR
///   ("fatura" → "faturanız"/"faturası").
/// - Çok pozitif terim → mevcut davranışla tutarlı, boşlukla (FTS5 örtük AND) birleşir.
///
/// Güvenlik: Üretilen ifade DAİMA geçerli FTS5 olmalı (sözdizim hatası aramayı çökertir).
/// Bu yüzden her terim çift tırnakla sarılır (FTS5'in `* " ( ) : ^ -` gibi özel karakterleri
/// alıntı içinde yalnızca tokenizer ayıracı sayılır, sözdizimi DEĞİL). Gelişmiş sözdizimi
/// yoksa veya üretilen ifade riskli/uç durumsa mevcut `IndexStore.ftsPattern`'e geri düşülür →
/// tek-terim/normal arama çıktısı ESKİYLE BİREBİR aynı kalır (regresyon yok).
public enum FtsQueryBuilder {
    /// Serbest-metin sorgudan geçerli bir FTS5 MATCH ifadesi üretir. Boş sorguda boş string
    /// döner (çağıran taraf boş deseni "sonuç yok" olarak ele alır, mevcut davranışla aynı).
    public static func build(_ query: String) -> String {
        // Gelişmiş sözdizimi (tırnak veya `-belirteç`) yoksa: mevcut davranış AYNEN korunur.
        // Tek-terim ve çok-terim normal aramalar bu yoldan geçer → sıfır regresyon.
        guard hasAdvancedSyntax(query) else {
            return IndexStore.ftsPattern(query)
        }

        let parsed = parse(query)

        // Pozitif terim yoksa (yalnız-dışlama / yalnız boş tırnak gibi uç durum): FTS5'te tek
        // başına `NOT ...` GEÇERSİZ → güvenli geri-düşüş. Tire/tırnak temizlenip mevcut
        // ftsPattern uygulanır; böylece çökme olmaz, makul bir eşleşme döner (boşsa "" → sonuç yok).
        guard !parsed.positives.isEmpty else {
            return IndexStore.ftsPattern(sanitizedForFallback(query))
        }

        // Pozitifler örtük AND ile (boşluk), dışlamalar `NOT` ile eklenir: `"a"* "b" NOT "c"*`.
        var expr = parsed.positives.joined(separator: " ")
        for excluded in parsed.exclusions {
            expr += " NOT \(excluded)"
        }
        return expr
    }

    // MARK: - Yardımcılar

    private static func isSpace(_ c: Character) -> Bool { c == " " || c == "\t" || c == "\n" }

    /// İçinde en az bir harf/rakam var mı? Yoksa unicode61 tokenizer'ı sıfır token üretir →
    /// FTS5'te BOŞ ifade (sözdizim hatası) doğar. Böyle parçalar gelişmiş yolda atlanır.
    private static func hasWordChar(_ s: String) -> Bool {
        s.contains { $0.isLetter || $0.isNumber }
    }

    /// Sorguda gelişmiş sözdizimi var mı? (çift tırnak veya tire ile başlayan herhangi bir belirteç)
    /// Yoksa mevcut ftsPattern'e doğrudan düşeriz. Sözcük İÇİ tire (e-posta, ön-ek) DIŞLAMA sayılmaz;
    /// yalnızca belirtecin BAŞINDAKİ tire dışlamadır.
    private static func hasAdvancedSyntax(_ query: String) -> Bool {
        if query.contains("\"") { return true }
        return query.split(whereSeparator: isSpace).contains { $0.first == "-" }
    }

    private struct Parsed {
        var positives: [String] = []
        var exclusions: [String] = []
    }

    /// Sorguyu tarayarak pozitif/dışlama FTS5 parçalarına ayırır. Tırnaklı bölümler ifade (phrase),
    /// çıplak belirteçler önekli (`*`) terim olur. Boş/geçersiz parçalar atlanır (ifade her zaman geçerli).
    private static func parse(_ query: String) -> Parsed {
        var result = Parsed()
        let chars = Array(query)
        let n = chars.count
        var i = 0

        while i < n {
            // Önceki boşlukları atla.
            while i < n && isSpace(chars[i]) { i += 1 }
            if i >= n { break }

            // Baştaki tire → dışlama. Tireden hemen sonra boşluk/son gelirse tireyi yok say.
            var negate = false
            if chars[i] == "-" {
                negate = true
                i += 1
                if i >= n || isSpace(chars[i]) { continue }
            }

            if chars[i] == "\"" {
                // Tırnaklı ifade: kapanış tırnağına (veya sorgu sonuna) kadar oku. İçeride tırnak
                // olamaz (ilk tırnakta dururuz) → ayrıca kaçışa gerek yok.
                i += 1
                var content = ""
                while i < n && chars[i] != "\"" {
                    content.append(chars[i]); i += 1
                }
                if i < n { i += 1 }  // kapanış tırnağını tüket
                let cleaned = content.trimmingCharacters(in: .whitespaces)
                if !hasWordChar(cleaned) { continue }   // boş/yalnız-noktalama ifade → atla (FTS5'te sorunlu)
                let phrase = "\"\(cleaned)\""        // ifade (phrase) — ÖNEK YOK
                if negate { result.exclusions.append(phrase) } else { result.positives.append(phrase) }
            } else {
                // Çıplak belirteç: bir sonraki boşluğa veya tırnağa kadar oku.
                var token = ""
                while i < n && !isSpace(chars[i]) && chars[i] != "\"" {
                    token.append(chars[i]); i += 1
                }
                // Güvenlik için olası tırnakları temizle (normalde belirteçte tırnak olmaz).
                let safe = token.replacingOccurrences(of: "\"", with: "")
                if !hasWordChar(safe) { continue }   // yalnız-noktalama belirteç → atla (boş ifade olmasın)
                let term = "\"\(safe)\"*"            // önekli terim — Türkçe davranış korunur
                if negate { result.exclusions.append(term) } else { result.positives.append(term) }
            }
        }
        return result
    }

    /// Geri-düşüş için sorguyu sadeleştirir: tırnakları boşluğa çevirir, belirteç başındaki tireleri
    /// atar. Sonuç mevcut `ftsPattern`'e verilir → her zaman geçerli, güvenli bir desen üretir.
    private static func sanitizedForFallback(_ query: String) -> String {
        query
            .replacingOccurrences(of: "\"", with: " ")
            .split(whereSeparator: isSpace)
            .map { token -> Substring in
                var t = token
                while t.first == "-" { t = t.dropFirst() }
                return t
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
