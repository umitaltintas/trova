import Foundation

/// Klavye kısayolları kılavuzundaki (cheat sheet) tek bir satır.
/// `keys` insan-okur kombinasyon (örn. "⌘1", "⌘K", "⌥↑"), `label` Türkçe açıklama,
/// `group` ait olduğu başlık (örn. "Bölümler").
public struct ShortcutItem: Equatable, Sendable {
    public let keys: String
    public let label: String
    public let group: String

    public init(keys: String, label: String, group: String) {
        self.keys = keys
        self.label = label
        self.group = group
    }
}

/// Uygulamadaki GERÇEK klavye bağlamalarının tek kaynağı (⌘/ kılavuzu bunu çizer).
/// İçerik koddaki gerçek kısayollarla bire bir eşleşir:
/// - Bölümler ⌘1–6 ve ⌘K palet → `ContentView.KeyboardShortcuts`
/// - Gezinme ⌥↑/⌥↓ → `AppModel.selectAdjacent`
/// - ⌘, Ayarlar → `TrovaApp` Settings sahnesi (macOS standart bağlaması)
/// - ⌘/ bu kılavuz, Komut paleti içi ↑↓/Enter/Esc → `CommandPalette` onKeyPress
public enum ShortcutCatalog {
    public static let all: [ShortcutItem] = [
        // Bölümler — ⌘1–6 ile sol kenardaki bölümler arasında geçiş.
        .init(keys: "⌘1", label: "Sor", group: "Bölümler"),
        .init(keys: "⌘2", label: "Ara", group: "Bölümler"),
        .init(keys: "⌘3", label: "Bugün", group: "Bölümler"),
        .init(keys: "⌘4", label: "Kişiler", group: "Bölümler"),
        .init(keys: "⌘5", label: "Genel Bakış", group: "Bölümler"),
        .init(keys: "⌘6", label: "Ekler", group: "Bölümler"),

        // Genel — uygulama geneli komutlar.
        .init(keys: "⌘K", label: "Komut paleti", group: "Genel"),
        .init(keys: "⌘/", label: "Klavye kısayolları", group: "Genel"),
        .init(keys: "⌘,", label: "Ayarlar", group: "Genel"),

        // Gezinme — aktif listede mailler arasında geçiş.
        .init(keys: "⌥↑", label: "Önceki mail", group: "Gezinme"),
        .init(keys: "⌥↓", label: "Sonraki mail", group: "Gezinme"),

        // Komut paleti — ⌘K paleti açıkken geçerli tuşlar.
        .init(keys: "↑ ↓", label: "Komutlar arasında gezin", group: "Komut paleti"),
        .init(keys: "Enter", label: "Seçili komutu çalıştır", group: "Komut paleti"),
        .init(keys: "Esc", label: "Paleti kapat", group: "Komut paleti"),
    ]

    /// Grupları ilk görülme sıralarını koruyarak (group → items) eşler.
    /// `all` içindeki grup sırası bozulmadan döner; UI başlıklı bölümleri bununla çizer.
    public static var byGroup: [(group: String, items: [ShortcutItem])] {
        var order: [String] = []
        var map: [String: [ShortcutItem]] = [:]
        for item in all {
            if map[item.group] == nil { order.append(item.group) }
            map[item.group, default: []].append(item)
        }
        return order.map { (group: $0, items: map[$0] ?? []) }
    }
}
