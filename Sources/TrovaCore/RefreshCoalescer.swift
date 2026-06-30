import Foundation

/// Hızlı ardışık dosya-sistemi olaylarını tek bir tazeleme tetiğine indirgeyen saf karar yapısı.
///
/// FSEvents canlı tazelemede, bir mail klasörüne yapılan tek bir yazma birden çok ham olay üretebilir.
/// Bu yapı, olayların zaman damgalarını alıp "şimdi tetiklenmeli mi?" sorusuna yan etkisiz yanıt verir:
/// son olaydan bu yana `window` kadar sessizlik geçtiyse VE bu olay grubu için henüz tetiklenmediyse
/// tetikler. `now` enjekte edilir → testlerde sabit zamanla deterministik.
public struct RefreshCoalescer: Sendable {
    /// Sessizlik penceresi: son olaydan sonra bu süre kadar yeni olay gelmezse tetiklenir.
    public let window: TimeInterval

    public init(window: TimeInterval = 2) {
        self.window = window
    }

    /// Verilen olay zaman damgaları, şu anki zaman ve son tetik anına göre tetiklenmeli mi?
    ///
    /// - events: O ana dek gözlenen (henüz tetiklenmemiş) olayların zaman damgaları.
    /// - now: Şu anki zaman (enjekte; test edilebilirlik için).
    /// - lastFired: En son tetiklenme anı (hiç tetiklenmediyse nil).
    /// - Returns: Pencere dolduğunda ve grup için henüz tetiklenmediğinde `true`.
    public func shouldFire(events: [Date], now: Date, lastFired: Date?) -> Bool {
        // Hiç olay yoksa tetiklenecek bir şey yok.
        guard let lastEvent = events.max() else { return false }
        // Son olaydan bu yana sessizlik penceresi henüz dolmadıysa bekle (olayları birleştir).
        guard now.timeIntervalSince(lastEvent) >= window else { return false }
        // Bu olay grubu için zaten tetiklendiyse (son tetik, son olaydan sonraysa) tekrar tetikleme.
        if let lastFired, lastFired >= lastEvent { return false }
        return true
    }
}
