import Foundation

public struct AgentStep: Sendable {
    public enum Kind: String, Sendable { case search, read, thread, answer, note }
    public let kind: Kind
    public let detail: String
    public init(kind: Kind, detail: String) { self.kind = kind; self.detail = detail }
}

/// Yanıt doğrulama (self-critique) sonucu: yanıttaki iddialar kaynak maillerce
/// ne ölçüde destekleniyor + desteklenmeyen iddialar için kısa notlar.
public struct Verification: Sendable {
    public enum Verdict: String, Sendable { case grounded, partial, unsupported, unknown }
    public let verdict: Verdict
    public let issues: [String]
    public init(verdict: Verdict, issues: [String]) {
        self.verdict = verdict
        self.issues = issues
    }
}

public struct AgentRun: Sendable {
    public let answer: String
    public let steps: [AgentStep]
    public let cited: [SearchHit]   // ajanın okuduğu/kullandığı mailler (kaynak)
    public let verification: Verification?   // opsiyonel doğrulama (ayar açıksa)
}

/// Sohbet geçmişindeki bir tur (takip sorularında bağlam için).
public struct ChatTurn: Sendable {
    public let question: String
    public let answer: String
    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

/// Çok adımlı, araç kullanan mail ajanı (OpenRouter function-calling).
/// Soruyu yanıtlamak için arar, mail okur, bulduğuna göre yeniden arar; bitince yanıtlar.
public struct ToolAgent: Sendable {
    let store: IndexStore
    let searcher: Searcher
    let llm: OpenRouterClient
    let maxSteps: Int

    public init(store: IndexStore, embedder: EmbeddingProvider?,
                llm: OpenRouterClient, maxSteps: Int = 8, reranker: Reranker? = nil,
                maxPerThread: Int? = nil) {
        self.store = store
        self.searcher = Searcher(store: store, embedder: embedder,
                                 reranker: reranker, maxPerThread: maxPerThread)
        self.llm = llm
        self.maxSteps = maxSteps
    }

    public func run(_ question: String,
                    history: [ChatTurn] = [],
                    cancel: CancellationFlag? = nil,
                    verify: Bool = false,
                    progress: (AgentStep) -> Void = { _ in }) throws -> AgentRun {
        // Önceki oturumlardan hatırlananları sistem istemine ekle (kalıcı hafıza).
        let memories = (try? store.allMemories()) ?? []
        var systemContent = Self.systemPrompt
        if !memories.isEmpty {
            let recalled = memories.map { "- \($0.text)" }.joined(separator: "\n")
            systemContent += "\n\nHATIRLADIKLARIN (önceki oturumlardan):\n\(recalled)"
        }
        var messages: [[String: Any]] = [["role": "system", "content": systemContent]]
        for turn in history {
            messages.append(["role": "user", "content": turn.question])
            messages.append(["role": "assistant", "content": turn.answer])
        }
        messages.append(["role": "user", "content": question])
        var handles: [String: SearchHit] = [:]
        var counter = 0
        var steps: [AgentStep] = []
        var cited: [SearchHit] = []
        var citedSeen = Set<String>()

        for _ in 0..<maxSteps {
            if cancel?.isCancelled == true {
                return AgentRun(answer: "İptal edildi.", steps: steps, cited: cited, verification: nil)
            }
            let response = try llm.chatRaw(messages: messages, tools: Self.tools)

            guard !response.toolCalls.isEmpty else {
                progress(AgentStep(kind: .answer, detail: ""))
                return finish(question: question, answer: response.content ?? "",
                              steps: steps, cited: cited, verify: verify, progress: progress)
            }

            messages.append(response.rawAssistantMessage)
            for call in response.toolCalls {
                let outcome = execute(call, handles: &handles, counter: &counter)
                steps.append(outcome.step)
                progress(outcome.step)
                for hit in outcome.touched where !citedSeen.contains(hit.id) {
                    citedSeen.insert(hit.id); cited.append(hit)
                }
                messages.append(["role": "tool", "tool_call_id": call.id, "content": outcome.result])
            }
        }

        // Adım sınırına ulaşıldı → araçsız son yanıt iste.
        messages.append(["role": "user",
                         "content": "Adım sınırına ulaşıldı. Şimdiye dek bulduklarınla Türkçe net bir yanıt ver."])
        let final = try llm.chatRaw(messages: messages, tools: nil)
        progress(AgentStep(kind: .answer, detail: ""))
        return finish(question: question, answer: final.content ?? "",
                      steps: steps, cited: cited, verify: verify, progress: progress)
    }

