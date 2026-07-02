import Foundation

/// Otomatik günlük brifing için saf (yan etkisiz, IO'suz) zamanlama kararları.
///
/// Her gün belirlenen bir saat:dakika hedefine göre "sonraki tetik ne zaman?" ve "şimdi
/// tetiklenmeli mi?" sorularına yanıt verir. `Calendar` enjekte edilir → testlerde sabit bir
/// zaman dilimiyle (UTC) deterministik çalışır; üretimde `.current` (kullanıcının yerel saati)
/// geçirilir. Böylece hedef saat kullanıcının gördüğü yerel saatle örtüşür.
public enum DailyTrigger {
    /// `now`'dan SONRAKİ ilk hedef anı (verilen `hour`:`minute`).
    ///
    /// Bugünkü hedef henüz gelmemişse bugünün hedefi; hedef geçmişse (veya tam o andaysa)
    /// yarının hedefi döner. "Sonraki" kesin olarak `now`'dan büyük bir andır: `now` tam hedefe
    /// eşitse bu anın kendisi değil, ertesi günün hedefi döner (o an artık "geçmiş" sayılır).
    public static func nextFire(after now: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        let today = target(on: now, hour: hour, minute: minute, calendar: calendar)
        if today > now { return today }
        // Bugünün hedefi geçti (veya tam o an) → yarının hedefi. Calendar ay/yıl sınırını da sarar.
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }

    /// Şimdi hedefi (telafi) ateşlemeli mi?
    ///
    /// Koşullar: `now`, hedef saatin AYNI GÜNÜNDE hedefi geçmiş (veya tam o an) olmalı VE o gün
    /// daha önce ateşlenmemiş olmalı. Uygulama hedef anda kapalıysa, aynı gün içinde sonradan
    /// açılınca telafi ateşler; ertesi güne sarkarsa o günün kendi hedefi devreye girer (dünün
    /// ateşlenmemiş hedefi telafi EDİLMEZ — her gün yalnız kendi hedefini kovalar).
    ///
    /// - lastFiredDay: En son ateşlenmenin gerçekleştiği gün (herhangi bir anı; yalnız gün
    ///   bileşeni önemsenir). Hiç ateşlenmediyse nil.
    public static func shouldFire(now: Date, hour: Int, minute: Int,
                                  lastFiredDay: Date?, calendar: Calendar) -> Bool {
        let today = target(on: now, hour: hour, minute: minute, calendar: calendar)
        // Bugünün hedefi henüz gelmedi → ateşleme.
        guard now >= today else { return false }
        // Bugün zaten ateşlendiyse tekrarlama.
        if let lastFiredDay, calendar.isDate(lastFiredDay, inSameDayAs: now) { return false }
        return true
    }

    /// `date`'in bulunduğu günde `hour`:`minute`:00 anını üretir (saniye sıfırlanır).
    private static func target(on date: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps) ?? date
    }
}
