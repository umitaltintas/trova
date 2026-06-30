import Foundation

/// Apple Mail `.emlx` plist trailer'ındaki `flags` tamsayısından (bitfield) çözülen
/// okunmuş/bayraklı/yanıtlanmış durumları.
///
/// Doğrulanmış EMLX flag bitleri:
/// - bit 0 (0x1)   = okundu (read)
/// - bit 2 (0x4)   = yanıtlandı (answered)
/// - bit 4 (0x10)  = bayraklı (flagged)
/// - bit 8 (0x100) = iletildi (forwarded) — şimdilik kullanılmıyor
public struct EmailFlags: Equatable, Sendable {
    /// Okundu mu (bit 0).
    public let isRead: Bool
    /// Bayraklı mı (bit 4).
    public let isFlagged: Bool
    /// Yanıtlandı mı (bit 2).
    public let isAnswered: Bool

    /// Ham `flags` bitfield'ından ilgili bitleri ayıklar.
    public init(rawValue: Int) {
        isRead = rawValue & 0x1 != 0       // bit 0
        isAnswered = rawValue & 0x4 != 0   // bit 2
        isFlagged = rawValue & 0x10 != 0   // bit 4
    }
}
