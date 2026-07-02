import Foundation

/// Bir tarihi, arama sonuçlarını başlıklar altında toplamak için okunabilir bir "yakınlık"
/// kovasına indirgeyen saf, yan etkisiz, deterministik bir modül. IO yoktur; `Calendar` ve
/// `now` dışarıdan enjekte edilir, böylece testler zaman diliminden ve gerçek saatten bağımsız
/// (deterministik) çalışır.
///
/// Kovalar en yakından en uzağa sıralıdır (enum sırası = gösterim sırası). `.tarihsiz` en sona
/// düşer — tarihi olmayan sonuçlar zaten sıralamada da listenin sonundadır.
public enum DateBucket: CaseIterable, Sendable {
    case bugun      // now ile aynı takvim günü
    case dun        // now'un bir önceki günü
    case buHafta    // now ile aynı takvim haftası (firstWeekday'e saygılı), bugün/dün hariç
    case buAy       // now ile aynı takvim ayı (yıl dahil), yukarıdakiler hariç
    case dahaEski   // yukarıdakilerin hiçbirine düşmeyen tarihli sonuçlar
    case tarihsiz   // tarihi olmayan (nil) sonuçlar

    /// Kullanıcıya gösterilecek Türkçe etiket (başlık satırında büyük harfe çevrilerek gösterilir).
    public var label: String {
        switch self {
        case .bugun:    return "Bugün"
        case .dun:      return "Dün"
        case .buHafta:  return "Bu Hafta"
        case .buAy:     return "Bu Ay"
        case .dahaEski: return "Daha Eski"
        case .tarihsiz: return "Tarihsiz"
        }
    }

    /// Bir tarihi `now`'a göre uygun kovaya yerleştirir. Kurallar sırayla denenir; ilk tutan kazanır.
    ///
    /// - `nil` → `.tarihsiz`.
    /// - `now` ile aynı takvim günü → `.bugun` (günün herhangi bir anı; geçmiş/gelecek fark etmez).
    /// - `now`'un bir önceki günü → `.dun` (yalnız geçmiş; gelecekteki bir tarih asla "dün" olamaz).
    /// - `now` ile aynı takvim haftası (firstWeekday'e saygılı; hafta aralığı `dateInterval` ile
    ///   hesaplanır, week-of-year sayısına güvenilmez → yıl sınırında da doğru), bugün/dün değil → `.buHafta`.
    /// - `now` ile aynı takvim ayı (yıl dahil; Aralık 2024 ≠ Ocak 2025), yukarıdakiler değil → `.buAy`.
    /// - Kalan her şey → `.dahaEski`.
    ///
    /// GELECEK TARİH KARARI: Gelecekteki tarihler de (nadir; genelde saat kayması) yukarıdaki
    /// AYNI içerme kurallarından geçer. Yani bugüne düşen gelecek anı `.bugun`, bu haftaya düşen
    /// gelecek gün `.buHafta`, bu aya düşen gelecek gün `.buAy` olur; mevcut aydan öteye taşan
    /// gelecek tarihler ise uzak geçmişle aynı kovaya — `.dahaEski` — iner. Kovalar "yakınlık"
    /// ekseninde olduğundan bu tutarlı ve basit seçimdir; ayrı bir "gelecek" kovası eklemeyiz.
    public static func bucket(for date: Date?, now: Date, calendar: Calendar) -> DateBucket {
        guard let date else { return .tarihsiz }

        if calendar.isDate(date, inSameDayAs: now) { return .bugun }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .dun
        }

        if let week = calendar.dateInterval(of: .weekOfYear, for: now),
           week.contains(date) {
            return .buHafta
        }

        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return .buAy
        }

        return .dahaEski
    }

    /// Öğeleri tarihlerine göre kovalara ayırır. Girdi sırası her kova İÇİNDE korunur; boş kovalar
    /// atlanır; döndürülen dizinin sırası enum sırasıdır (Bugün → … → Tarihsiz).
    ///
    /// Generic ve `date` çıkarıcı sayesinde `SearchHit` dahil her tür üzerinde çalışır.
    public static func grouped<T>(_ items: [T],
                                  date: (T) -> Date?,
                                  now: Date,
                                  calendar: Calendar) -> [(bucket: DateBucket, items: [T])] {
        var byBucket: [DateBucket: [T]] = [:]
        for item in items {
            let b = bucket(for: date(item), now: now, calendar: calendar)
            byBucket[b, default: []].append(item)   // append → kova içi girdi sırası korunur
        }
        // Enum sırasına göre, yalnız dolu kovaları döndür.
        return DateBucket.allCases.compactMap { b in
            guard let group = byBucket[b], !group.isEmpty else { return nil }
            return (bucket: b, items: group)
        }
    }
}
