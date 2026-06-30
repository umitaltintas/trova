import Foundation

// Proaktif asistan (triyaj) için kutu sınıflandırma yardımcıları.
// Temel sinyal kutudur: "gönderilmiş" tipi bir kutudaki mail kullanıcıya aittir
// (yani kullanıcı yazmıştır); aksi halde gelen (alınan) bir maildir.

/// Bir kutu yolunun "gönderilmiş" (kullanıcının yazdığı) bir kutu olup olmadığını söyler.
/// Yol, büyük/küçük harf duyarsız olarak şu parçalardan birini içeriyorsa doğrudur.
public func isSentMailbox(_ name: String) -> Bool {
    let lower = name.lowercased()
    return ["sent", "gönderil", "giden", "outbox"].contains { lower.contains($0) }
}

/// Kutu "gelen kutusu" gibi mi — yani yanıt verilebilir / işlem gerektiren bir kutu mu?
/// Gönderilmiş DEĞİL ve çöp/spam/arşiv/taslak gibi pasif kutulardan biri DEĞİL.
public func isActionableMailbox(_ name: String) -> Bool {
    if isSentMailbox(name) { return false }
    let lower = name.lowercased()
    let excluded = ["trash", "çöp", "junk", "spam", "deleted", "archive", "arşiv", "draft", "taslak"]
    return !excluded.contains { lower.contains($0) }
}

/// Bir digest öğesinin (mailin) görmezden gelme anahtarı: thread'i varsa `threadKey`,
/// yoksa mailin kendi id'si (latestPerThread'in `COALESCE(threadKey, id)` gruplamasıyla aynı).
/// Hem gizleme yazarken hem süzerken tek kaynak burasıdır.
public func digestDismissKey(_ hit: SearchHit) -> String {
    hit.threadKey ?? hit.id
}

/// Görmezden gelinen (dismissed) digest öğelerini süzer (saf — yan etkisiz). Bir öğe:
/// - dismissed haritasında YOKSA → görünür;
/// - VARSA ve öğenin tarihi `dismissedAt`'a eşit veya ondan ESKİYSE → gizli;
/// - VARSA ama öğenin tarihi `dismissedAt`'tan SONRAYSA (konuya yeni yanıt gelmiş) → tekrar görünür.
/// Tarihsiz bir öğe dismissed'deyse karşılaştırılamadığından gizli kalır. Sıra korunur.
public func filterDismissed(_ hits: [SearchHit], dismissed: [String: Date]) -> [SearchHit] {
    guard !dismissed.isEmpty else { return hits }
    return hits.filter { hit in
        guard let dismissedAt = dismissed[digestDismissKey(hit)] else { return true }
        guard let date = hit.date else { return false }
        return date > dismissedAt   // yalnız gizleme anından SONRAki (yeni yanıt) görünür
    }
}

/// Yanıt bekleyen / yanıt gerektiren bir thread'i temsil eden öğe: en son mail + yaşı (gün).
public struct TriageItem: Sendable, Identifiable {
    public var id: String { hit.id }
    public let hit: SearchHit
    public let ageDays: Int

    public init(hit: SearchHit, ageDays: Int) {
        self.hit = hit
        self.ageDays = ageDays
    }

    /// Bir mailden, tarihini `now`'a göre tam güne çevirerek öğe oluşturur.
    public init(hit: SearchHit, now: Date = Date()) {
        self.init(hit: hit, ageDays: TriageItem.ageDays(of: hit.date, now: now))
    }

    /// Bir tarihin `now`'a göre yaşını tam gün olarak verir; tarih yoksa veya gelecekteyse 0.
    public static func ageDays(of date: Date?, now: Date = Date()) -> Int {
        guard let date else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0)
    }
}
