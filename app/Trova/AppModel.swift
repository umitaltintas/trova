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

    enum Section: Equatable { case ask, search, digest, people, insights }
    var section: Section = .ask

    // Durum
    var hasAccess = false
    var mailRoot: String?
    var totalCount = 0
    var vectorCount = 0
    var memoryCount = 0
    var accounts: [AccountStat] = []

    // Kişiler (en çok yazışılanlar)
    var people: [SenderStat] = []
    var selectedPersonAddress: String?
    var personMails: [SearchHit] = []
    var personDetail: SenderDetail?      // seçili kişinin mini analitiği

    // Genel Bakış (insights)
    var monthly: [MonthCount] = []
    var attachmentTotal = 0

    // Sağlık / kurulum (HealthCheck girdileri)
    var llmConfigured = false
    var embedderConfigured = false
    var usesLocalEmbedder = false
    var statusLoaded = false        // ilk durum yüklemesi bitti mi (kurulum kapısı yanıp sönmesin)

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
    var results: [SearchHit] = []
    var selection: SearchHit.ID?
    var selectedBody: String?
    var selectedHTML: String?
    var selectedThread: [SearchHit] = []
    var threadSummary: String?           // "Konuyu özetle" çıktısı (markdown)
    var summaryThreadKey: String?        // özetin ait olduğu thread (başka thread'e geçince gizlenir)
    var isSummarizing = false
    var selectedMessageID: String?       // seçili mailin RFC822 Message-ID'si ("Mail'de Aç" için)
    var isSearching = false
    var detectedDateLabel: String?       // sorgudan algılanan Türkçe tarih ifadesi etiketi (örn. "son 7 gün")
    var searchFromLabel: String?         // from:/gönderen: operatörü etiketi
    var searchHasAttachment = false      // has:attachment operatörü etkin mi
    var expansionChips: [String] = []    // PRF ile sorguya eklenen terimler (gösterim)

    // Filtre
    var filterAccount = ""          // "" → tüm hesaplar (accountID)
    var dateRange: DateRange = .all

    // Kayıtlı aramalar
    var savedSearches: [SavedSearch] = []

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
    var needsReply: [SearchHit] = []     // yanıt gerekiyor: karşı taraf en son yazdı
    var waitingOn: [SearchHit] = []      // yanıt bekliyor: sen en son yazdın, yanıt yok
    var digestText = ""
    var isDigesting = false

    // Uzun işler
    var busy = false
    var progress = ""
    var errorMessage: String?
    var jobProcessed = 0
    var jobTotal = 0
    private var currentTask: Task<Void, Never>?
    private var cancelFlag: CancellationFlag?
    private var watcher: MailWatcher?

    init() {
        // Otomatik arama geçmişini kalıcı depodan yükle.
        recentSearches = RecentSearchesStore.load()
    }

    var selectedHit: SearchHit? {
        results.first { $0.id == selection }
            ?? selectedThread.first { $0.id == selection }
            ?? needsReply.first { $0.id == selection }
            ?? waitingOn.first { $0.id == selection }
            ?? personMails.first { $0.id == selection }
            ?? conversation.flatMap(\.cited).first { $0.id == selection }
    }

    /// Açık bölüme göre klavyeyle gezinilebilir aktif mail id listesi (görünen sırayla).
    var navigableIDs: [String] {
        switch section {
        case .search:   results.map(\.id)
        case .people:   personMails.map(\.id)
        case .digest:   (needsReply + waitingOn).map(\.id)
        case .ask:      conversation.flatMap(\.cited).map(\.id)
        case .insights: []
        }
    }

    /// Aktif listede `delta` yönündeki komşu maile geçer ve okuma panelinde açar (uçlarda kenetlenir).
    func selectAdjacent(_ delta: Int) {
        guard let next = Navigation.adjacent(ids: navigableIDs, current: selection, delta: delta) else { return }
        selection = next
        loadSelected()
    }

    /// Bir tarihin bugüne göre yaşını tam gün olarak verir (UI yaş çipleri için).
    static func ageDays(_ date: Date?) -> Int { TriageItem.ageDays(of: date) }

    /// Yaşı kısa bir etikete çevirir ("bugün" / "3g") — yaş çipi ve dışa aktarım aynı biçimi paylaşır.
    static func ageLabel(_ date: Date?) -> String {
        let days = ageDays(date)
        return days <= 0 ? "bugün" : "\(days)g"
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
    }

    private func onMailChanged() {
        guard !busy else { return }
        progress = "Yeni mail algılandı, güncelleniyor…"
        runIndex()
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

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshStatus() {
        Task {
            guard let stats = await background({ () -> (Int, Int, Int, [AccountStat]) in
                let store = try IndexStore(path: AppPaths.databaseURL)
                let accounts = try store.accountCounts().map { AccountStat(account: $0.account, count: $0.count) }
                return (try store.count(), try store.vectorCount(), try store.memoryCount(), accounts)
            }) else { return }
            totalCount = stats.0; vectorCount = stats.1; memoryCount = stats.2; accounts = stats.3
            statusLoaded = true
        }
        refreshProviders()
        loadTriage()   // indeksleme/durum yenilemesi sonrası triyaj listeleri de tazelensin
        loadConversations()
        loadMemories()
        loadPeople()
        loadSavedSearches()
        loadInsights()
    }

    /// Kayıtlı aramaları arka planda tazeler.
    func loadSavedSearches() {
        Task {
            guard let list = await background({
                try IndexStore(path: AppPaths.databaseURL).allSavedSearches()
            }) else { return }
            savedSearches = list
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
            guard let data = await background({ () -> (monthly: [MonthCount], attachments: Int) in
                let store = try IndexStore(path: AppPaths.databaseURL)
                return (try store.monthlyCounts(months: 12, now: Date()), try store.attachmentCount())
            }) else { return }
            monthly = data.monthly
            attachmentTotal = data.attachments
        }
    }

    /// En çok yazışılan kişileri arka planda tazeler ("Kişiler" görünümü için).
    func loadPeople() {
        Task {
            guard let list = await background({
                try IndexStore(path: AppPaths.databaseURL).topSenders(limit: 60)
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

    /// Triyaj listelerini (yanıt gerekiyor / yanıt bekliyor) arka planda tazeler.
    func loadTriage() {
        Task {
            guard let lists = await background({ () -> (needs: [SearchHit], waiting: [SearchHit]) in
                let store = try IndexStore(path: AppPaths.databaseURL)
                return (try store.needsReply(limit: 50),
                        try store.waitingOnReply(minDays: 3, limit: 50))
            }) else { return }
            needsReply = lists.needs
            waitingOn = lists.waiting
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
        currentTask = Task {
            defer { busy = false; currentTask = nil; cancelFlag = nil; refreshStatus() }
            let result = await background { () -> IndexResult in
                guard let root = MailStore.locate() else { throw AppError.noMailStore }
                let store = try IndexStore(path: AppPaths.databaseURL)
                return try Indexer.run(store: store, root: root, cancel: flag) { processed, total in
                    Task { @MainActor in
                        self.jobProcessed = processed; self.jobTotal = total
                        self.progress = "İndeksleniyor \(processed)/\(total)"
                    }
                }
            }
            if let result {
                progress = result.processed > 0
                    ? "\(result.indexed) yeni · \(result.skipped) atlandı · \(result.failed) hata"
                    : "Mail bulunamadı"
            }
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

    func runSearch() {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        // Önce Gmail-tarzı operatörleri (from:/has:attachment), sonra Türkçe tarih ifadesini ayrıştır.
        let ops = SearchOperatorParser.parse(raw)
        let parsed = TurkishDateParser.parse(ops.cleaned, now: Date())
        detectedDateLabel = parsed.hint?.label
        searchFromLabel = ops.fromContains
        searchHasAttachment = ops.hasAttachment
        let q = parsed.hint != nil ? parsed.cleaned : ops.cleaned
        // Geçerli bir arama metni varsa (yalnız operatör/tarih değil — browse fallback hariç)
        // ham kullanıcı sorgusunu otomatik geçmişe ekle.
        if !q.isEmpty { recordRecent(raw) }
        let selectedMode = mode
        // Algılanan tarih aralığı, kenar çubuğundaki tarih picker'ını geçersiz kılar.
        let since = parsed.hint?.since ?? dateRange.since
        let until = parsed.hint?.until
        let filter = SearchFilter(
            accountID: filterAccount.isEmpty ? nil : filterAccount, since: since, until: until,
            fromContains: ops.fromContains, hasAttachment: ops.hasAttachment)
        // PRF (sorgu genişletme) ayarı: açıksa ilk sonuçlardan terim çıkarıp sorguya eklenir.
        let prf = UserDefaults.standard.bool(forKey: SettingsKeys.queryExpansion)
        isSearching = true; errorMessage = nil; expansionChips = []
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
                                        maxPerThread: Retrieval.maxPerThread())
                    .search(effectiveQuery, mode: selectedMode, filter: filter, limit: 50)
                return (hits, terms)
            }
            isSearching = false
            results = outcome?.hits ?? []
            expansionChips = outcome?.terms ?? []
            selection = results.first?.id
            loadSelected()
        }
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

    /// Seçili mailden verilen adlı eki çıkarıp geçici bir dosyaya yazar ve sistemde açar.
    func openAttachment(named name: String) {
        guard let id = selection else { return }
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
    func openInMail() {
        guard let url = MailLink.appleMailURL(messageID: selectedMessageID) else {
            errorMessage = "Bu mailin Message-ID'si kayıtlı değil; Mail'de açılamıyor."
            return
        }
        NSWorkspace.shared.open(url)
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

        isAsking = true; errorMessage = nil
        let flag = CancellationFlag(); cancelFlag = flag
        currentTask = Task {
            defer {
                isAsking = false; currentTask = nil; cancelFlag = nil
                if index < conversation.count { conversation[index].running = false }
            }
            let run = await background { () -> AgentRun in
                let store = try IndexStore(path: AppPaths.databaseURL)
                let agent = ToolAgent(store: store, embedder: Providers.embedder(),
                                      llm: llm, reranker: Providers.reranker(),
                                      maxPerThread: Retrieval.maxPerThread())
                return try agent.run(q, history: history, cancel: flag, verify: verify) { step in
                    Task { @MainActor in
                        if index < self.conversation.count { self.conversation[index].steps.append(step) }
                    }
                }
            }
            if let run, index < conversation.count {
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