    /// `run()`'ın AKIŞLI (streaming) eşi: aynı döngü mantığını birebir aynalar ama `chatRaw`
    /// yerine `streamChatRaw` kullanır ve nihai yanıtın içerik parçalarını token token
    /// `onAnswerDelta`'ya iletir. Tool dispatch, memory enjeksiyonu, cited toplama, verify,
    /// maxSteps ve `AgentRun` üretimi `run()` ile BİREBİR aynı davranır (aynı `execute`/`finish`
    /// yardımcılarını paylaşır). Ara tool-call turlarında içerik ~boş olduğundan delta akmaz;
    /// nihai `AgentRun.answer` son turun tam içeriğidir.
    public func runStreaming(_ question: String,
                             history: [ChatTurn] = [],
                             cancel: CancellationFlag? = nil,
                             verify: Bool = false,
                             progress: @Sendable @escaping (AgentStep) -> Void = { _ in },
                             onAnswerDelta: @Sendable @escaping (String) async -> Void)
        async throws -> AgentRun {
        var messages = makeInitialMessages(question: question, history: history)
        var handles: [String: SearchHit] = [:]
        var counter = 0
        var steps: [AgentStep] = []
        var cited: [SearchHit] = []
        var citedSeen = Set<String>()

        for _ in 0..<maxSteps {
            if cancel?.isCancelled == true {
                return AgentRun(answer: "İptal edildi.", steps: steps, cited: cited, verification: nil)
            }
            let response = try await llm.streamChatRaw(messages: messages, tools: Self.tools,
                                                       onContentDelta: onAnswerDelta)

            guard !response.toolCalls.isEmpty else {
                progress(AgentStep(kind: .answer, detail: ""))
                return finish(question: question, answer: response.content ?? "",
                              steps: steps, cited: cited, verify: verify, progress: progress)
            }

            messages.append(response.rawAssistantMessage)
            for call in response.toolCalls {
                let outcome = execute(call, handles: &handles, counter: &counter)
                steps.append(outcome.step)
                progress(outcome.step)
                for hit in outcome.touched where !citedSeen.contains(hit.id) {
                    citedSeen.insert(hit.id); cited.append(hit)
                }
                messages.append(["role": "tool", "tool_call_id": call.id, "content": outcome.result])
            }
        }

        // Adım sınırına ulaşıldı → araçsız son yanıt iste (yine akıtarak).
        messages.append(["role": "user",
                         "content": "Adım sınırına ulaşıldı. Şimdiye dek bulduklarınla Türkçe net bir yanıt ver."])
        let final = try await llm.streamChatRaw(messages: messages, tools: nil,
                                                onContentDelta: onAnswerDelta)
        progress(AgentStep(kind: .answer, detail: ""))
        return finish(question: question, answer: final.content ?? "",
                      steps: steps, cited: cited, verify: verify, progress: progress)
    }

    /// Sistem istemini (kalıcı hafıza enjeksiyonu dâhil), geçmiş turları ve güncel soruyu içeren
    /// başlangıç mesaj dizisini kurar. `runStreaming` bunu kullanır; `run()` aynı kurulumu satır içi
    /// yapar (senkron yol byte-identik korunduğu için ayrı tutulur).
    private func makeInitialMessages(question: String, history: [ChatTurn]) -> [[String: Any]] {
        let memories = (try? store.allMemories()) ?? []
        var systemContent = Self.systemPrompt
        if !memories.isEmpty {
            let recalled = memories.map { "- \($0.text)" }.joined(separator: "\n")
            systemContent += "\n\nHATIRLADIKLARIN (önceki oturumlardan):\n\(recalled)"
        }
        var messages: [[String: Any]] = [["role": "system", "content": systemContent]]
        for turn in history {
            messages.append(["role": "user", "content": turn.question])
            messages.append(["role": "assistant", "content": turn.answer])
        }
        messages.append(["role": "user", "content": question])
        return messages
    }

