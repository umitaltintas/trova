import Foundation

/// Arama sorgusunda algılanan Türkçe tarih ifadesinden çıkan tarih aralığı + insan-okur etiketi.
public struct DateHint: Equatable, Sendable {
    public let since: Date?
    public let until: Date?
    public let label: String
    public init(since: Date?, until: Date?, label: String) {
        self.since = since; self.until = until; self.label = label
    }
}

/// Türkçe doğal dil tarih ifadelerini ("son 7 gün", "dün", "geçen ay", "bu hafta") ayrıştırır.
/// Saf — yan etkisiz; `now`/`calendar` enjekte edilebildiği için deterministik test edilir.
/// İlk algılanan ifade kazanır; kalan kelimeler arama sorgusu olarak döner.
public enum TurkishDateParser {
    private static let units: Set<String> = ["gün", "hafta", "ay", "yıl", "sene"]
    private static let periodWords: Set<String> = ["hafta", "ay", "yıl", "sene"]

    public static func parse(_ query: String, now: Date,
                             calendar: Calendar = .current) -> (hint: DateHint?, cleaned: String) {
        let tokens = query.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        func low(_ s: String) -> String { s.lowercased(with: Locale(identifier: "tr_TR")) }

        var kept: [String] = []
        var hint: DateHint?
        var i = 0
        while i < tokens.count {
            // Bir tarih ipucu bulunduysa ikinciyi arama; kalan token'lar sorgudur.
            if hint == nil {
                let t = low(tokens[i])
                if t == "bugün" {
                    hint = todayHint(now: now, calendar: calendar); i += 1; continue
                }
                if t == "dün" {
                    hint = yesterdayHint(now: now, calendar: calendar); i += 1; continue
                }
                if t == "son", i + 2 < tokens.count, let n = Int(tokens[i + 1]), n > 0,
                   units.contains(low(tokens[i + 2])) {
                    hint = lastNHint(n, unit: low(tokens[i + 2]), now: now); i += 3; continue
                }
                if t == "bu" || t == "geçen" || t == "geçtiğimiz" || t == "gecen" || t == "gectigimiz" {
                    if i + 1 < tokens.count, periodWords.contains(low(tokens[i + 1])) {
                        hint = periodHint(determiner: t, unit: low(tokens[i + 1]),
                                          now: now, calendar: calendar)
                        i += 2; continue
                    }
                }
            }
            kept.append(tokens[i]); i += 1
        }
        return (hint, kept.joined(separator: " "))
    }

    // MARK: - Aralık hesapları

    private static func todayHint(now: Date, calendar: Calendar) -> DateHint {
        DateHint(since: calendar.startOfDay(for: now), until: nil, label: "bugün")
    }

    private static func yesterdayHint(now: Date, calendar: Calendar) -> DateHint {
        let startToday = calendar.startOfDay(for: now)
        let startYest = calendar.date(byAdding: .day, value: -1, to: startToday)
            ?? startToday.addingTimeInterval(-86_400)
        return DateHint(since: startYest, until: startToday, label: "dün")
    }

    private static func lastNHint(_ n: Int, unit: String, now: Date) -> DateHint {
        let day = 86_400.0
        let seconds: Double
        let unitLabel: String
        switch unit {
        case "hafta": seconds = Double(n) * 7 * day; unitLabel = "hafta"
        case "ay": seconds = Double(n) * 30 * day; unitLabel = "ay"
        case "yıl", "sene": seconds = Double(n) * 365 * day; unitLabel = "yıl"
        default: seconds = Double(n) * day; unitLabel = "gün"
        }
        return DateHint(since: now.addingTimeInterval(-seconds), until: nil, label: "son \(n) \(unitLabel)")
    }

    private static func periodHint(determiner: String, unit: String,
                                   now: Date, calendar: Calendar) -> DateHint {
        let comp: Calendar.Component
        let unitLabel: String
        switch unit {
        case "hafta": comp = .weekOfYear; unitLabel = "hafta"
        case "ay": comp = .month; unitLabel = "ay"
        default: comp = .year; unitLabel = "yıl"
        }
        let start = calendar.dateInterval(of: comp, for: now)?.start ?? now
        if determiner == "bu" {
            return DateHint(since: start, until: nil, label: "bu \(unitLabel)")
        }
        let prevStart = calendar.date(byAdding: comp, value: -1, to: start) ?? start
        return DateHint(since: prevStart, until: start, label: "geçen \(unitLabel)")
    }
}
