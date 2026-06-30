import Foundation

/// Ek dosya adlarını arama terimleriyle eşleştiren saf yardımcı (byte çözmeden, yalnız ad üzerinden).
/// Sonuç satırında "hangi ek eşleşti" rozetini hesaplamak için kullanılır.
public enum AttachmentMatch {

    /// `names` içinde, `terms`'ten en az biri alt dizge olarak GEÇEN ek adlarını (giriş sırasıyla) döndürür.
    /// - Karşılaştırma Türkçe yerele duyarlı küçük harfe (İ→i) indirgenerek yapılır; büyük/küçük harf duyarsız.
    /// - Boş `terms` veya boş `names` → []. Boş terimler yok sayılır.
    /// - Yinelenenler ayıklanmaz (çağıran adların tekil olduğunu varsayar).
    public static func matching(names: [String], terms: [String]) -> [String] {
        guard !names.isEmpty, !terms.isEmpty else { return [] }
        let locale = Locale(identifier: "tr_TR")
        let needles = terms
            .map { $0.lowercased(with: locale) }
            .filter { !$0.isEmpty }
        guard !needles.isEmpty else { return [] }
        return names.filter { name in
            let haystack = name.lowercased(with: locale)
            return needles.contains { haystack.contains($0) }
        }
    }
}
