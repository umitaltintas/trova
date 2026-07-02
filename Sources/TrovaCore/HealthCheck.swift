import Foundation

/// Tek bir sağlık kontrolünün sonucu.
public enum HealthStatus: String, Sendable, Equatable {
    case ok      // her şey yolunda
    case warn    // çalışır ama eksik/iyileştirilebilir
    case fail    // temel işlevi engelleyen sorun
}

/// Kurulum/teşhis ekranında gösterilen tek bir madde.
public struct HealthItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let status: HealthStatus
    public let detail: String

    public init(id: String, title: String, status: HealthStatus, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

/// Sağlık değerlendirmesi için canlı ortamdan toplanan girdiler.
/// Saf veri olduğu için `HealthCheck.evaluate` birim testlerle doğrulanabilir.
public struct HealthInput: Sendable, Equatable {
    public var mailStoreReadable: Bool   // Full Disk Access: ~/Library/Mail okunabiliyor mu
    public var mailStoreLocated: Bool    // V<n> deposu bulundu mu
    public var indexedCount: Int         // indekslenmiş mail sayısı
    public var vectorCount: Int          // gömülmüş (vektörü olan) mail sayısı
    public var llmConfigured: Bool       // OpenRouter anahtarı / ortam ayarlı mı
    public var embedderConfigured: Bool  // kullanılabilir bir embedding sağlayıcısı var mı
    public var usesLocalEmbedder: Bool   // sağlayıcı yerel (ölçülen zayıf sıralama) mı
    public var autoEmbedEnabled: Bool    // "Yeni mailleri otomatik göm" ayarı açık mı

    public init(mailStoreReadable: Bool, mailStoreLocated: Bool, indexedCount: Int,
                vectorCount: Int, llmConfigured: Bool, embedderConfigured: Bool,
                usesLocalEmbedder: Bool, autoEmbedEnabled: Bool = true) {
        self.mailStoreReadable = mailStoreReadable
        self.mailStoreLocated = mailStoreLocated
        self.indexedCount = indexedCount
        self.vectorCount = vectorCount
        self.llmConfigured = llmConfigured
        self.embedderConfigured = embedderConfigured
        self.usesLocalEmbedder = usesLocalEmbedder
        self.autoEmbedEnabled = autoEmbedEnabled
    }
}

/// Bir dizi sağlık maddesi ve bunlardan türeyen genel durum.
public struct HealthReport: Sendable, Equatable {
    public let items: [HealthItem]

    public init(items: [HealthItem]) { self.items = items }

    public func item(_ id: String) -> HealthItem? { items.first { $0.id == id } }

    /// Sorgu yapmaya hazır mı: erişim var ve en az bir mail indeksli.
    public var isReady: Bool {
        item("fda")?.status == .ok && item("index")?.status == .ok
    }

    /// İlk-çalıştırma kurulum kapısı gösterilmeli mi (henüz hazır değilse).
    public var needsSetup: Bool { !isReady }

    /// En kötü madde durumu (fail > warn > ok) — kenar çubuğu rozetinin rengi.
    public var overall: HealthStatus {
        if items.contains(where: { $0.status == .fail }) { return .fail }
        if items.contains(where: { $0.status == .warn }) { return .warn }
        return .ok
    }
}

/// Trova'nın kurulum durumunu değerlendirip kullanıcıya gösterilecek
/// adım adım teşhis listesini üretir. Tamamen saf; ağ/dosya erişimi yapmaz.
public enum HealthCheck {
    public static func evaluate(_ input: HealthInput) -> HealthReport {
        var items: [HealthItem] = []

        // 1) Full Disk Access — her şeyin önkoşulu.
        items.append(HealthItem(
            id: "fda",
            title: "Tam Disk Erişimi",
            status: input.mailStoreReadable ? .ok : .fail,
            detail: input.mailStoreReadable
                ? "Trova ~/Library/Mail'i okuyabiliyor."
                : "Sistem Ayarları › Gizlilik ve Güvenlik › Tam Disk Erişimi'nden Trova'yı ekleyip açın."))

        // 2) Mail deposu — yalnızca erişim varken anlamlı (V<n> klasörü mevcut mu).
        if input.mailStoreReadable {
            items.append(HealthItem(
                id: "store",
                title: "Mail deposu",
                status: input.mailStoreLocated ? .ok : .fail,
                detail: input.mailStoreLocated
                    ? "Yerel Apple Mail deposu bulundu."
                    : "~/Library/Mail altında bir depo (V klasörü) yok. Apple Mail'i bir kez açıp hesap ekleyin."))
        }

        // 3) İndeks — en az bir mail indekslenmiş olmalı.
        let indexStatus: HealthStatus = !input.mailStoreReadable
            ? .warn                                  // erişim yokken indekslenemez; ön koşula düşür
            : (input.indexedCount > 0 ? .ok : .fail)
        items.append(HealthItem(
            id: "index",
            title: "İndeks",
            status: indexStatus,
            detail: input.indexedCount > 0
                ? "\(input.indexedCount.formatted()) mail indeksli."
                : "Henüz mail indekslenmedi. \"İndeksle\" ile başlayın."))

        // 4) Anlamsal kapsam — vektör oranı.
        let coverage = input.indexedCount > 0
            ? Double(input.vectorCount) / Double(input.indexedCount) : 0
        let vecStatus: HealthStatus
        let vecDetail: String
        // Otomatik gömme yalnız bir sağlayıcı kuruluysa VE ayar açıksa kendiliğinden tamamlar; iki
        // koşul da sağlanıyorsa kullanıcıya elle "Gömme" değil, arka planda tamamlanacağını söyleriz.
        let autoWillFinish = input.autoEmbedEnabled && input.embedderConfigured
        if input.indexedCount == 0 {
            vecStatus = .warn
            vecDetail = autoWillFinish
                ? "Otomatik gömme açık — indeksleme sonrası gömme arka planda kendiliğinden yapılır."
                : "İndeks oluştuktan sonra anlamsal arama için \"Gömme\" çalıştırın."
        } else if input.vectorCount == 0 {
            vecStatus = .warn
            vecDetail = autoWillFinish
                ? "Anlamsal arama henüz kapalı. Otomatik gömme açık; mailler arka planda kendiliğinden gömülür."
                : "Anlamsal arama kapalı. \"Gömme\" ile vektörleri oluşturun."
        } else if coverage < 0.9 {
            vecStatus = .warn
            vecDetail = autoWillFinish
                ? "Maillerin %\(Int(coverage * 100))'i gömülü. Kalanı otomatik gömme ile arka planda kendiliğinden tamamlanır."
                : "Maillerin %\(Int(coverage * 100))'i gömülü. Kalanı için \"Gömme\" çalıştırın."
        } else {
            vecStatus = .ok
            vecDetail = "Anlamsal arama hazır (%\(Int(coverage * 100)))."
        }
        items.append(HealthItem(id: "vectors", title: "Anlamsal kapsam",
                                status: vecStatus, detail: vecDetail))

        // 5) AI anahtarı — "Sor", özet ve günlük brifing için gerekli.
        items.append(HealthItem(
            id: "llm",
            title: "AI anahtarı",
            status: input.llmConfigured ? .ok : .warn,
            detail: input.llmConfigured
                ? "OpenRouter anahtarı ayarlı."
                : "\"Sor\", özet ve \"Bugün\" brifingi için Ayarlar'dan bir OpenRouter anahtarı ekleyin."))

        // 6) Embedding sağlayıcısı — yalnızca yapılandırılmışsa not düş.
        //    Yerel model (NLContextualEmbedding) cihaz-üstü ve anahtarsızdır; yine de
        //    mean-pool sıralaması bulut modellerinden zayıf olduğundan uyarı (warn) kalır.
        if input.embedderConfigured {
            items.append(HealthItem(
                id: "embedder",
                title: "Embedding sağlayıcısı",
                status: input.usesLocalEmbedder ? .warn : .ok,
                detail: input.usesLocalEmbedder
                    ? "Yerel model (cihaz-üstü, anahtarsız) etkin. Sıralama kalitesi için Ayarlar'dan bulut sağlayıcı seçebilirsiniz."
                    : "Bulut embedding sağlayıcısı ayarlı."))
        }

        return HealthReport(items: items)
    }
}
