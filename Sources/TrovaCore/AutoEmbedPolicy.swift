import Foundation

/// Otomatik gömme (auto-embed) kararını veren saf mantık: bir gömme dalgasında kaç mesajın
/// gömüleceğini hesaplar. UI'dan ve dosya/ağ erişiminden bağımsızdır → birim testlerle doğrulanır.
///
/// Kararı belirleyen girdiler: bir gömme sağlayıcısı kurulabiliyor mu (yerel model varlıkları hazır
/// VEYA bir bulut anahtarı var), "Yeni mailleri otomatik göm" ayarı açık mı, kaç mail hâlâ gömülmemiş
/// (vektörü yok) ve bir dalgada işlenecek üst sınır (CPU/ısı koruması). Sonuç 0 ise bu dalgada gömme
/// yapılmaz; çağıran taraf sessizce durur (hata göstermez).
public enum AutoEmbedPolicy {
    /// Bu dalgada gömülecek mesaj sayısı.
    /// - providerAvailable: Bir gömme sağlayıcısı kurulabiliyor mu.
    /// - enabled: "Yeni mailleri otomatik göm" ayarı açık mı.
    /// - missingCount: Henüz gömülmemiş (vektörü olmayan) mail sayısı.
    /// - batchLimit: Bir dalgada işlenecek üst sınır (0 veya negatifse hiç iş yapılmaz).
    ///
    /// Herhangi bir ön koşul sağlanmazsa 0; aksi halde eksik sayı ile parti sınırının küçüğü döner
    /// (eksik sayı sınırın altındaysa hepsi, üstündeyse yalnız sınır kadar — kalanı sonraki dalgada).
    public static func batchSize(providerAvailable: Bool,
                                 enabled: Bool,
                                 missingCount: Int,
                                 batchLimit: Int) -> Int {
        guard enabled, providerAvailable, missingCount > 0, batchLimit > 0 else { return 0 }
        return Swift.min(missingCount, batchLimit)
    }
}
