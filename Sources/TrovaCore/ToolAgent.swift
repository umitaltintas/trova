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
public struct ToolAgent {
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
        - list_thread / summarize_thread: bir konunun mailleri (özet listesi / tam gövdeler).
        - read_attachment: PDF/görsel/metin ekten içerik çıkar (fatura, fiş, sözleşme için — OCR dahil).
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
