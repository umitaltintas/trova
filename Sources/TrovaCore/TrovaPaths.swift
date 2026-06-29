import Foundation

/// Uygulama dosya yolları. CLI (`trova`) ve uygulama (Trova.app) tek indeksi paylaşır.
public enum TrovaPaths {
    /// Varsayılan veritabanı: `~/Library/Application Support/Trova/index.sqlite`.
    ///
    /// Geriye dönük göç: önceki sürümler indeksi `EmailIndexer/` klasöründe tutuyordu.
    /// Yeni `Trova/` klasörü henüz yoksa ve eski klasör varsa, mevcut indeks (DB +
    /// yan dosyalar) tek seferlik olarak taşınır — kullanıcı yeniden indekslemek
    /// zorunda kalmaz.
    public static func defaultDatabaseURL() -> URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let newDir = support.appendingPathComponent("Trova", isDirectory: true)
        let oldDir = support.appendingPathComponent("EmailIndexer", isDirectory: true)

        if !fm.fileExists(atPath: newDir.path), fm.fileExists(atPath: oldDir.path) {
            try? fm.moveItem(at: oldDir, to: newDir)
        }
        return newDir.appendingPathComponent("index.sqlite")
    }
}
