import Foundation

/// Sayısal rozetler için saf etiket yardımcısı (UI'dan bağımsız, test edilebilir).
/// Kenar çubuğu ve diğer rozetler aynı eşik/biçim kurallarını buradan paylaşır.
public enum BadgeCount {
    /// Bir sayıyı rozet etiketine çevirir:
    /// - count <= 0 → nil (rozet hiç gösterilmez);
    /// - 1...99 → sayının kendisi ("1" … "99");
    /// - > 99 → "99+" (rozet dar kalsın diye üst sınır).
    public static func label(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }
}
