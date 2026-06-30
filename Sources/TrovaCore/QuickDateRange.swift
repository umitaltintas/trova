import Foundation

/// Aramada tek tıkla (yazmadan) uygulanan hızlı tarih aralıkları: Bugün / Son 7 gün / Son 30 gün / Bu yıl.
public enum QuickDateRange: String, CaseIterable, Sendable {
    case today, last7, last30, thisYear

    /// Çip etiketi (Türkçe).
    public var label: String {
        switch self {
        case .today:    "Bugün"
        case .last7:    "Son 7 gün"
        case .last30:   "Son 30 gün"
        case .thisYear: "Bu yıl"
        }
    }

    /// Çip ikonu (SF Symbol).
    public var systemImage: String {
        switch self {
        case .today:    "sun.max"
        case .last7:    "calendar"
        case .last30:   "calendar"
        case .thisYear: "calendar.badge.clock"
        }
    }
}

/// Hızlı tarih aralığını (since/until) hesaplar — saf, yan etkisiz; `now`/`calendar` enjekte edilir.
/// TurkishDateParser ile TUTARLI: tüm alt sınırlar `calendar` gün/yıl başlangıçlarına hizalanır ve
/// üst sınır (until) açık bırakılır (nil → "şimdiye kadar"), tıpkı yazılı "bugün"/"son N gün"/"bu yıl" gibi.
public enum QuickDate {
    public static func range(_ kind: QuickDateRange, now: Date,
                             calendar: Calendar = .current) -> (since: Date, until: Date?) {
        let startToday = calendar.startOfDay(for: now)
        switch kind {
        case .today:
            return (startToday, nil)
        case .last7:
            return (calendar.date(byAdding: .day, value: -7, to: startToday) ?? startToday, nil)
        case .last30:
            return (calendar.date(byAdding: .day, value: -30, to: startToday) ?? startToday, nil)
        case .thisYear:
            return (calendar.dateInterval(of: .year, for: now)?.start ?? startToday, nil)
        }
    }
}
