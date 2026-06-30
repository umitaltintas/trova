import Foundation

/// Bir bölümün boş durumunda gösterilecek içerik: ikon, başlık, mesaj ve (varsa) tek bir CTA.
/// Saf veri — görünümden bağımsız, test edilebilir. `actionLabel == nil` ise CTA gösterilmez.
public struct EmptyStateContent: Equatable, Sendable {
    public let systemImage: String
    public let title: String
    public let message: String
    public let actionLabel: String?   // nil → CTA yok

    public init(systemImage: String, title: String, message: String, actionLabel: String?) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
    }
}

/// Her bölüm için bağlama göre boş durum içeriği üreten saf fonksiyonlar.
/// Boş ekran bir eylem davetidir: ne yapılacağını söyler, gerekiyorsa tek net CTA verir.
public enum EmptyStates {

    /// Tüm bölümlerde ortak indeksleme daveti — başlık ve CTA tutarlı, mesaj bölüme göre değişir.
    private static func indexInvite(_ message: String) -> EmptyStateContent {
        EmptyStateContent(
            systemImage: "tray.and.arrow.down",
            title: "Önce postanı indeksle",
            message: message,
            actionLabel: "İndeksle")
    }

    /// Ara: indeks yok → indeksleme daveti; sorgu/filtre yok → arama daveti + ipucu;
    /// sorgu var → sonuç yok; yalnız filtre var → eşleşen mail yok.
    public static func search(hasIndex: Bool, hasQuery: Bool, hasFilters: Bool) -> EmptyStateContent {
        if !hasIndex {
            return indexInvite("Aramak için önce yerel posta kutunu indekslemelisin. "
                             + "İndeksleme tümüyle bilgisayarında çalışır; hiçbir şey dışarı gönderilmez.")
        }
        if hasQuery {
            // Geçerli bir sorgu vardı ama hiç sonuç yok.
            return EmptyStateContent(
                systemImage: "magnifyingglass",
                title: "Sonuç bulunamadı",
                message: "Bu sorguya uyan mail yok. Terimi değiştir, daha genel yaz ya da filtreleri temizle.",
                actionLabel: nil)
        }
        if hasFilters {
            // Sorgu yok, yalnız filtre çipleri açık ve eşleşen mail yok.
            return EmptyStateContent(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "Eşleşen mail yok",
                message: "Seçili filtrelere uyan mail yok. Filtreleri temizleyip yeniden dene.",
                actionLabel: nil)
        }
        // İndeks var, henüz arama yapılmadı — ne yazılabileceğini örnekle.
        return EmptyStateContent(
            systemImage: "magnifyingglass",
            title: "Aramaya başla",
            message: "Anahtar kelime ya da anlamsal bir sorgu yaz. Operatör ve tarih de kullanabilirsin: "
                   + "\"son 7 gün fatura\", \"from:ali\", \"has:attachment\".",
            actionLabel: nil)
    }

    /// Sor: indeks yok → indeksleme daveti; var → soru sorma daveti + örnek sorular.
    public static func ask(hasIndex: Bool) -> EmptyStateContent {
        if !hasIndex {
            return indexInvite("Sorularını yanıtlayabilmem için önce postanı indekslemelisin. "
                             + "İndeksleme tümüyle yerel çalışır.")
        }
        return EmptyStateContent(
            systemImage: "sparkles",
            title: "Postana soru sor",
            message: "Ajan arar, ilgili maili okur ve kaynaklı yanıt verir. Örnekler: "
                   + "\"geçen ay kira ile ilgili mailleri özetle\", \"Ahmet en son ne yazdı?\", "
                   + "\"bu hafta fatura geldi mi?\".",
            actionLabel: nil)
    }

