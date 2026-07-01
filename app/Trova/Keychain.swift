import Foundation
import Security

/// API anahtarlarını macOS Keychain'de saklar (UserDefaults yerine — güvenli).
enum Keychain {
    private static let service = "com.emailindexer.Trova"

    static func set(_ value: String, for account: String) {
        delete(account)
        guard !value.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Senkron Keychain okuması. DİKKAT: ANA THREAD'DEN ÇAĞIRMAYIN. Ad-hoc imza her
    /// değiştiğinde (her yeniden derlemede) macOS, Keychain erişimi için onay diyaloğu
    /// gösterir; diyalog yanıtlanana dek `SecItemCopyMatching` ana thread'i SÜRESİZ kilitler
    /// ("0 pencere" açılış donması). Açılış yolundaki okumalar için `readAsync(_:)` kullanın.
    static func get(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    /// Anahtarı ANA THREAD DIŞINDA (arka plan görevinde) okur. Senkron `get(_:)` yeniden
    /// imzalama sonrası onay diyaloğu beklerken ana thread'i kilitlediğinden, açılış
    /// yolundaki (görünüm init'leri, durum tazeleme) tüm okumalar bunun üzerinden yapılmalı;
    /// böylece diyalog beklerken bile pencere/UI çizilmeye devam eder.
    static func readAsync(_ account: String) async -> String {
        await Task.detached(priority: .userInitiated) { get(account) }.value
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainKeys {
    static let embedKey = "embedKey"
    static let llmKey = "llmKey"
}
