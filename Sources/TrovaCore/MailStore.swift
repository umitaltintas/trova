import Foundation

/// Diskte bulunan tek bir mail dosyası ve yolundan çıkarılan hesap/kutu bilgisi.
public struct DiscoveredMessage: Sendable {
    public let fileURL: URL
    public let accountID: String
    public let mailbox: String
}

/// Apple Mail'in yerel deposunu (`~/Library/Mail/V<n>/`) bulup gezer.
///
/// Apple Mail tüm hesapları (IMAP/Exchange/iCloud/Gmail) bu konuma indirip
/// senkronize ettiği için hiçbir hesaba yeniden bağlanmaya gerek kalmaz —
/// sadece `.emlx` dosyalarını okuruz. Tek gereksinim: Full Disk Access.
public enum MailStore {
    static var mailRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail", isDirectory: true)
    }

    /// `~/Library/Mail/` altındaki en güncel `V<n>` deposunu döndürür.
    public static func locate() -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: mailRoot, includingPropertiesForKeys: nil) else { return nil }
        let versions = entries.compactMap { url -> (URL, Int)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("V"), let n = Int(name.dropFirst()) else { return nil }
            return (url, n)
        }
        return versions.max(by: { $0.1 < $1.1 })?.0
    }

    /// Full Disk Access verilmiş mi? (`~/Library/Mail` listelenebiliyor mu?)
    public static func canAccess() -> Bool {
        (try? FileManager.default.contentsOfDirectory(
            at: mailRoot, includingPropertiesForKeys: nil)) != nil
    }

    /// Depodaki tüm `.emlx` dosyalarını bulur; hesap (UUID) ve kutu adını yoldan çıkarır.
    ///
    /// Yol deseni: `…/V<n>/<accountUUID>/<Kutu>.mbox/…/Messages/xxxxx.emlx`
    /// İç içe kutular için `.mbox` bileşenleri "/" ile birleştirilir.
    public static func discoverMessages(root: URL, limit: Int? = nil) -> [DiscoveredMessage] {
        let rootDepth = root.pathComponents.count
        var results: [DiscoveredMessage] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasSuffix(".emlx") else { continue }

            let comps = Array(url.pathComponents.dropFirst(rootDepth))
            guard let accountID = comps.first else { continue }
            let mailbox = comps
                .filter { $0.hasSuffix(".mbox") }
                .map { String($0.dropLast(".mbox".count)) }
                .joined(separator: "/")

            results.append(DiscoveredMessage(
                fileURL: url,
                accountID: accountID,
                mailbox: mailbox.isEmpty ? "(kök)" : mailbox))

            if let limit, results.count >= limit { break }
        }
        return results
    }
}