    /// Bugün: yanıt bekleyen/gereken yoksa olumlu "her şey güncel" mesajı.
    public static func digest(hasNeedsReply: Bool, hasWaiting: Bool) -> EmptyStateContent {
        if !hasNeedsReply && !hasWaiting {
            return EmptyStateContent(
                systemImage: "checkmark.circle",
                title: "Bugün için temiz",
                message: "Yanıt bekleyen ya da yanıt gereken bir konu yok. "
                       + "Üstteki düğmeyle günlük brifing oluşturabilirsin.",
                actionLabel: nil)
        }
        // En az bir triyaj listesi doluysa bu görünüm pratikte gizli kalır; nötr bir özet daveti.
        return EmptyStateContent(
            systemImage: "sun.max",
            title: "Gün özetin hazır",
            message: "Aşağıdaki triyaj listelerini gözden geçir ya da günlük brifing oluştur.",
            actionLabel: nil)
    }

    /// Kişiler: indeks yok → indeksleme daveti; var ama veri yok → açıklayıcı mesaj.
    public static func people(hasIndex: Bool) -> EmptyStateContent {
        if !hasIndex {
            return indexInvite("En çok yazıştığın kişileri çıkarmak için önce postanı indeksle.")
        }
        return EmptyStateContent(
            systemImage: "person.2",
            title: "Henüz kişi yok",
            message: "Postanı indeksleyince en çok yazıştığın kişiler burada listelenir.",
            actionLabel: nil)
    }

    /// Genel Bakış: indeks yok → indeksleme daveti; var ama veri yok → açıklayıcı mesaj.
    public static func insights(hasIndex: Bool) -> EmptyStateContent {
        if !hasIndex {
            return indexInvite("İstatistikleri ve aylık hacmi görmek için önce postanı indeksle.")
        }
        return EmptyStateContent(
            systemImage: "chart.bar",
            title: "Henüz veri yok",
            message: "Bu dönemde gösterilecek mail yok. İndeksleme tamamlanınca istatistikler burada belirir.",
            actionLabel: nil)
    }

    /// Ekler: hiç ek yok → açıklama + İndeksle ipucu; arama/filtre eşleşmedi → eşleşen ek yok + temizle.
    public static func attachments(hasAny: Bool, hasQueryOrFilter: Bool) -> EmptyStateContent {
        if hasQueryOrFilter {
            // Arama ya da tür filtresi aktif ama eşleşen ek yok.
            return EmptyStateContent(
                systemImage: "paperclip",
                title: "Eşleşen ek yok",
                message: "Bu ada ya da türe uyan ek bulunamadı. Aramayı kısalt ya da tür filtresini kaldır.",
                actionLabel: nil)
        }
        if !hasAny {
            // Depoda hiç ek yok.
            return indexInvite("Postanı indeksleyince gelen tüm dosya ekleri burada toplanır; "
                             + "bir eke tıklayınca uygun uygulamada açılır.")
        }
        // hasAny && !hasQueryOrFilter: liste normalde dolu olurdu; güvenli nötr durum.
        return EmptyStateContent(
            systemImage: "paperclip",
            title: "Henüz ek yok",
            message: "Ada ya da türe göre eklerini burada arayabilirsin.",
            actionLabel: nil)
    }

    /// Benzer mailler: hiç vektör yoksa "Gömme" daveti; varsa bu maile yakın başka mail yok.
    public static func similar(hasVectors: Bool) -> EmptyStateContent {
        if !hasVectors {
            return EmptyStateContent(
                systemImage: "sparkles",
                title: "Anlamsal benzerlik için gömme gerekli",
                message: "Benzer mailleri bulabilmem için önce 'Gömme' çalıştırarak maillerinin "
                       + "anlamsal vektörlerini üretmelisin. Gömme tümüyle yerel çalışabilir.",
                actionLabel: nil)
        }
        return EmptyStateContent(
            systemImage: "square.stack.3d.up",
            title: "Benzer mail bulunamadı",
            message: "Bu maile anlamsal olarak yakın başka mail yok. Bu mail henüz gömülü "
                   + "olmayabilir; daha fazla mail gömersen benzerlik sonuçları iyileşir.",
            actionLabel: nil)
    }
}
