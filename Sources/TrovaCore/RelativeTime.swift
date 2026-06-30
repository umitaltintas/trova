import Foundation

/// Uygulama genelinde tek tip Türkçe göreli zaman gösterimi.
/// Saf — yan etkisiz; `now`/`calendar` enjekte edilebildiği için deterministik test edilir.
/// Locale'den bağımsızdır: ay adları sabit dizilerden gelir (TR diakritikleriyle).
public enum RelativeTime {

    // Türkçe kısa aylar (rozet/çip ve "5 Mar" biçimleri için).
    private static let shortMonths = ["Oca", "Şub", "Mar", "Nis", "May", "Haz",
                                      "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
    // Türkçe tam aylar (mutlak tooltip için).
    private static let fullMonths = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                                     "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]

    /// İnsan-okur göreli zaman: "az önce", "5 dk önce", "3 saat önce", "dün",
    /// "4 gün önce", "geçen hafta", "2 hafta önce", "geçen ay", "5 ay önce",
    /// aynı yıl daha eski → "5 Mar", farklı yıl → "5 Mar 2024".
    public static func format(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        // Gelecekteki tarihler için makul davran (saat dilimi/saat kayması).
        if seconds < 60 { return "az önce" }                 // < 60 saniye
        if seconds < 3_600 { return "\(Int(seconds / 60)) dk önce" } // < 60 dakika

        // Gün sınırları takvime göre: "saat" yalnızca aynı takvim günü içinde geçerli.
        let d = dayDiff(date, now, calendar)
        if d == 0 { return "\(Int(seconds / 3_600)) saat önce" } // aynı gün, < 24 saat
        if d == 1 { return "dün" }                           // önceki takvim günü
        if d < 7 { return "\(d) gün önce" }                  // 2–6 gün
        if d < 14 { return "geçen hafta" }                   // 7–13 gün
        if d < 35 { return "\(d / 7) hafta önce" }           // ~2–4 hafta (< ~5 hafta)

        let mo = monthDiff(date, now, calendar)
        if mo <= 1 { return "geçen ay" }                     // ~1 ay
        if mo <= 6 { return "\(mo) ay önce" }                // 2–6 ay
        return shortAbsolute(date, now: now, calendar: calendar) // daha eski → "5 Mar" / "5 Mar 2024"
    }

    /// Dar alanlar (rozet/çip) için kısa biçim: "şimdi", "5dk", "2sa", "dün",
    /// "3g", "2h" (hafta), aynı yıl daha eski → "Mar", farklı yıl → "Mar 24".
    public static func short(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "şimdi" }                   // < 60 saniye
        if seconds < 3_600 { return "\(Int(seconds / 60))dk" } // < 60 dakika

        let d = dayDiff(date, now, calendar)
        if d == 0 { return "\(Int(seconds / 3_600))sa" }     // aynı gün, < 24 saat
        if d == 1 { return "dün" }                           // önceki takvim günü
        if d < 7 { return "\(d)g" }                          // 2–6 gün
        if d < 35 { return "\(d / 7)h" }                     // hafta (1h, 2h, …)

        // Daha eski: kısa ay; farklı yılda 2 haneli yıl eklenir.
        let month = shortMonths[monthIndex(date, calendar)]
        if sameYear(date, now, calendar) { return month }
        let yy = calendar.component(.year, from: date) % 100
        return month + " " + String(format: "%02d", yy)
    }

    /// Tooltip için tam mutlak zaman: "5 Mart 2024 14:30".
    public static func absolute(_ date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.component(.day, from: date)
        let month = fullMonths[monthIndex(date, calendar)]
        let year = calendar.component(.year, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return "\(day) \(month) \(year) " + String(format: "%02d:%02d", hour, minute)
    }

    // MARK: - Yardımcılar

    /// Kısa mutlak tarih: aynı yıl "5 Mar", farklı yıl "5 Mar 2024".
    private static func shortAbsolute(_ date: Date, now: Date, calendar: Calendar) -> String {
        let day = calendar.component(.day, from: date)
        let month = shortMonths[monthIndex(date, calendar)]
        if sameYear(date, now, calendar) { return "\(day) \(month)" }
        return "\(day) \(month) \(calendar.component(.year, from: date))"
    }

    /// Takvim günü farkı (gün sınırlarına göre; saat farkı değil).
    private static func dayDiff(_ date: Date, _ now: Date, _ calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Takvim ayı farkı (yıl*12 + ay indeksine göre).
    private static func monthDiff(_ date: Date, _ now: Date, _ calendar: Calendar) -> Int {
        let a = calendar.dateComponents([.year, .month], from: date)
        let b = calendar.dateComponents([.year, .month], from: now)
        return (b.year! - a.year!) * 12 + (b.month! - a.month!)
    }

    private static func sameYear(_ date: Date, _ now: Date, _ calendar: Calendar) -> Bool {
        calendar.component(.year, from: date) == calendar.component(.year, from: now)
    }

    /// 0 tabanlı ay indeksi (ay dizilerine erişmek için).
    private static func monthIndex(_ date: Date, _ calendar: Calendar) -> Int {
        calendar.component(.month, from: date) - 1
    }
}
