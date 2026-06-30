import Foundation
import AppKit
import TrovaCore

enum DateRange: String, CaseIterable, Identifiable {
    case all, week, month, year
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "Tüm zamanlar"
        case .week: "Son 7 gün"
        case .month: "Son 30 gün"
        case .year: "Son 1 yıl"
        }
    }
    var since: Date? {
        switch self {
        case .all: nil
        case .week: Date().addingTimeInterval(-7 * 86_400)
        case .month: Date().addingTimeInterval(-30 * 86_400)
        case .year: Date().addingTimeInterval(-365 * 86_400)
        }
    }
}

enum AppError: Error, CustomStringConvertible {
    case noMailStore, noEmbedder, noLLM
    var description: String {
        switch self {
        case .noMailStore: return "Mail deposu bulunamadı (Full Disk Access verili mi?)."
        case .noEmbedder: return "Embedding sağlayıcısı yok. Ayarlar'dan yapılandırın."
        case .noLLM: return "OpenRouter anahtarı yok. Ayarlar'dan ekleyin."
        }
    }
}

@MainActor
@Observable
final class AppModel {
    struct AccountStat: Identifiable, Sendable {
        let id = UUID(); let account: String; let count: Int
    }

    /// Sohbetteki bir tur: soru + ajanın adımları, yanıtı ve kaynakları.
    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        var answer = ""
        var steps: [AgentStep] = []
        var cited: [SearchHit] = []
        var verification: Verification?      // opsiyonel yanıt doğrulama sonucu
        var running = true
    }

    enum Section: Equatable { case ask, search, digest, people, insights, attachments }
    var section: Section = .ask

    // Klavye kısayolları kılavuzu (⌘/) açık mı — sheet bunu izler; palet komutu da bunu açar.
    var showShortcuts = false

    // Durum
    var hasAccess = false
    var mailRoot: String?
    var totalCount = 0
    var vectorCount = 0
    var memoryCount = 0
    var attachmentContentCount = 0   // ek içeriği indekslenmiş mail sayısı (Ayarlar göstergesi)
    var duplicateCount = 0           // aynı Message-ID'li yinelenen (fazladan) satır sayısı (Bakım göstergesi)
    var accounts: [AccountStat] = []

    // Kişiler (en çok yazışılanlar)
    var people: [SenderStat] = []
    var peopleQuery = ""                  // ada/adrese göre süzme (boşken en-çok-yazışılanlar)
    var selectedPersonAddress: String?
    var personMails: [SearchHit] = []
    var personDetail: SenderDetail?      // seçili kişinin mini analitiği

    // Genel Bakış (insights)
    var monthly: [MonthCount] = []
    var monthlyBalance: [MonthSentReceived] = []   // aylık gelen vs gönderilen dağılımı
    var weekdayActivity: [WeekdayCount] = []       // haftanın gününe göre mail dağılımı
    var attachmentTotal = 0

    // Ekler görünümü (tüm eklerin ada/türe göre aranabilir listesi)
    var attachments: [AttachmentRow] = []
    var attachmentQuery = ""                       // ad araması (LIKE)
    var attachmentKind: AttachmentKind?            // seçili kategori filtresi (nil → tümü)
    var attachmentKindCounts: [AttachmentKind: Int] = [:]   // kategori çiplerindeki sayılar
    var isLoadingAttachments = false               // ek listesi yüklenirken iskelet göstermek için

    // Sağlık / kurulum (HealthCheck girdileri)
    var llmConfigured = false
    var embedderConfigured = false
    var usesLocalEmbedder = false
    var statusLoaded = false        // ilk durum yüklemesi bitti mi (kurulum kapısı yanıp sönmesin)

    // Bağlantı testi (Ayarlar → AI): yapılandırılmış LLM/embedding sağlayıcılarına canlı istek sonuçları.
    var connectionResults: [ConnectionResult] = []
    var isTestingConnection = false

    /// Canlı kurulum durumundan teşhis raporu üretir (saf — yalnız depolanmış bayrakları okur).
    var health: HealthReport {
        HealthCheck.evaluate(HealthInput(
            mailStoreReadable: hasAccess,
            mailStoreLocated: mailRoot != nil,
            indexedCount: totalCount,
            vectorCount: vectorCount,
            llmConfigured: llmConfigured,
            embedderConfigured: embedderConfigured,
            usesLocalEmbedder: usesLocalEmbedder))
    }

    /// İlk-çalıştırma kurulum kapısı gösterilmeli mi.
    /// Erişim yoksa hemen; erişim varsa yalnız durum yüklendikten sonra (boş indeks) karar verilir.
    var shouldShowSetup: Bool {
        if !hasAccess { return true }
        return statusLoaded && health.needsSetup
    }

    // Arama
    var query = ""
    var mode: SearchMode = .hybrid
    var results: [SearchHit] = []            // ham, alaka sıralı sonuçlar (arama motorundan)
    var resultSort: ResultSort = .relevance  // kullanıcının seçtiği gösterim sıralaması
    var selection: SearchHit.ID?
    var selectedBody: String?
    var selectedHTML: String?
    var selectedThread: [SearchHit] = []
    var threadSummary: String?           // "Konuyu özetle" çıktısı (markdown)
    var summaryThreadKey: String?        // özetin ait olduğu thread (başka thread'e geçince gizlenir)
    var isSummarizing = false
    var replyDraft: String?              // "Yanıt taslağı" çıktısı (canlı dolar; markdown)
    var replyDraftHit: String?           // taslağın ait olduğu mail id (başka maile geçince gizlenir)
    var isDraftingReply = false
    var draftError: String?              // taslak üretiminde oluşan hata (kart içinde gösterilir)
    var selectedMessageID: String?       // seçili mailin RFC822 Message-ID'si ("Mail'de Aç" için)
    var isSearching = false
    var detectedDateLabel: String?       // sorgudan algılanan Türkçe tarih ifadesi etiketi (örn. "son 7 gün")
    var searchFromLabel: String?         // from:/gönderen: operatörü etiketi
    var searchHasAttachment = false      // has:attachment operatörü etkin mi
    var searchAttachmentKind: AttachmentKind?   // has:<tür> operatörüyle seçilen ek türü (çip için)
    var expansionChips: [String] = []    // PRF ile sorguya eklenen terimler (gösterim)
    var highlightTerms: [String] = []    // sonuç snippet'lerinde vurgulanacak terimler (temizlenmiş sorgu + genişletme)
    var activeSenderFilter: String?      // tıklanan gönderen facet'i (istemci tarafı daraltma; yeniden sorgu YOK)

    // Benzer mailler (embedding tabanlı more-like-this) — yalnız kullanıcı isteyince yüklenir.
    var similarMails: [SearchHit] = []
    var isLoadingSimilar = false
    var showSimilarSheet = false
    var similarSourceSubject: String?    // benzerlerin ait olduğu mailin konusu (sheet başlığı için)

    // Filtre
    var filterAccount = ""          // "" → tüm hesaplar (accountID)
    var dateRange: DateRange = .all
    var unreadOnly = false          // yalnızca okunmamış mailler
    var flaggedOnly = false         // yalnızca bayraklı mailler
    var pinnedOnly = false          // yalnızca Trova-yerel yıldızlı (pinned) mailler
    var activeQuickDate: QuickDateRange?   // aktif hızlı tarih çipi (Bugün/Son 7g/Son 30g/Bu yıl); runSearch tarihini geçersiz kılar

    // Trova-yerel yıldızlı (pin) koleksiyonu: gösterim için yüklenen id kümesi (message.id).
    // Sonuç satırı yıldız rozeti + ReadingPane "Yıldızla/Yıldızı kaldır" toggle'ı bunu izler.
    var pinnedIDs: Set<String> = []

    // Arama sonuçlarında çoklu seçim (toplu aksiyon): seçili mail id'leri (message.id).
    // Sonuç satırı onay kutusu + toplu aksiyon çubuğu bunu izler; yeni aramada sıfırlanır.
    var selectedResultIDs: Set<String> = []

    // Kayıtlı aramalar
    var savedSearches: [SavedSearch] = []
    // Her kayıtlı aramanın şu anki canlı eşleşme sayısı (akıllı klasör rozeti). id → sayı.
    var savedSearchCounts: [String: Int] = [:]

    // Son aramalar (otomatik arama geçmişi — kullanıcı arama yaptıkça birikir)
    var recentSearches: [String] = []

    // Ask (AI ajan — sohbet)
    var question = ""
    var conversation: [Exchange] = []
    var isAsking = false
    var currentConversationId: String?          // açık sohbetin kalıcı kimliği (yoksa yeni sohbet)
    var conversations: [ConversationSummary] = []  // geçmiş sohbet tarayıcısı için
    var memories: [Memory] = []                  // hafıza görüntüleyici listesi

    // Bugün (proaktif asistan — triyaj + günlük brifing)
    var needsReply: [SearchHit] = []     // yanıt gerekiyor: karşı taraf en son yazdı (gizlenenler süzülmüş)
    var waitingOn: [SearchHit] = []      // yanıt bekliyor: sen en son yazdın, yanıt yok (gizlenenler süzülmüş)
    var dismissedHiddenCount = 0         // şu an triyaj listelerinden GİZLENEN (görmezden gelinen) öğe sayısı
    var digestText = ""
    var isDigesting = false

    /// Kenar çubuğu "Bugün" rozeti için yanıt-bekleyen sayısı: gizlenenler süzülmüş `needsReply`.
    /// (waitingOn dahil DEĞİL — "yanıt bekleyen" = senin yanıtlaman gereken mailler.) Triyaj henüz
    /// yüklenmediyse `needsReply` boş olduğundan 0; `loadTriage`/dismiss/restore ile kendiliğinden tazelenir.
    var pendingReplyCount: Int { needsReply.count }

    // Yeni mail göstergesi (FSEvents canlı tazeleme): autoSync açıkken artımlı reindex bitince
    // eklenen mail sayısı burada birikir; kullanıcı rozete dokununca (clearNewMail) sıfırlanır.
    var newMailCount = 0

    // Uzun işler
    var busy = false
    var progress = ""
    var errorMessage: String?
    var jobProcessed = 0
    var jobTotal = 0
    private var currentTask: Task<Void, Never>?
    private var cancelFlag: CancellationFlag?
    private var watcher: MailWatcher?

    // FSEvents akışını birleştirme (debounce) durumu — yalnız autoSync açıkken kullanılır.
    private let refreshCoalescer = RefreshCoalescer(window: 2)
    private var fsEventTimes: [Date] = []     // henüz tetiklenmemiş FS olaylarının zaman damgaları
    private var lastReindexFired: Date?       // son birleştirilmiş reindex tetiği

    init() {
        // Otomatik arama geçmişini kalıcı depodan yükle.
        recentSearches = RecentSearchesStore.load()
    }

    /// Ham `results` üzerine yalnız seçili sıralama uygulanmış liste (gönderen filtresi UYGULANMADAN).
    /// `resultSort` değişince YENİDEN SORGU yapılmaz; yalnız bu liste yeniden hesaplanır.
    var sortedResults: [SearchHit] {
        ResultSorter.sort(results, by: resultSort)
    }

    /// Kullanıcıya gösterilen nihai liste: sıralı sonuçlar, varsa aktif gönderen facet'iyle daraltılmış.
    /// Liste (sayaç/dışa aktarım/klavye) bunu izler; facet sayıları ise filtre öncesi kümeden gelir.
    var displayedResults: [SearchHit] {
        guard let sender = activeSenderFilter else { return sortedResults }
        return Facets.filter(sortedResults, bySender: sender)
    }

    /// Sonuçlardaki en sık gönderenler (sayılı çipler). Filtre UYGULANMADAN ham `results`'tan
    /// hesaplanır ki bir gönderen seçilince çipler kaybolmasın ve sayılar sabit kalsın.
    var senderFacets: [Facet] {
        Facets.senders(results)
    }

    /// Bir gönderen facet'ine tıklayınca istemci tarafı daraltmayı uygular (yeniden sorgu YOK).
    /// `nil` geçilince filtreyi temizler. Her iki durumda gösterilen listenin ilkini seçer.
    func applySenderFilter(_ sender: String?) {
        activeSenderFilter = sender
        selection = displayedResults.first?.id
        loadSelected()
    }

    var selectedHit: SearchHit? {
        guard let selection else { return nil }
        func find(_ hits: [SearchHit]) -> SearchHit? { hits.first { $0.id == selection } }
        return find(results)
            ?? find(selectedThread)
            ?? find(needsReply)
            ?? find(waitingOn)
            ?? find(personMails)
            ?? find(similarMails)
            ?? find(conversation.flatMap(\.cited))
    }

    /// Seçili mail Trova-yerel yıldızlı mı (ReadingPane "Yıldızla/Yıldızı kaldır" toggle'ı için).
    var isSelectedPinned: Bool {
        guard let id = selection else { return false }
        return pinnedIDs.contains(id)
    }

    /// Açık bölüme göre klavyeyle gezinilebilir aktif mail id listesi (görünen sırayla).
    var navigableIDs: [String] {
        switch section {
        case .search:   displayedResults.map(\.id)
        case .people:   personMails.map(\.id)
        case .digest:   (needsReply + waitingOn).map(\.id)
        case .ask:      conversation.flatMap(\.cited).map(\.id)
        case .insights: []
        case .attachments: []   // ekler okuma panelinde değil, dosya olarak açılır
        }
    }

    /// Aktif listede `delta` yönündeki komşu maile geçer ve okuma panelinde açar (uçlarda kenetlenir).
    func selectAdjacent(_ delta: Int) {
        guard let next = Navigation.adjacent(ids: navigableIDs, current: selection, delta: delta) else { return }
        selection = next
        loadSelected()
    }

    /// Yaşı kısa bir etikete çevirir ("şimdi" / "3g" / "dün") — tek kaynak: RelativeTime.
    /// Tarih yoksa boş döner (dışa aktarımda parantezli yaş bölümü gösterilmez).
    static func ageLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        return RelativeTime.short(date, now: Date())
    }

    /// "Bugün" brifingini (brifing metni + triyaj listeleri) paylaşılabilir Markdown'a döker.
    func digestMarkdown() -> String {
        func items(_ hits: [SearchHit]) -> [DigestItem] {
            hits.map { hit in
                DigestItem(
                    from: hit.fromName ?? hit.fromAddress ?? "Bilinmeyen gönderen",
                    subject: hit.subject ?? "(konu yok)",
                    ageLabel: AppModel.ageLabel(hit.date))
            }
        }
        let title = "Bugün — " + Date().formatted(date: .long, time: .omitted)
        return MarkdownExporter.digest(title: title, briefing: digestText,
                                       needsReply: items(needsReply), waitingOn: items(waitingOn))
    }

    /// Bir mail listesini dışa aktarılabilir maddelere çevirir (gönderen + konu + göreli tarih + kutu).
    /// Tarih yoksa etiket boş bırakılır; kutu her zaman doldurulur (MarkdownExporter boşsa atlar).
    private func listItems(_ hits: [SearchHit]) -> [ExportedListItem] {
        let now = Date()
        return hits.map { hit in
            ExportedListItem(
                from: hit.fromName ?? hit.fromAddress ?? "Bilinmeyen gönderen",
                subject: hit.subject ?? "(konu yok)",
                dateLabel: hit.date.map { RelativeTime.short($0, now: now) } ?? "",
                mailbox: hit.mailbox)
        }
    }

    /// Arama sonuçlarını Markdown listesine döker. Başlık: sorgu varsa "Arama: <sorgu>", yoksa "Arama sonuçları".
    func exportSearchResults() -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = q.isEmpty ? "Arama sonuçları" : "Arama: \(q)"
        // Dışa aktarım kullanıcının gördüğü listeyi (seçili sıralama + aktif gönderen filtresi) izler.
        return MarkdownExporter.emailList(title: title, items: listItems(displayedResults))
    }

    /// Seçili kişinin maillerini Markdown listesine döker. Başlık: kişinin adı (yoksa adresi).
    func exportPersonMails() -> String {
        let address = selectedPersonAddress ?? ""
        let name = people.first { $0.address == address }?.name
        let title = name ?? (address.isEmpty ? "Kişi mailleri" : address)
        return MarkdownExporter.emailList(title: title, items: listItems(personMails))
    }

    /// "Benzer mailler" listesini Markdown'a döker.
    func exportSimilar() -> String {
        MarkdownExporter.emailList(title: "Benzer mailler", items: listItems(similarMails))
    }

    /// Arama sonuçlarını elektronik tabloya uygun CSV'ye döker (Markdown ile aynı listeyi izler).
    func exportSearchResultsCSV() -> String {
        CsvExporter.emailList(listItems(displayedResults))
    }

    /// Seçili kişinin maillerini CSV'ye döker.
    func exportPersonMailsCSV() -> String {
        CsvExporter.emailList(listItems(personMails))
    }

    /// "Benzer mailler" listesini CSV'ye döker.
    func exportSimilarCSV() -> String {
        CsvExporter.emailList(listItems(similarMails))
    }

    func cancelJob() {
        cancelFlag?.cancel()
        currentTask?.cancel()
        progress = "İptal ediliyor…"
    }

    // MARK: - Otomatik senkron (FSEvents)

    func setAutoSync(_ enabled: Bool) {
        enabled ? startWatching() : stopWatching()
    }

    private func startWatching() {
        guard watcher == nil, hasAccess, let root = MailStore.locate() else { return }
        let watcher = MailWatcher(root: root) { [weak self] in
            Task { @MainActor in self?.onMailChanged() }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
        // autoSync kapanınca canlı-tazeleme durumu sıfırlanır ve rozet temizlenir (devre dışı davranış).
        fsEventTimes.removeAll()
        lastReindexFired = nil
        newMailCount = 0
    }

    /// FSEvents'ten gelen her değişiklik bildirimini kaydeder ve birleştirme (debounce) kontrolünü planlar.
    private func onMailChanged() {
        fsEventTimes.append(Date())
        scheduleCoalescedReindex()
    }

    /// Sessizlik penceresi kadar bekleyip RefreshCoalescer kararına göre birleştirilmiş reindex tetikler.
    /// Pencere içinde gelen birden çok olay tek bir tetiğe iner; tetik sonrası eski kontroller etkisizdir.
    private func scheduleCoalescedReindex() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(refreshCoalescer.window))
            let now = Date()
            guard refreshCoalescer.shouldFire(events: fsEventTimes, now: now, lastFired: lastReindexFired)
            else { return }
            lastReindexFired = now
            fsEventTimes.removeAll()
            runAutoReindex()
        }
    }

    /// autoSync: birleştirilmiş FS olayı sonrası artımlı reindex. Bitince yeni-mail sayacını ekler ve
    /// (kullanıcı meşgul değilse) görünür görünümü sessizce tazeler. Manuel iş sürerken çakışmaz.
    private func runAutoReindex() {
        guard !busy else { return }   // manuel indeksle/gömme sürüyorsa bu turu atla
        busy = true; errorMessage = nil; jobProcessed = 0; jobTotal = 0
        progress = "Yeni mail algılandı, güncelleniyor…"
        let flag = CancellationFlag(); cancelFlag = flag
        // Opt-in ek içeriği ayarı: yeni gelen maillerde de (AÇIKsa) ek metni indekslenir.
        let indexAttContent = UserDefaults.standard.bool(forKey: SettingsKeys.indexAttachmentContent)
        currentTask = Task {
            let result = await background { () -> IndexResult in
                guard let root = MailStore.locate() else { throw AppError.noMailStore }
                let store = try IndexStore(path: AppPaths.databaseURL)
                // PRUNE KAPALI: FSEvents tetikli otomatik senkron, Apple Mail mail taşırken/yazarken
                // de patlayabilir; o anlık durumda bir `.emlx` geçici olarak kaybolmuş görünebilir.
                // Silinen mailleri düşürmeyi (prune) güvenli, kullanıcı tetikli TAM "İndeksle"ye
                // bırakırız — burada yanlışlıkla satır silmeyiz (yalnız ekler/güncelleriz).
                return try Indexer.run(store: store, root: root,
                                       indexAttachmentContent: indexAttContent,
                                       pruneMissing: false, cancel: flag) { processed, total in
                    Task { @MainActor in
                        self.jobProcessed = processed; self.jobTotal = total
                        self.progress = "İndeksleniyor \(processed)/\(total)"
                    }
                }
            }
            // Meşguliyet bayraklarını ÖNCE sıfırla ki görünür tazeleme (busy kontrolü) çalışabilsin.
            busy = false; currentTask = nil; cancelFlag = nil
            refreshStatus()
            guard let result else { return }
            progress = result.processed > 0
                ? "\(result.inserted) yeni · \(result.duplicates) kopya · \(result.skipped) atlandı · \(result.failed) hata"
                : "Mail bulunamadı"
            // Churn kapısı (iter 24): YALNIZ gerçek tekil yeni mail (inserted>0) varken rozeti artır
            // ve görünür listeyi sessizce tazele. Kopya `.emlx`'ler (forward-dedup sayesinde) inserted
            // üretmez → 0-yeni turlarda rozet artmaz, liste sabit kalır (senkron churn'ü durur).
            if result.inserted > 0 {
                newMailCount += result.inserted
                refreshVisibleSection()
            }
        }
    }

    /// Kullanıcıyı bölmeden açık bölümü sessizce tazeler — yalnız aktif bir iş (soru/arama/indeksleme/
    /// özet/brifing) yokken. Aktifse görünüme dokunmaz; rozet+sayı zaten ayrıca güncellenir.
    private func refreshVisibleSection() {
        guard !isAsking, !isSearching, !isDigesting, !isSummarizing, !busy else { return }
        switch section {
        case .search:
            // Yalnız anlamlı bir sorgu/filtre varsa mevcut aramayı sessizce yeniden çalıştır.
            let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasQuery || unreadOnly || flaggedOnly || pinnedOnly || activeQuickDate != nil { runSearch() }
        case .digest:
            loadTriage()              // triyaj listeleri (LLM brifingine dokunmadan)
        case .insights:
            loadInsights()
        case .people:
            loadPeople()
            if let address = selectedPersonAddress { selectPerson(address) }
        case .attachments:
            loadAttachments()         // mevcut arama/filtreyle ek listesini tazele
        case .ask:
            break                     // açık sohbeti elleme
        }
    }

    /// "N yeni mail" rozetine dokununca: sayacı sıfırlar ve açık görünümü tazeler.
    func clearNewMail() {
        newMailCount = 0
        refreshVisibleSection()
    }

    func onAppear() {
        refreshAccess()
        refreshStatus()
    }

    func refreshAccess() {
        hasAccess = MailStore.canAccess()
        mailRoot = MailStore.locate()?.path
        refreshProviders()
    }

    /// Sağlayıcı yapılandırma bayraklarını ağır nesne kurmadan (yalnız anahtar/ayar okuyarak) tazeler.
    func refreshProviders() {
        let defaults = UserDefaults.standard
        let provider = defaults.string(forKey: SettingsKeys.embedProvider) ?? "local"
        let embedKey = Keychain.get(KeychainKeys.embedKey)
        let llmKey = Keychain.get(KeychainKeys.llmKey)

        llmConfigured = !llmKey.isEmpty || OpenRouterClient.fromEnvironment() != nil
        usesLocalEmbedder = provider == "local"
        switch provider {
        case "openai", "voyage": embedderConfigured = !embedKey.isEmpty
        case "openrouter":       embedderConfigured = !(embedKey.isEmpty && llmKey.isEmpty)
        default:                 embedderConfigured = true   // yerel her zaman kullanılabilir
        }
    }

    /// Ayarlardan canlı bağlantı testi: yapılandırılmış LLM ve embedding sağlayıcısına minik birer
    /// istek (LLM "ping" sohbeti, embedder kısa metin gömme) atıp gerçek sonucu toplar. HTTP durumu
    /// hata tipinden/mesajından çıkarılıp `ConnectionTest` ile Türkçe sonuca (✓/✗) çevrilir.
    /// Anahtar yoksa o servis "yapılandırılmamış" olarak işaretlenir (istek atılmaz).
    func testConnection() {
        guard !isTestingConnection else { return }
        isTestingConnection = true
        connectionResults = []
        let llm = Providers.llm()
        let embedder = Providers.embedder()
        let usesLocal = (UserDefaults.standard.string(forKey: SettingsKeys.embedProvider) ?? "local") == "local"
        Task {
            defer { isTestingConnection = false }
            var results: [ConnectionResult] = []

            // 1) LLM — kısa bir "ping" sohbeti at.
            if let llm {
                results.append(await Task.detached(priority: .userInitiated) {
                    do {
                        _ = try llm.complete(messages: [ChatMessage(role: "user", content: "ping")],
                                             temperature: 0)
                        return ConnectionTest.result(service: "LLM", error: nil)
                    } catch {
                        return ConnectionTest.result(service: "LLM", error: error)
                    }
                }.value)
            } else {
                results.append(ConnectionResult(service: "LLM", status: .unknown,
                    detail: "LLM: Yapılandırılmamış (Ayarlar'dan OpenRouter anahtarı ekleyin)"))
            }

            // 2) Embedding — kısa bir metni göm (yerelde offline doğrulama, API'de canlı istek).
            let embedService = usesLocal ? "Embedding (yerel)" : "Embedding"
            if let embedder {
                results.append(await Task.detached(priority: .userInitiated) {
                    do {
                        _ = try embedder.embed("ping")
                        return ConnectionTest.result(service: embedService, error: nil)
                    } catch {
                        return ConnectionTest.result(service: embedService, error: error)
                    }
                }.value)
            } else {
                results.append(ConnectionResult(service: embedService, status: .unknown,
                    detail: "\(embedService): Yapılandırılmamış"))
            }

            connectionResults = results
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshStatus() {
        Task {
            guard let stats = await background({ () -> (Int, Int, Int, Int, Int, [AccountStat]) in
                let store = try IndexStore(path: AppPaths.databaseURL)
                let accounts = try store.accountCounts().map { AccountStat(account: $0.account, count: $0.count) }
                return (try store.count(), try store.vectorCount(), try store.memoryCount(),
                        try store.attachmentContentCount(), try store.duplicateCount(), accounts)
            }) else { return }
            totalCount = stats.0; vectorCount = stats.1; memoryCount = stats.2
            attachmentContentCount = stats.3; duplicateCount = stats.4; accounts = stats.5
            statusLoaded = true
        }
        refreshProviders()
        loadTriage()   // indeksleme/durum yenilemesi sonrası triyaj listeleri de tazelensin
        loadConversations()
        loadMemories()
        loadPeople()
        loadSavedSearches()
        loadInsights()
        loadAttachments()
        loadPinned()
    }

    /// Ekler görünümünü tazeler: mevcut ad araması + kategori filtresine uyan ekleri ve
    /// kategori çip sayılarını arka planda yükler.
    func loadAttachments() {
        let q = attachmentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = attachmentKind
        isLoadingAttachments = true
        Task {
            defer { isLoadingAttachments = false }
            guard let data = await background({ () -> (rows: [AttachmentRow], counts: [AttachmentKind: Int]) in
                let store = try IndexStore(path: AppPaths.databaseURL)
                return (try store.allAttachments(query: q.isEmpty ? nil : q, kind: kind, limit: 500),
                        try store.attachmentKindCounts())
            }) else { return }
            attachments = data.rows
            attachmentKindCounts = data.counts
        }
    }

    /// Bir ek satırını açar: sahip `.emlx`'ten eki ada göre çıkarıp geçici dosyaya yazar ve sistemde açar.
    /// (Mevcut `extractAttachments` akışını yeniden kullanır; satır zaten `filePath` taşır.)
    func openAttachmentRow(_ row: AttachmentRow) {
        Task {
            let result = await background { () -> URL? in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: row.filePath)) else { return nil }
                guard let att = EMLXParser.extractAttachments(data: data)
                    .first(where: { $0.filename == row.fileName }) else { return nil }
                // Dosya adını güvenli kıl (yol bileşeni kaçışını önle).
                let safe = (att.filename as NSString).lastPathComponent
                let fileName = safe.isEmpty ? "ek" : safe
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("trova-ekler", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let fileURL = dir.appendingPathComponent(fileName)
                try att.data.write(to: fileURL)
                return fileURL
            }
            guard let url = result.flatMap({ $0 }) else {
                errorMessage = "Ek açılamadı: \(row.fileName)"; return
            }
            NSWorkspace.shared.open(url)
        }
    }

    /// Ek satırının sahip mailini native Apple Mail.app'te açar (RFC822 Message-ID'yi bularak).
    func openRowInMail(_ row: AttachmentRow) {
        Task {
            let rfc = await background {
                try IndexStore(path: AppPaths.databaseURL).messageID(forID: row.messageID)
            }
            guard let url = MailLink.appleMailURL(messageID: rfc.flatMap({ $0 })) else {
                errorMessage = "Bu mailin Message-ID'si kayıtlı değil; Mail'de açılamıyor."; return
            }
            NSWorkspace.shared.open(url)
        }
    }

    /// Kayıtlı aramaları arka planda tazeler; her birinin canlı eşleşme sayısını da yeniden hesaplar.
    func loadSavedSearches() {
        Task {
            guard let list = await background({
                try IndexStore(path: AppPaths.databaseURL).allSavedSearches()
            }) else { return }
            savedSearches = list
            refreshSavedSearchCounts(list)
        }
    }

    /// Kayıtlı aramalar için "akıllı klasör" eşleşme sayılarını arka planda (ağ yok) hesaplar.
    /// `countSavedSearch` yalnız FTS + filtre (operatör/Türkçe tarih çözülmüş) çalıştırır; ucuzdur.
    private func refreshSavedSearchCounts(_ list: [SavedSearch]) {
        let now = Date()
        Task {
            let counts = await background { () -> [String: Int] in
                let store = try IndexStore(path: AppPaths.databaseURL)
                var result: [String: Int] = [:]
                for saved in list {
                    result[saved.id] = (try? store.countSavedSearch(saved.query, now: now)) ?? 0
                }
                return result
            }
            savedSearchCounts = counts ?? [:]
        }
    }

    /// Mevcut arama sorgusunu (ve modunu) verilen isimle kaydeder.
    func saveCurrentSearch(name: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let selectedMode = mode.rawValue
        Task {
            _ = await background {
                try IndexStore(path: AppPaths.databaseURL).saveSearch(name: name, query: q, mode: selectedMode)
            }
            loadSavedSearches()
        }
    }

    /// Kayıtlı bir aramayı yükleyip çalıştırır (Ara sekmesine geçer).
    func runSavedSearch(_ saved: SavedSearch) {
        query = saved.query
        mode = SearchMode(rawValue: saved.mode) ?? .hybrid
        section = .search
        runSearch()
    }

    /// Kayıtlı bir aramayı siler.
    func deleteSavedSearch(_ id: String) {
        Task {
            _ = await background { try IndexStore(path: AppPaths.databaseURL).deleteSavedSearch(id) }
            loadSavedSearches()
        }
    }

    /// "Genel Bakış" verilerini (aylık hacim + ekli sayısı) arka planda tazeler.
    func loadInsights() {
        Task {
            guard let data = await background({ () -> (monthly: [MonthCount], balance: [MonthSentReceived], weekday: [WeekdayCount], attachments: Int) in
                let store = try IndexStore(path: AppPaths.databaseURL)
                let now = Date()   // aylık hacim, gelen/gönderilen ve haftanın günü aynı now/calendar ile bucket'lanır
                return (try store.monthlyCounts(months: 12, now: now),
                        try store.monthlySentReceived(months: 12, now: now),
                        try store.weekdayCounts(now: now),
                        try store.attachmentCount())
            }) else { return }
            monthly = data.monthly
            monthlyBalance = data.balance
            weekdayActivity = data.weekday
            attachmentTotal = data.attachments
        }
    }

    /// En çok yazışılan kişileri arka planda tazeler ("Kişiler" görünümü için).
    /// `peopleQuery` doluysa ada/adrese göre süzer; boşken en-çok-yazışılanları gösterir.
    func loadPeople() {
        let q = peopleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            guard let list = await background({
                try IndexStore(path: AppPaths.databaseURL)
                    .topSenders(matching: q.isEmpty ? nil : q, limit: 60)
            }) else { return }
            people = list
        }
    }

    /// Seçilen kişinin maillerini (en yeni önce) ve mini analitiğini yükler, ilkini okuma paneline getirir.
    func selectPerson(_ address: String) {
        selectedPersonAddress = address
        personDetail = nil
        Task {
            guard let loaded = await background({ () -> (mails: [SearchHit], stats: SenderDetail) in
                let store = try IndexStore(path: AppPaths.databaseURL)
                return (try store.fromSender(address, limit: 200),
                        try store.senderStats(address: address))
            }) else { return }
            personMails = loaded.mails
            personDetail = loaded.stats
            selection = loaded.mails.first?.id
            loadSelected()
        }
    }

    /// Geçmiş sohbetleri arka planda tazeler (geçmiş tarayıcısı için).
    func loadConversations() {
        Task {
            guard let list = await background({
                try IndexStore(path: AppPaths.databaseURL).allConversations()
            }) else { return }
            conversations = list
        }
    }

    /// Ajanın kalıcı hafıza listesini arka planda tazeler (hafıza görüntüleyici için).
    func loadMemories() {
        Task {
            guard let list = await background({
                try IndexStore(path: AppPaths.databaseURL).allMemories()
            }) else { return }
            memories = list
        }
    }

    /// Triyaj listelerini (yanıt gerekiyor / yanıt bekliyor) arka planda tazeler ve görmezden
    /// gelinen (dismissed) öğeleri süzer. Gizlenen öğe sayısı `dismissedHiddenCount`'a yazılır;
    /// re-surface: bir öğenin tarihi gizleme anından sonraysa (konuya yeni yanıt) yeniden görünür.
    func loadTriage() {
        Task {
            guard let lists = await background({ () -> (needs: [SearchHit], waiting: [SearchHit], dismissed: [String: Date]) in
                let store = try IndexStore(path: AppPaths.databaseURL)
                return (try store.needsReply(limit: 50),
                        try store.waitingOnReply(minDays: 3, limit: 50),
                        try store.dismissedDigest())
            }) else { return }
            let needs = filterDismissed(lists.needs, dismissed: lists.dismissed)
            let waiting = filterDismissed(lists.waiting, dismissed: lists.dismissed)
            dismissedHiddenCount = (lists.needs.count - needs.count) + (lists.waiting.count - waiting.count)
            needsReply = needs
            waitingOn = waiting
        }
    }

    /// Bir triyaj öğesini görmezden gelir: şimdiyle dismiss eder, listeden hemen çıkarır (optimistik)
    /// ve kalıcılaştırır. Aynı konuya yeni yanıt gelirse öğe sonraki `loadTriage`'da tekrar görünür.
    func dismissDigestItem(_ hit: SearchHit) {
        let key = digestDismissKey(hit)
        let countBefore = needsReply.count + waitingOn.count
        needsReply.removeAll { digestDismissKey($0) == key }
        waitingOn.removeAll { digestDismissKey($0) == key }
        let removed = countBefore - (needsReply.count + waitingOn.count)
        guard removed > 0 else { return }   // öğe zaten listede değil → işlem yok
        dismissedHiddenCount += removed
        let now = Date()
        Task {
            _ = await background {
                try IndexStore(path: AppPaths.databaseURL).dismissDigest(threadKey: key, at: now)
            }
        }
    }

    /// Yıldızlı (pinned) mail id kümesini arka planda tazeler (sonuç satırı yıldız rozeti + filtre).
    func loadPinned() {
        Task {
            guard let ids = await background({
                try IndexStore(path: AppPaths.databaseURL).pinnedIDs()
            }) else { return }
            pinnedIDs = ids
        }
    }

    /// Bir mailin Trova-yerel yıldızını açar/kapatır (Apple Mail'e YAZMAZ; anahtar `message.id`).
    /// Optimistik: yerel kümeyi hemen günceller, sonra kalıcılaştırır. "Yalnız yıldızlı" süzgeci
    /// açıkken arama listesini tazeler ki yıldızı kaldırılan mail listeden düşsün.
    func togglePin(id: String) {
        let willPin = !pinnedIDs.contains(id)
        if willPin { pinnedIDs.insert(id) } else { pinnedIDs.remove(id) }
        let now = Date()
        Task {
            _ = await background {
                let store = try IndexStore(path: AppPaths.databaseURL)
                if willPin { try store.pin(id: id, at: now) } else { try store.unpin(id: id) }
            }
            if pinnedOnly && section == .search { runSearch() }
        }
    }

    // MARK: - Arama sonuçlarında çoklu seçim + toplu aksiyon

    /// Bir sonuç satırının seçim durumunu açar/kapatır (kümede varsa çıkarır, yoksa ekler).
    func toggleResultSelection(id: String) {
        if selectedResultIDs.contains(id) { selectedResultIDs.remove(id) }
        else { selectedResultIDs.insert(id) }
    }

    /// Çoklu seçimi tümüyle temizler (toplu aksiyon çubuğu gizlenir).
    func clearResultSelection() {
        selectedResultIDs.removeAll()
    }

    /// Gösterilen tüm sonuçları seçer (sırayla; filtreli liste neyse onu kapsar).
    func selectAllResults() {
        selectedResultIDs = Set(displayedResults.map(\.id))
    }

    /// Seçili mailleri TOPLU yıldızlar (tek transaction). Optimistik: yerel kümeyi hemen
    /// günceller, sonra kalıcılaştırır. "Yalnız yıldızlı" süzgeci açıkken listeyi tazeler.
    func pinSelected() {
        let ids = Array(selectedResultIDs)
        guard !ids.isEmpty else { return }
        pinnedIDs.formUnion(ids)
        Task {
            _ = await background {
                try IndexStore(path: AppPaths.databaseURL).pinMany(ids: ids, at: Date())
            }
            if pinnedOnly && section == .search { runSearch() }
        }
    }

    /// Seçili maillerin yıldızını TOPLU kaldırır (tek transaction). Optimistik + kalıcı.
    /// "Yalnız yıldızlı" süzgeci açıkken yıldızı kalkan mailler listeden düşsün diye tazeler.
    func unpinSelected() {
        let ids = Array(selectedResultIDs)
        guard !ids.isEmpty else { return }
        pinnedIDs.subtract(ids)
        Task {
            _ = await background {
                try IndexStore(path: AppPaths.databaseURL).unpinMany(ids: ids)
            }
            if pinnedOnly && section == .search { runSearch() }
        }
    }

    /// Seçili sonuçları Markdown listesine döker (gösterilen sırayı korur).
    func exportSelectedMarkdown() -> String {
        let hits = displayedResults.filter { selectedResultIDs.contains($0.id) }
        return MarkdownExporter.emailList(title: "Seçili sonuçlar", items: listItems(hits))
    }

    /// Seçili sonuçları CSV'ye döker (gösterilen sırayı korur).
    func exportSelectedCSV() -> String {
        let hits = displayedResults.filter { selectedResultIDs.contains($0.id) }
        return CsvExporter.emailList(listItems(hits))
    }

    /// Tüm görmezden gelme kayıtlarını siler ve triyaj listelerini yeniden yükler ("Gizlenenleri geri al").
    func restoreDismissedDigest() {
        Task {
            _ = await background { try IndexStore(path: AppPaths.databaseURL).clearDismissedDigest() }
            dismissedHiddenCount = 0
            loadTriage()
        }
    }

    /// Son gelen mailler için LLM ile Türkçe günlük brifing üretir.
    func runDigest() {
        guard !isDigesting else { return }
        guard let llm = Providers.llm() else { errorMessage = AppError.noLLM.description; return }
        isDigesting = true; errorMessage = nil; digestText = ""
        Task {
            defer { isDigesting = false }
            // Mailleri arka planda getir ve LLM mesajlarını hazırla.
            let result = await background { () -> [ChatMessage]? in
                let store = try IndexStore(path: AppPaths.databaseURL)
                let hits = try store.recentReceived(sinceDays: 2, limit: 40)
                return hits.isEmpty ? nil : DigestBuilder(llm: llm).messages(for: hits)
            }
            guard let inner = result else { return }                 // arka plan hatası (errorMessage set)
            guard let messages = inner else { digestText = "Yeni mail yok."; return }
            do {
                _ = try await llm.completeStreaming(messages: messages) { fragment in
                    await MainActor.run { self.digestText += fragment }
                }
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    /// Ajanın kalıcı hafızasını temizler ve sayacı yeniler.
    func clearMemory() {
        Task {
            _ = await background { try IndexStore(path: AppPaths.databaseURL).clearMemories() }
            refreshStatus()
        }
    }

    func runIndex() {
        guard !busy else { return }
        busy = true; errorMessage = nil; jobProcessed = 0; jobTotal = 0; progress = "Taranıyor…"
        let flag = CancellationFlag(); cancelFlag = flag
        // Opt-in: ek içeriği indeksleme ayarı (varsayılan KAPALI). KAPALIYKEN ek metni çıkarılmaz.
        let indexAttContent = UserDefaults.standard.bool(forKey: SettingsKeys.indexAttachmentContent)
        currentTask = Task {
            defer { busy = false; currentTask = nil; cancelFlag = nil; refreshStatus() }
            let result = await background { () -> IndexResult in
                guard let root = MailStore.locate() else { throw AppError.noMailStore }
                let store = try IndexStore(path: AppPaths.databaseURL)
                return try Indexer.run(store: store, root: root,
                                       indexAttachmentContent: indexAttContent, cancel: flag) { processed, total in
                    Task { @MainActor in
                        self.jobProcessed = processed; self.jobTotal = total
                        self.progress = "İndeksleniyor \(processed)/\(total)"
                    }
                }
            }
            if let result {
                progress = result.processed > 0
                    ? "\(result.inserted) yeni · \(result.duplicates) kopya · \(result.removed) silinmiş kaldırıldı · \(result.skipped) atlandı · \(result.failed) hata"
                    : "Mail bulunamadı"
            }
        }
    }

    /// Yinelenen mail satırlarını (aynı Message-ID — Apple Mail'in kopya `.emlx`'leri) tek seferde
    /// temizler: kanonik satırı tutar, kopyaları + yetim vektör/ek/ek-içeriği kayıtlarını siler.
    /// Otomatik DEĞİL — kullanıcı Bakım'dan tetikler (güvenli; `.emlx` kaynak olduğundan geri-üretilebilir).
    func dedupeMessages() {
        guard !busy else { return }
        busy = true; errorMessage = nil; jobProcessed = 0; jobTotal = 0
        progress = "Yinelenenler taranıyor…"
        currentTask = Task {
            defer { busy = false; currentTask = nil; cancelFlag = nil; refreshStatus() }
            let removed = await background { () -> Int in
                let store = try IndexStore(path: AppPaths.databaseURL)
                return try store.dedupeExisting { processed, total in
                    Task { @MainActor in
                        self.jobProcessed = processed; self.jobTotal = total
                        self.progress = "Yinelenenler temizleniyor \(processed)/\(total)"
                    }
                }
            }
            if let removed {
                progress = removed == 0 ? "Yinelenen mail bulunamadı" : "\(removed) kopya kaldırıldı"
            }
        }
    }

    /// Ek içeriği backfill geçişini başlatır (opt-in toggle AÇIK olmalı): eki olan TÜM mevcut
    /// mailleri gezip eklerden OCR'SIZ ucuz metni çıkarır ve aranabilir kılar. İlerleme + iptal.
    /// Artımlı indeksleme değişmemiş mailleri atladığından bu ayrı geçiş gereklidir.
    func runAttachmentContentPass() {
        guard !busy else { return }
        busy = true; errorMessage = nil; jobProcessed = 0; jobTotal = 0; progress = "Ek içeriği taranıyor…"
        let flag = CancellationFlag(); cancelFlag = flag
        currentTask = Task {
            defer { busy = false; currentTask = nil; cancelFlag = nil; refreshStatus() }
            let count = await background { () -> Int in
                let store = try IndexStore(path: AppPaths.databaseURL)
                return try Indexer.indexAttachmentContentPass(store: store, cancel: flag) { processed, total in
                    Task { @MainActor in
                        self.jobProcessed = processed; self.jobTotal = total
                        self.progress = "Ek içeriği indeksleniyor \(processed)/\(total)"
                    }
                }
            }
            if let count {
                progress = count == 0 ? "İçerik çıkarılabilen ek bulunamadı"
                                      : "Bitti · \(count) mailin eki indekslendi"
            }
        }
    }

    /// Ek içeriği FTS tablosunu boşaltır (toggle kapatıldıktan sonra temizlemek için).
    func clearAttachmentContent() {
        guard !busy else { return }
        Task {
            _ = await background { try IndexStore(path: AppPaths.databaseURL).clearAttachmentContent() }
            refreshStatus()
        }
    }

    func runEmbed() {
        guard !busy else { return }
        busy = true; errorMessage = nil; jobProcessed = 0; jobTotal = 0; progress = "Hazırlanıyor…"
        let flag = CancellationFlag(); cancelFlag = flag
        currentTask = Task {
            defer { busy = false; currentTask = nil; cancelFlag = nil; refreshStatus() }
            guard let embedder = Providers.embedder() else {
                errorMessage = AppError.noEmbedder.description; return
            }
            let count = await background { () -> Int in
                let store = try IndexStore(path: AppPaths.databaseURL)
                return try EmbeddingRunner.run(store: store, embedder: embedder, cancel: flag) { processed, total in
                    Task { @MainActor in
                        self.jobProcessed = processed; self.jobTotal = total
                        self.progress = "Gömülüyor \(processed)/\(total)"
                    }
                }
            }
            if let count { progress = count == 0 ? "Tüm mailler zaten gömülü" : "Bitti · \(count) işlendi" }
        }
    }

    /// Hızlı tarih çipine dokununca tarih aralığını set edip aramayı (mevcut sorguyla) çalıştırır.
    /// Toggle: aynı çipe tekrar dokununca filtre kalkar. Aktifken `runSearch` tarih filtresini bu
    /// aralıkla geçersiz kılar (yazılı tarih ve kenar çubuğu picker'ı dahil). Sorgu boşken bile
    /// (yalnız çip) sonuçları gözatma kipinde listeler.
    func toggleQuickDate(_ kind: QuickDateRange) {
        activeQuickDate = (activeQuickDate == kind) ? nil : kind
        runSearch()
    }

    func runSearch() {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Yeni arama: eski gönderen daraltması yeni sonuçlara yapışmasın diye sıfırla.
        activeSenderFilter = nil
        // Yeni arama: önceki çoklu seçim yeni sonuçlarla tutarsız kalmasın diye temizle.
        selectedResultIDs.removeAll()
        // Arama metni yoksa bile aktif bir filtre çipi (okunmadı/bayraklı/yıldızlı) varsa browse'a izin ver.
        guard !raw.isEmpty || unreadOnly || flaggedOnly || pinnedOnly || activeQuickDate != nil else {
            results = []; selection = nil; highlightTerms = []; return
        }
        // Önce Gmail-tarzı operatörleri (from:/has:attachment), sonra Türkçe tarih ifadesini ayrıştır.
        let ops = SearchOperatorParser.parse(raw)
        let parsed = TurkishDateParser.parse(ops.cleaned, now: Date())
        // Hızlı tarih çipi aktifse yazılı tarih ve picker'ı geçersiz kılar; çip etiketi de onu gösterir.
        let quick = activeQuickDate.map { QuickDate.range($0, now: Date(), calendar: .current) }
        detectedDateLabel = activeQuickDate?.label ?? parsed.hint?.label
        searchFromLabel = ops.fromContains
        searchHasAttachment = ops.hasAttachment
        searchAttachmentKind = ops.attachmentKind
        let q = parsed.hint != nil ? parsed.cleaned : ops.cleaned
        // Geçerli bir arama metni varsa (yalnız operatör/tarih değil — browse fallback hariç)
        // ham kullanıcı sorgusunu otomatik geçmişe ekle.
        if !q.isEmpty { recordRecent(raw) }
        let selectedMode = mode
        // Algılanan tarih aralığı, kenar çubuğundaki tarih picker'ını geçersiz kılar.
        let since = quick?.since ?? parsed.hint?.since ?? dateRange.since
        let until = quick?.until ?? parsed.hint?.until
        let filter = SearchFilter(
            accountID: filterAccount.isEmpty ? nil : filterAccount, since: since, until: until,
            fromContains: ops.fromContains, hasAttachment: ops.hasAttachment,
            attachmentKind: ops.attachmentKind,
            unreadOnly: unreadOnly, flaggedOnly: flaggedOnly, pinnedOnly: pinnedOnly)
        // PRF (sorgu genişletme) ayarı: açıksa ilk sonuçlardan terim çıkarıp sorguya eklenir.
        let prf = UserDefaults.standard.bool(forKey: SettingsKeys.queryExpansion)
        // Opt-in: ek içeriği aramaya katılsın mı (varsayılan KAPALI → hiç sorgu çalışmaz).
        let includeAttContent = UserDefaults.standard.bool(forKey: SettingsKeys.indexAttachmentContent)
        isSearching = true; errorMessage = nil; expansionChips = []
        // Vurgulanacak terimler: önce temizlenmiş sorgu tokenları (genişletme sonuçla birlikte gelir).
        highlightTerms = AppModel.highlightTerms(query: q, expansion: [])
        Task {
            let outcome = await background { () -> (hits: [SearchHit], terms: [String]) in
                let store = try IndexStore(path: AppPaths.databaseURL)
                // Arama metni kalmadıysa (yalnız operatör/tarih) filtreye uyanları listele.
                if q.isEmpty {
                    return (try store.browse(filter, limit: 50), [])
                }
                // PRF: ilk FTS sonuçlarının metinlerinden genişletme terimleri türet.
                var effectiveQuery = q
                var terms: [String] = []
                if prf {
                    let initial = try store.search(query: q, filter: filter, limit: 8)
                    let docs = initial.map { ($0.subject ?? "") + " " + $0.snippet }
                    terms = QueryExpander.expansionTerms(query: q, docs: docs, maxTerms: 4)
                    if !terms.isEmpty { effectiveQuery = q + " " + terms.joined(separator: " ") }
                }
                let embedder = selectedMode == .fts ? nil : Providers.embedder()
                // Reranking yalnızca anlamsal/hibrit modlarda anlamlıdır.
                let reranker = selectedMode == .fts ? nil : Providers.reranker()
                let hits = try Searcher(store: store, embedder: embedder, reranker: reranker,
                                        maxPerThread: Retrieval.maxPerThread(),
                                        includeAttachmentContent: includeAttContent)
                    .search(effectiveQuery, mode: selectedMode, filter: filter, limit: 50)
                return (hits, terms)
            }
            isSearching = false
            results = outcome?.hits ?? []
            expansionChips = outcome?.terms ?? []
            // Genişletme (PRF) terimlerini de vurgu listesine kat (temizlenmiş sorgu + genişletme).
            highlightTerms = AppModel.highlightTerms(query: q, expansion: outcome?.terms ?? [])
            selection = displayedResults.first?.id   // gösterilen listenin ilk satırını seç
            loadSelected()
        }
    }

    /// Snippet vurgusu için terim listesini üretir: temizlenmiş sorgu tokenları + genişletme
    /// terimleri. Operatör/tarih kelimeleri çağrıdan önce `q`'dan zaten elenmiştir; burada
    /// yalnız <2 harfli token'lar atılır, küçük harfe (Türkçe) indirilir ve tekilleştirilir.
    static func highlightTerms(query q: String, expansion: [String]) -> [String] {
        let locale = Locale(identifier: "tr_TR")
        func tokenize(_ s: String) -> [String] {
            s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map { $0.lowercased(with: locale) }
        }
        var seen = Set<String>()
        var result: [String] = []
        for term in tokenize(q) + expansion.flatMap(tokenize) where term.count >= 2 {
            if seen.insert(term).inserted { result.append(term) }
        }
        return result
    }

    /// Ham kullanıcı sorgusunu otomatik arama geçmişine ekler ve kalıcılaştırır (en yeni başta).
    private func recordRecent(_ raw: String) {
        var recents = RecentSearches(items: recentSearches)
        recents.add(raw)
        recentSearches = recents.items
        RecentSearchesStore.save(recentSearches)
    }

    /// Geçmişten bir sorguyu yeniden çalıştırır.
    func runRecent(_ q: String) {
        query = q
        runSearch()
    }

    /// Otomatik arama geçmişini temizler ve kalıcılaştırır.
    func clearRecents() {
        recentSearches = []
        RecentSearchesStore.save([])
    }

    func loadSelected() {
        guard let id = selection else {
            selectedBody = nil; selectedHTML = nil; selectedThread = []; selectedMessageID = nil; return
        }
        let threadKey = selectedHit?.threadKey
        Task {
            let loaded = await background { () -> (body: String, html: String?, thread: [SearchHit], messageID: String?) in
                let store = try IndexStore(path: AppPaths.databaseURL)
                let body = (try store.body(forID: id)) ?? ""
                var html: String?
                if let path = try store.filePath(forID: id),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let raw = EMLXParser.extractHTMLBody(data: data) {
                    html = EMLXParser.sanitizeEmailHTML(raw)
                }
                let thread = try threadKey.map { try store.thread(forKey: $0) } ?? []
                let messageID = try store.messageID(forID: id)
                return (body, html, thread, messageID)
            }
            if let loaded {
                selectedBody = loaded.body; selectedHTML = loaded.html
                selectedThread = loaded.thread; selectedMessageID = loaded.messageID
            }
        }
    }

    /// Seçili konunun (thread) tüm mesajlarını LLM ile Türkçe özetler.
    func summarizeThread() {
        guard !isSummarizing, selectedThread.count > 1 else { return }
        guard let llm = Providers.llm() else { errorMessage = AppError.noLLM.description; return }
        let thread = selectedThread
        let key = selectedHit?.threadKey
        isSummarizing = true; errorMessage = nil
        threadSummary = ""; summaryThreadKey = key
        Task {
            defer { isSummarizing = false }
            // Thread gövdelerini arka planda yükle ve LLM mesajlarını hazırla.
            let messages = await background { () -> [ChatMessage] in
                let store = try IndexStore(path: AppPaths.databaseURL)
                let entries = try thread.map { hit in
                    ThreadEntry(from: hit.fromName ?? hit.fromAddress, date: hit.date,
                                body: (try store.body(forID: hit.id)) ?? hit.snippet)
                }
                return ThreadSummarizer(llm: llm).messages(for: entries)
            }
            guard let messages else { threadSummary = nil; return }
            do {
                _ = try await llm.completeStreaming(messages: messages) { fragment in
                    await MainActor.run { self.threadSummary = (self.threadSummary ?? "") + fragment }
                }
            } catch {
                errorMessage = "\(error)"; threadSummary = nil
            }
        }
    }

    /// Seçili maile LLM ile kısa, nazik bir Türkçe yanıt taslağı üretir (canlı akış).
    /// Ajan döngüsüne dokunmaz; tek-atışlık `completeStreaming` kullanır → sıfır regresyon.
    func generateReplyDraft() {
        guard !isDraftingReply, let hit = selectedHit else { return }
        guard let address = hit.fromAddress, !address.isEmpty else {
            draftError = "Bu mailin gönderen adresi yok; yanıt taslağı üretilemiyor."
            return
        }
        guard let llm = Providers.llm() else { errorMessage = AppError.noLLM.description; return }
        let id = hit.id
        let fromName = hit.fromName ?? hit.fromAddress
        let subject = hit.subject ?? ""
        let snippet = hit.snippet
        isDraftingReply = true; draftError = nil
        replyDraft = ""; replyDraftHit = id
        Task {
            defer { isDraftingReply = false }
            // Mailin gövdesini arka planda yükle (özetleyiciyle aynı kaynak) ve mesajları hazırla.
            let messages = await background { () -> [ChatMessage] in
                let store = try IndexStore(path: AppPaths.databaseURL)
                let body = (try store.body(forID: id)) ?? snippet
                return ReplyDraft.messages(from: fromName, subject: subject, body: body)
            }
            guard let messages else { replyDraft = nil; return }
            do {
                _ = try await llm.completeStreaming(messages: messages) { fragment in
                    await MainActor.run { self.replyDraft = (self.replyDraft ?? "") + fragment }
                }
            } catch {
                draftError = "\(error)"; replyDraft = nil
            }
        }
    }

    /// Üretilen taslağı her durumda panoya kopyalar; sonra Mail.app yanıt penceresini açar.
    /// mailto gövde uzunluk sınırını aşmamak için: taslak KISAYSA gövdeye konur, UZUNSA gövde
    /// boş bırakılır — taslak zaten panoda olduğundan kullanıcı doğrudan yapıştırabilir.
    func composeReplyWithDraft() {
        guard let hit = selectedHit, let address = hit.fromAddress, !address.isEmpty,
              let draft = replyDraft, !draft.isEmpty else {
            draftError = "Yanıt penceresi açılamadı."
            return
        }
        // Taslağı her zaman panoya kopyala (uzun gövdede yapıştırmak için).
        Exporter.copy(draft)
        let subject = MailtoLink.replySubject(hit.subject ?? "")
        let body: String? = draft.count <= 1500 ? draft : nil
        guard let url = MailtoLink.url(to: [address], subject: subject, body: body) else {
            draftError = "Yanıt penceresi açılamadı."
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Yanıt taslağı kartını kapatır (taslağı ve hata durumunu temizler).
    func clearReplyDraft() {
        replyDraft = nil; replyDraftHit = nil; draftError = nil
    }

    /// Seçili mailden verilen adlı eki çıkarıp geçici bir dosyaya yazar ve sistemde açar.
    func openAttachment(named name: String) {
        guard let id = selection else { return }
        openAttachment(named: name, messageID: id)
    }

    /// Belirli bir mailden (id) verilen adlı eki çıkarıp geçici bir dosyaya yazar ve sistemde açar.
    /// Seçili maile bağlı değildir; sonuç satırındaki eşleşen-ek rozetlerinden doğrudan açmak için.
    func openAttachment(named name: String, messageID id: String) {
        Task {
            let result = await background { () -> URL? in
                let store = try IndexStore(path: AppPaths.databaseURL)
                guard let path = try store.filePath(forID: id),
                      let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
                guard let att = EMLXParser.extractAttachments(data: data)
                    .first(where: { $0.filename == name }) else { return nil }
                // Dosya adını güvenli kıl (yol bileşeni kaçışını önle).
                let safe = (att.filename as NSString).lastPathComponent
                let fileName = safe.isEmpty ? "ek" : safe
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("trova-ekler", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let fileURL = dir.appendingPathComponent(fileName)
                try att.data.write(to: fileURL)
                return fileURL
            }
            guard let url = result.flatMap({ $0 }) else {
                errorMessage = "Ek açılamadı: \(name)"; return
            }
            NSWorkspace.shared.open(url)
        }
    }

    /// Seçili maili native Apple Mail.app'te açar (message:// derin-linki). Message-ID yoksa hata gösterir.
    func openInMail() { openInMail(messageID: selectedMessageID) }

    /// Verilen Message-ID'li maili native Apple Mail.app'te açar (örn. Bugün triyaj satırından).
    /// Message-ID yoksa hata gösterir. Yalnız açar — hiçbir şey göndermez/yazmaz.
    func openInMail(messageID: String?) {
        guard let url = MailLink.appleMailURL(messageID: messageID) else {
            errorMessage = "Bu mailin Message-ID'si kayıtlı değil; Mail'de açılamıyor."
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Seçili maile yanıt için Mail.app oluşturma penceresi açar.
    func composeReply() {
        guard let hit = selectedHit else {
            errorMessage = "Bu mailin gönderen adresi yok; yanıt penceresi açılamıyor."
            return
        }
        composeReply(hit)
    }

    /// Verilen mail öğesine yanıt için Mail.app oluşturma penceresi açar: gönderene; konu "Yan: …";
    /// gövdede sade bir alıntı başlığı. Yalnız pencere açar — hiçbir şey göndermez/yazmaz.
    func composeReply(_ hit: SearchHit) {
        guard let address = hit.fromAddress, !address.isEmpty else {
            errorMessage = "Bu mailin gönderen adresi yok; yanıt penceresi açılamıyor."
            return
        }
        let subject = MailtoLink.replySubject(hit.subject ?? "")
        // Sade alıntı başlığı: "<tarih> tarihinde <gönderen> yazdı:" (boş satırlarla ayrılmış).
        var body: String?
        if let date = hit.date {
            let stamp = date.formatted(date: .abbreviated, time: .shortened)
            body = "\n\n\(stamp) tarihinde \(hit.fromName ?? address) yazdı:\n"
        }
        guard let url = MailtoLink.url(to: [address], subject: subject, body: body) else {
            errorMessage = "Yanıt penceresi açılamadı."
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Verilen adrese boş bir "Yeni e-posta" oluşturma penceresi açar (yalnız alıcı dolu).
    /// Yalnız pencere açar — hiçbir şey göndermez/yazmaz.
    func composeNew(to address: String) {
        guard let url = MailtoLink.url(to: [address]) else {
            errorMessage = "Geçersiz adres; yeni e-posta açılamıyor."
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// "Benzer mailler": verilen mailin embedding vektörüne en yakın mailleri arka planda bulur
    /// ve sheet'i açar. Vektörler zaten hazır olduğundan Providers (LLM/embedder) gerekmez.
    func loadSimilar(messageID id: String) {
        similarSourceSubject = selectedHit?.subject
        similarMails = []
        isLoadingSimilar = true
        showSimilarSheet = true
        Task {
            let hits = await background { () -> [SearchHit] in
                let store = try IndexStore(path: AppPaths.databaseURL)
                return try store.similar(toMessageID: id, limit: 20)
            }
            isLoadingSimilar = false
            similarMails = hits ?? []
        }
    }

    /// Benzer mailler listesinden bir maile geçer: sheet'i kapatır, seçimi değiştirir ve detayını yükler.
    func openSimilar(_ hit: SearchHit) {
        showSimilarSheet = false
        selection = hit.id
        loadSelected()
    }

    func runAsk() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        guard let llm = Providers.llm() else { errorMessage = AppError.noLLM.description; return }

        // Önceki turlar bağlam olarak ajana verilir (sohbet hafızası).
        let history = conversation.map { ChatTurn(question: $0.question, answer: $0.answer) }
        // Yanıt doğrulama (self-critique) ayarı: açıksa ek bir LLM çağrısı yapılır.
        let verify = UserDefaults.standard.bool(forKey: SettingsKeys.verify)
        question = ""
        // Yeni bir sohbet başlıyorsa kalıcı bir kimlik ata (sonraki turlar aynı kayda yazılır).
        if currentConversationId == nil { currentConversationId = UUID().uuidString }
        conversation.append(Exchange(question: q))
        let index = conversation.count - 1

        // Canlı akış ayarı: anahtar hiç yazılmamışsa varsayılan AÇIK.
        let defaults = UserDefaults.standard
        let streaming = defaults.object(forKey: SettingsKeys.streamAnswers) == nil
            ? true : defaults.bool(forKey: SettingsKeys.streamAnswers)

        isAsking = true; errorMessage = nil
        let flag = CancellationFlag(); cancelFlag = flag
        currentTask = Task {
            defer {
                isAsking = false; currentTask = nil; cancelFlag = nil
                if index < conversation.count { conversation[index].running = false }
            }
            // Ajan adımlarını (search/read/…) canlı olarak ilgili tura işler (iki yol da paylaşır).
            let onStep: @Sendable (AgentStep) -> Void = { step in
                Task { @MainActor in
                    if index < self.conversation.count { self.conversation[index].steps.append(step) }
                }
            }
            let run: AgentRun?
            if streaming {
                // Ajanı arka planda kur (bloklayıcı store açılışı), sonra yanıtı token token akıt.
                guard let agent = await background({ () -> ToolAgent in
                    let store = try IndexStore(path: AppPaths.databaseURL)
                    return ToolAgent(store: store, embedder: Providers.embedder(),
                                     llm: llm, reranker: Providers.reranker(),
                                     maxPerThread: Retrieval.maxPerThread())
                }) else { return }
                do {
                    run = try await agent.runStreaming(
                        q, history: history, cancel: flag, verify: verify, progress: onStep,
                        onAnswerDelta: { delta in
                            await MainActor.run {
                                if index < self.conversation.count { self.conversation[index].answer += delta }
                            }
                        })
                } catch {
                    errorMessage = "\(error)"; return
                }
            } else {
                // Eski senkron yol (değişmedi): yanıt tamamlanınca tek seferde belirir.
                run = await background { () -> AgentRun in
                    let store = try IndexStore(path: AppPaths.databaseURL)
                    let agent = ToolAgent(store: store, embedder: Providers.embedder(),
                                          llm: llm, reranker: Providers.reranker(),
                                          maxPerThread: Retrieval.maxPerThread())
                    return try agent.run(q, history: history, cancel: flag, verify: verify, progress: onStep)
                }
            }
            if let run, index < conversation.count {
                // Akışta birikenin üzerine nihai (son tur) yanıtı kesinleştir; kaynak/doğrulamayı işle.
                conversation[index].answer = run.answer
                conversation[index].cited = run.cited
                conversation[index].verification = run.verification
                persistConversation()
            }
        }
    }

    /// Açık sohbeti (yanıtı dolu turlarıyla) kalıcı geçmişe kaydeder ve listeyi tazeler.
    private func persistConversation() {
        guard let cid = currentConversationId else { return }
        let turns = conversation
            .filter { !$0.answer.isEmpty }
            .map { ChatTurn(question: $0.question, answer: $0.answer) }
        guard !turns.isEmpty else { return }
        let title = String(turns[0].question.prefix(60))
        Task {
            _ = await background {
                try IndexStore(path: AppPaths.databaseURL)
                    .saveConversation(id: cid, title: title, turns: turns)
            }
            loadConversations()
        }
    }

    func newConversation() {
        guard !isAsking else { return }
        conversation = []
        currentConversationId = nil
    }

    /// Geçmiş bir sohbeti yeniden açar: turlarını yükleyip sohbeti yeniden kurar ve Sor sekmesine geçer.
    func loadConversation(_ id: String) {
        guard !isAsking else { return }
        Task {
            guard let turns = await background({
                try IndexStore(path: AppPaths.databaseURL).conversationTurns(id)
            }) else { return }
            conversation = turns.map {
                Exchange(question: $0.question, answer: $0.answer,
                         steps: [], cited: [], verification: nil, running: false)
            }
            currentConversationId = id
            section = .ask
        }
    }

    /// Geçmiş bir sohbeti siler; açık olan sohbetse ekranı da temizler.
    func deleteConversation(_ id: String) {
        Task {
            _ = await background {
                try IndexStore(path: AppPaths.databaseURL).deleteConversation(id)
            }
            if currentConversationId == id { newConversation() }
            loadConversations()
        }
    }

    /// Tek bir hafıza kaydını siler; listeyi ve sayacı tazeler.
    func deleteMemory(_ id: String) {
        Task {
            _ = await background {
                try IndexStore(path: AppPaths.databaseURL).deleteMemory(id)
            }
            loadMemories()
            guard let count = await background({
                try IndexStore(path: AppPaths.databaseURL).memoryCount()
            }) else { return }
            memoryCount = count
        }
    }

    /// Bloklayıcı işi arka planda çalıştırır; hata olursa `errorMessage`'a yazıp nil döner.
    private func background<T: Sendable>(_ work: @Sendable @escaping () throws -> T) async -> T? {
        do {
            return try await Task.detached(priority: .userInitiated, operation: work).value
        } catch {
            errorMessage = "\(error)"
            return nil
        }
    }
}