    /// Nihai yanıtı paketler; `verify` açıksa ve yanıt boş değilse ek bir doğrulama
    /// çağrısı yapıp sonucu iliştirir, aksi halde `verification: nil` döner.
    private func finish(question: String, answer: String, steps: [AgentStep],
                        cited: [SearchHit], verify: Bool,
                        progress: (AgentStep) -> Void) -> AgentRun {
        guard verify, !answer.isEmpty else {
            return AgentRun(answer: answer, steps: steps, cited: cited, verification: nil)
        }
        progress(AgentStep(kind: .note, detail: "yanıt doğrulanıyor"))
        let verification = verifyAnswer(question: question, answer: answer, cited: cited)
        return AgentRun(answer: answer, steps: steps, cited: cited, verification: verification)
    }

    /// Yanıttaki iddiaların, ajanın okuduğu kaynak maillerle desteklenip desteklenmediğini
    /// ek bir LLM çağrısıyla denetler. Kaynak yoksa veya herhangi bir hata/çözümleme
    /// sorununda nazikçe `.unknown` döner; asla hata fırlatmaz.
    private func verifyAnswer(question: String, answer: String, cited: [SearchHit]) -> Verification {
        guard !cited.isEmpty else { return Verification(verdict: .unknown, issues: []) }

        var sources: [String] = []
        for (index, hit) in cited.enumerated() {
            let subject = hit.subject ?? "(konu yok)"
            let snippet = hit.snippet.replacingOccurrences(of: "\n", with: " ")
            sources.append("[\(index + 1)] Konu: \(subject)\n    İçerik: \(String(snippet.prefix(200)))")
        }
        let prompt = """
            Soru: \(question)

            Yanıt:
            \(answer)

            Kaynak mailler:
            \(sources.joined(separator: "\n"))

            Görev: Yanıttaki iddiaların yalnızca yukarıdaki kaynak maillerce desteklenip
            desteklenmediğini değerlendir.
            - "grounded": tüm önemli iddialar kaynaklarca destekleniyor.
            - "partial": bazı iddialar destekli, bazıları kaynaklarda yok.
            - "unsupported": iddialar kaynaklarca desteklenmiyor.
            SADECE şu şemada geçerli JSON döndür, başka hiçbir şey yazma:
            {"verdict":"grounded|partial|unsupported","issues":["kaynakta olmayan iddia için kısa not", ...]}
            """
        guard let raw = try? llm.complete(messages: [
            .init(role: "system", content: Self.verifierSystemPrompt),
            .init(role: "user", content: prompt),
        ]) else {
            return Verification(verdict: .unknown, issues: [])
        }
        // MailAgent.extractJSON: ```fence``` / açıklama metnini soyup ilk {…son } bloğunu çıkarır.
        let json = MailAgent.extractJSON(raw)
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Verification(verdict: .unknown, issues: [])
        }
        let verdict = Verification.Verdict(rawValue: (root["verdict"] as? String) ?? "") ?? .unknown
        let issues = Array(((root["issues"] as? [String]) ?? []).prefix(5))
        return Verification(verdict: verdict, issues: issues)
    }

    private func execute(_ call: OpenRouterClient.ToolCall,
                         handles: inout [String: SearchHit],
                         counter: inout Int)
        -> (result: String, step: AgentStep, touched: [SearchHit]) {
        let args = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)))
            as? [String: Any] ?? [:]

        switch call.name {
        case "search_mail":
            let query = args["query"] as? String ?? ""
            let mode = SearchMode(rawValue: (args["mode"] as? String) ?? "hybrid") ?? .hybrid
            let limit = (args["limit"] as? Int) ?? 8
            var filter = SearchFilter()
            if let days = args["days"] as? Int, days > 0 {
                filter.since = Date(timeIntervalSinceNow: -Double(days) * 86_400)
            }
            let hits = (try? searcher.search(query, mode: mode, filter: filter, limit: limit)) ?? []
            let lines = hits.map { hit -> String in
                counter += 1
                let handle = "m\(counter)"
                handles[handle] = hit
                return describe(handle: handle, hit: hit)
            }
            return (lines.isEmpty ? "Sonuç yok." : lines.joined(separator: "\n"),
                    AgentStep(kind: .search, detail: query), [])

        case "read_mail":
            guard let handle = args["handle"] as? String, let hit = handles[handle] else {
                return ("Geçersiz handle.", AgentStep(kind: .read, detail: "?"), [])
            }
            let body = (try? store.body(forID: hit.id)) ?? ""
            let result = """
                Konu: \(hit.subject ?? "-")
                Kimden: \(hit.fromName ?? hit.fromAddress ?? "-")
                Tarih: \(hit.date.map(Self.isoDate) ?? "-")
                Ekler: \(hit.attachments.joined(separator: ", "))
                Gövde:
                \(String(body.prefix(3000)))
                """
            return (result, AgentStep(kind: .read, detail: hit.subject ?? handle), [hit])

        case "list_thread":
            guard let handle = args["handle"] as? String, let hit = handles[handle],
                  let key = hit.threadKey else {
                return ("Bu mailin bir konu zinciri yok.", AgentStep(kind: .thread, detail: "?"), [])
            }
            let thread = (try? store.thread(forKey: key)) ?? []
            var touched: [SearchHit] = []
            let lines = thread.map { message -> String in
                counter += 1
                let handle = "m\(counter)"
                handles[handle] = message
                touched.append(message)
                return describe(handle: handle, hit: message)
            }
            return (lines.isEmpty ? "Boş." : lines.joined(separator: "\n"),
                    AgentStep(kind: .thread, detail: hit.subject ?? handle), touched)

        case "summarize_thread":
            guard let handle = args["handle"] as? String, let hit = handles[handle],
                  let key = hit.threadKey else {
                return ("Bu mailin konu zinciri yok.", AgentStep(kind: .thread, detail: "?"), [])
            }
            let thread = (try? store.thread(forKey: key)) ?? []
            var touched: [SearchHit] = []
            let parts = thread.map { message -> String in
                counter += 1
                let handle = "m\(counter)"
                handles[handle] = message
                touched.append(message)
                let body = (try? store.body(forID: message.id)) ?? ""
                return "[\(handle)] \(message.fromName ?? message.fromAddress ?? "-")"
                    + " · \(message.date.map(Self.isoDate) ?? "-")\n\(String(body.prefix(800)))"
            }
            return (parts.isEmpty ? "Boş." : parts.joined(separator: "\n---\n"),
                    AgentStep(kind: .thread, detail: hit.subject ?? handle), touched)

        case "find_by_sender":
            let query = args["query"] as? String ?? ""
            let limit = (args["limit"] as? Int) ?? 10
            let count = (try? store.senderCount(query)) ?? 0
            let hits = (try? store.fromSender(query, limit: limit)) ?? []
            let lines = hits.map { hit -> String in
                counter += 1
                let handle = "m\(counter)"
                handles[handle] = hit
                return describe(handle: handle, hit: hit)
            }
            let header = "\"\(query)\" ile eşleşen toplam \(count) mail. Son \(hits.count):"
            return (lines.isEmpty ? "Eşleşme yok." : header + "\n" + lines.joined(separator: "\n"),
                    AgentStep(kind: .search, detail: "gönderen: \(query)"), [])

        case "count_mail":
            var filter = SearchFilter()
            let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let from = (args["from"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let from, !from.isEmpty { filter.fromContains = from }
            if (args["has_attachment"] as? Bool) == true { filter.hasAttachment = true }
            // Tarihleri ("YYYY-MM-DD") ayrıştır; geçersiz/boşsa zarifçe yoksay (filtreye/özete girmez).
            var sinceLabel: String?
            if let s = args["since"] as? String, let d = Self.parseCountDate(s) {
                filter.since = d; sinceLabel = s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var untilLabel: String?
            if let u = args["until"] as? String, let d = Self.parseCountDate(u, endOfDay: true) {
                filter.until = d; untilLabel = u.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let count = (try? store.countMatching(query: query, filter: filter)) ?? 0
            let text = Self.countText(query: query, from: filter.fromContains, since: sinceLabel,
                                      until: untilLabel, hasAttachment: filter.hasAttachment, count: count)
            return (text, AgentStep(kind: .note, detail: "sayım: \(count)"), [])

        case "read_attachment":
            guard let handle = args["handle"] as? String, let hit = handles[handle] else {
                return ("Geçersiz handle.", AgentStep(kind: .read, detail: "ek"), [])
            }
            let path = (try? store.filePath(forID: hit.id)) ?? nil
            guard let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                return ("Mail dosyası okunamadı.", AgentStep(kind: .read, detail: "ek"), [hit])
            }
            let attachments = EMLXParser.extractAttachments(data: data)
            guard !attachments.isEmpty else {
                return ("Bu mailde ek yok.", AgentStep(kind: .read, detail: "ek"), [hit])
            }
            let wanted = args["filename"] as? String
            let chosen = wanted.flatMap { name in
                attachments.first { $0.filename.lowercased().contains(name.lowercased()) }
            } ?? attachments[0]
            let text = AttachmentText.extract(chosen)
            return ("Ek: \(chosen.filename) (\(chosen.mimeType))\n\(text)",
                    AgentStep(kind: .read, detail: "ek: \(chosen.filename)"), [hit])

        case "find_attachments":
            let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = Self.attachmentKind(from: args["kind"] as? String)
            let from = (args["from"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let limit = (args["limit"] as? Int) ?? 20
            let rows = findAttachments(name: name, kind: kind, from: from, limit: limit)
            let text = Self.findAttachmentsText(rows: rows, name: name, kind: kind,
                                                from: (from?.isEmpty ?? true) ? nil : from)
            return (text, AgentStep(kind: .search, detail: "ekler: \(rows.count)"), [])

        case "overview":
            return (overview(),
                    AgentStep(kind: .note, detail: "posta kutusu özeti"), [])

        case "remember":
            let fact = (args["fact"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fact.isEmpty else {
                return ("Boş bilgi kaydedilmedi.", AgentStep(kind: .note, detail: "hatırlanmadı"), [])
            }
            try? store.saveMemory(fact)
            let short = String(fact.prefix(60))
            return ("Hatırlandı: \(short)",
                    AgentStep(kind: .note, detail: "hatırlandı: \(short)"), [])

        default:
            return ("Bilinmeyen araç: \(call.name)", AgentStep(kind: .note, detail: call.name), [])
        }
    }

    /// `find_attachments` aracının DB yolu: ekleri ad/tür ile çeker; `from` (gönderen) verilmişse
    /// gönderen ad/e-postasında harf duyarsız süzer ve `limit`'e indirir. `allAttachments` gönderen
    /// filtresi sunmadığından `from` POST-FİLTRE uygulanır; bu yüzden süzmeden ÖNCE geniş bir havuz
    /// çekilir (aksi halde limit, filtreden önce kayıtları keserdi). I/O'yu ayrı tutar → test edilir.
    func findAttachments(name: String?, kind: AttachmentKind?, from: String?,
                         limit: Int) -> [AttachmentRow] {
        let hasFrom = !(from?.isEmpty ?? true)
        let fetchLimit = hasFrom ? max(limit, 500) : limit
        var rows = (try? store.allAttachments(query: name, kind: kind, limit: fetchLimit)) ?? []
        if hasFrom, let needle = from?.lowercased() {
            rows = rows.filter {
                ($0.fromAddress?.lowercased().contains(needle) ?? false)
                    || ($0.fromName?.lowercased().contains(needle) ?? false)
            }
        }
        return Array(rows.prefix(limit))
    }

    /// `overview` aracı: posta kutusunun genel istatistiğini store'dan toplayıp Türkçe
    /// kısa bir metin olarak üretir. `now`/`calendar` enjekte edilebildiğinden deterministik
    /// test edilebilir; biçimlendirme saf `overviewText` fonksiyonuna devredilir.
    func overview(now: Date = Date(), calendar: Calendar = .current, months: Int = 6) -> String {
        let total = (try? store.count()) ?? 0
        let accounts = (try? store.accountCounts())?.count ?? 0
        let withAttachments = (try? store.attachmentCount()) ?? 0
        let monthly = (try? store.monthlyCounts(months: months, now: now, calendar: calendar)) ?? []
        return Self.overviewText(total: total, accounts: accounts,
                                 withAttachments: withAttachments, monthly: monthly)
    }

    /// `overview` metnini üreten saf biçimlendirici (I/O içermez → kolayca test edilir).
    static func overviewText(total: Int, accounts: Int, withAttachments: Int,
                             monthly: [MonthCount]) -> String {
        var text = "Toplam \(total) mail, \(accounts) hesap. \(withAttachments) mailde ek var."
        if !monthly.isEmpty {
            let dağılım = monthly.map { "\($0.month): \($0.count)" }.joined(separator: ", ")
            text += " Son \(monthly.count) ayın aylık dağılımı: \(dağılım)."
            // En yoğun ayı yalnızca anlamlıysa ekle (eşitlikte en yeni ay seçilir).
            if let peak = monthly.max(by: { $0.count < $1.count }), peak.count > 0 {
                text += " En yoğun ay: \(peak.month) (\(peak.count))."
            }
        }
        return text
    }

    /// `count_mail` aracının saf Türkçe özet biçimlendiricisi (I/O içermez → kolayca test edilir).
    /// Yalnızca verilen (boş olmayan) ölçütleri parantez içinde listeler; hiçbiri yoksa sade cümle.
    static func countText(query: String?, from: String?, since: String?, until: String?,
                          hasAttachment: Bool, count: Int) -> String {
        var criteria: [String] = []
        if let query, !query.isEmpty { criteria.append("sorgu: \(query)") }
        if let from, !from.isEmpty { criteria.append("gönderen: \(from)") }
        if let since, !since.isEmpty { criteria.append("başlangıç tarihi: \(since)") }
        if let until, !until.isEmpty { criteria.append("son tarih: \(until)") }
        if hasAttachment { criteria.append("ekli") }
        let suffix = criteria.isEmpty ? "" : " (\(criteria.joined(separator: ", ")))"
        return "Ölçütlere uyan \(count) mail bulundu\(suffix)."
    }

    /// `count_mail` için "YYYY-MM-DD" tarihini yerel saat dilimine göre ayrıştırır (geçersizse nil →
    /// ajan tarihi zarifçe yoksayar). `endOfDay` true ise günün sonuna (23:59:59) çekilir; böylece
    /// `until` filtresi (m.date <= ?) verilen günü TÜMÜYLE kapsar.
    static func parseCountDate(_ string: String, endOfDay: Bool = false) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        guard let day = fmt.date(from: trimmed) else { return nil }
        guard endOfDay else { return day }
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: day) ?? day
    }

    /// `find_attachments` `kind` parametresini (Türkçe etiket / İngilizce eşanlamlı / enum adı)
    /// `AttachmentKind`'a eşler. Boş/bilinmeyen → nil (tür filtresi uygulanmaz).
    static func attachmentKind(from raw: String?) -> AttachmentKind? {
        guard let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !key.isEmpty else { return nil }
        switch key {
        case "pdf":                                              return .pdf
        case "görsel", "gorsel", "image", "resim", "foto", "fotoğraf": return .image
        case "tablo", "sheet", "excel", "spreadsheet":           return .sheet
        case "belge", "doc", "document", "döküman", "doküman", "word": return .doc
        case "sunum", "presentation", "slayt", "slide":          return .presentation
        case "arşiv", "arsiv", "archive", "zip":                 return .archive
        case "ses", "audio":                                     return .audio
        case "video":                                            return .video
        case "kod", "code":                                      return .code
        case "diğer", "diger", "other":                          return .other
        default:                                                 return nil
        }
    }

    /// `find_attachments` aracının saf Türkçe biçimlendiricisi (I/O içermez → kolayca test edilir).
    /// Üst satırda (boş olmayan) ölçütler + bulunan ek sayısı; her satır "dosya adı · gönderen · tarih".
    /// Sonuç yoksa "ek bulunamadı" döner (ölçütler yine parantezde listelenir). Tarih `RelativeTime`
    /// ile okunur kısaltılır (TR diakritikli, deterministik).
    static func findAttachmentsText(rows: [AttachmentRow], name: String?, kind: AttachmentKind?,
                                    from: String?, calendar: Calendar = .current) -> String {
        var criteria: [String] = []
        if let name, !name.isEmpty { criteria.append("ad: \(name)") }
        if let kind { criteria.append("tür: \(kind.label)") }
        if let from, !from.isEmpty { criteria.append("gönderen: \(from)") }
        let suffix = criteria.isEmpty ? "" : " (\(criteria.joined(separator: ", ")))"
        guard !rows.isEmpty else { return "Ölçütlere uyan ek bulunamadı\(suffix)." }
        let lines = rows.map { row -> String in
            let sender = row.fromName ?? row.fromAddress ?? "-"
            let date = row.date.map { RelativeTime.absolute($0, calendar: calendar) } ?? "-"
            return "- \(row.fileName) · \(sender) · \(date)"
        }
        return "\(rows.count) ek bulundu\(suffix):\n" + lines.joined(separator: "\n")
    }

    private func describe(handle: String, hit: SearchHit) -> String {
        let date = hit.date.map(Self.isoDate) ?? "-"
        let attachments = hit.attachments.isEmpty ? "" : " [ek: \(hit.attachments.joined(separator: ", "))]"
        return "\(handle): \"\(hit.subject ?? "-")\" — \(hit.fromName ?? hit.fromAddress ?? "-")"
            + " · \(date) · \(hit.mailbox)\(attachments)\n   \(hit.snippet.prefix(160))"
    }

    private static func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static let systemPrompt = """
        Sen bir e-posta araştırma ajanısın. Kullanıcının sorusunu, verilen araçları kullanarak
        adım adım yanıtlarsın. Mailleri 'handle' (örn. m1) ile gezersin. Araçlar:
        - search_mail: maillerde ara (hibrit/anlamsal/kelime, tarih filtresi).
        - read_mail: bir mailin tam gövdesini oku.
        - find_by_sender: bir göndericiden gelen mailleri ve toplam sayıyı getir.
        - count_mail: ölçütlere (sorgu/gönderen/tarih/ek) uyan mail SAYISINI döndür. Nicel/sayma
          soruları ("kaç ...", "ne kadar ...") için; içerik değil yalnız sayı gerektiğinde kullan.
        - list_thread / summarize_thread: bir konunun mailleri (özet listesi / tam gövdeler).
        - read_attachment: PDF/görsel/metin ekten içerik çıkar (fatura, fiş, sözleşme için — OCR dahil).
        - find_attachments: ekleri ada/türe (pdf/görsel/tablo...)/gönderene göre LİSTELE (mail içeriği
          değil, ek dosyaları). "hangi PDF'ler geldi", "X'in gönderdiği ekler" gibi sorular için.
        - overview: posta kutusu genel istatistiği (toplam mail, hesaplar, ekler, aylık dağılım).
        - remember: kullanıcı hakkında kalıcı, gelecekte işe yarayacak bir bilgiyi sakla
          (tercih, tekrarlayan kişi/proje, "haber bültenlerini hep özetle" gibi kalıcı talimat).
          Sadece gerçekten kalıcı bilgiler için kullan; geçici sonuçları kaydetme.
        Okuduğun içeriğe göre YENİ aramalar yapabilirsin. Yeterli bilgi toplayınca araç çağırmayı
        bırak ve Türkçe, net, KAYNAKLI bir yanıt yaz (hangi maillerden çıkardığını belirt).
        Uydurma; yalnızca maillerdeki bilgiye dayan.
        Sistem isteminde "HATIRLADIKLARIN" başlığı altındaki maddeler önceki oturumlardan gelen
        kalıcı bilgilerdir; yanıtlarında bunları bildiğin kabul edip dikkate al.
        """

    static let verifierSystemPrompt = """
        Sen bir yanıt denetleyicisisin. Sana bir soru, bir asistan yanıtı ve yanıtın dayandığı
        kaynak mailler verilir. Yanıttaki iddiaların yalnızca bu kaynaklarla desteklenip
        desteklenmediğini tarafsızca değerlendirir, desteklenmeyen iddialar için kısa Türkçe
        notlar yazarsın. Yalnızca istenen JSON şemasında yanıt ver.
        """

    static var tools: [[String: Any]] {[
        ["type": "function", "function": [
            "name": "search_mail",
            "description": "Maillerde arama yapar (hibrit/anlamsal/kelime). Sonuçları handle'larla döndürür.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Arama sorgusu"],
                    "mode": ["type": "string", "enum": ["hybrid", "semantic", "fts"],
                             "description": "Arama modu (varsayılan hybrid)"],
                    "days": ["type": "integer", "description": "Son N güne sınırla (opsiyonel)"],
                    "limit": ["type": "integer", "description": "Sonuç sayısı (varsayılan 8)"],
                ],
                "required": ["query"],
            ],
        ]],
        ["type": "function", "function": [
            "name": "read_mail",
            "description": "Bir mailin tam içeriğini handle ile okur.",
            "parameters": [
                "type": "object",
                "properties": ["handle": ["type": "string", "description": "Mail handle'ı, örn. m1"]],
                "required": ["handle"],
            ],
        ]],
        ["type": "function", "function": [
            "name": "list_thread",
            "description": "Bir mailin ait olduğu konudaki tüm mailleri (özet) listeler.",
            "parameters": [
                "type": "object",
                "properties": ["handle": ["type": "string", "description": "Mail handle'ı"]],
                "required": ["handle"],
            ],
        ]],
        ["type": "function", "function": [
            "name": "summarize_thread",
            "description": "Bir konudaki TÜM maillerin gövdelerini getirir (özet çıkarmak için).",
            "parameters": [
                "type": "object",
                "properties": ["handle": ["type": "string", "description": "Konudaki bir mailin handle'ı"]],
                "required": ["handle"],
            ],
        ]],
        ["type": "function", "function": [
            "name": "find_by_sender",
            "description": "Belirli bir göndericiden (ad veya e-posta) gelen mailleri ve toplam sayıyı getirir.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Gönderici adı veya e-postası (kısmi)"],
                    "limit": ["type": "integer", "description": "Sonuç sayısı (varsayılan 10)"],
                ],
                "required": ["query"],
            ],
        ]],
        ["type": "function", "function": [
            "name": "count_mail",
            "description": "Belirtilen ölçütlere uyan mail SAYISINI döndürür (içerik değil). "
                + "Nicel/sayma sorular için kullan (örn. 'geçen ay kaç fatura', 'Ali'den kaç mail', "
                + "'kaç ekli mail').",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string",
                              "description": "Konu/gövdede aranacak kelimeler (opsiyonel)"],
                    "from": ["type": "string",
                             "description": "Gönderen adı/e-postasında geçen metin (opsiyonel)"],
                    "since": ["type": "string",
                              "description": "Başlangıç tarihi (dahil), YYYY-MM-DD (opsiyonel)"],
                    "until": ["type": "string",
                              "description": "Bitiş tarihi (dahil), YYYY-MM-DD (opsiyonel)"],
                    "has_attachment": ["type": "boolean",
                                       "description": "Yalnızca ekli mailleri say (opsiyonel)"],
                ],
            ],
        ]],
        ["type": "function", "function": [
            "name": "read_attachment",
            "description": "Bir mailin ekinden metin çıkarır (PDF/görsel OCR/metin). Fatura, fiş, sözleşme içeriği için.",
            "parameters": [
                "type": "object",
                "properties": [
                    "handle": ["type": "string", "description": "Eki olan mailin handle'ı"],
                    "filename": ["type": "string", "description": "Belirli bir ek adı (opsiyonel; yoksa ilk ek)"],
                ],
                "required": ["handle"],
            ],
        ]],
        ["type": "function", "function": [
            "name": "find_attachments",
            "description": "E-posta EKLERİNİ ada/türe/gönderene göre listeler (mail içeriği değil, "
                + "ek dosyaları). 'hangi PDF'ler', 'X'in gönderdiği ekler' gibi sorular için.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string",
                             "description": "Dosya adında geçen metin (opsiyonel)"],
                    "kind": ["type": "string",
                             "enum": ["pdf", "görsel", "tablo", "belge", "sunum",
                                      "arşiv", "ses", "video", "kod"],
                             "description": "Ek türü (opsiyonel)"],
                    "from": ["type": "string",
                             "description": "Gönderen adı/e-postasında geçen metin (opsiyonel)"],
                    "limit": ["type": "integer", "description": "Sonuç sayısı (varsayılan 20)"],
                ],
            ],
        ]],
        ["type": "function", "function": [
            "name": "overview",
            "description": "Posta kutusunun genel istatistiğini döndürür "
                + "(toplam mail, hesap sayısı, ekli mail sayısı, son ayların aylık dağılımı). "
                + "Parametre almaz.",
            "parameters": [
                "type": "object",
                "properties": [String: Any](),
            ],
        ]],
        ["type": "function", "function": [
            "name": "remember",
            "description": "Kullanıcı hakkında kalıcı, gelecekte işe yarayacak bir bilgiyi hatırla "
                + "(tercih, tekrarlayan kişi/proje, kalıcı talimat). Sadece gerçekten kalıcı bilgiler için.",
            "parameters": [
                "type": "object",
                "properties": [
                    "fact": ["type": "string", "description": "Hatırlanacak kalıcı bilgi (kısa ve net)"],
                ],
                "required": ["fact"],
            ],
        ]],
    ]}
}
