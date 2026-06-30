import Foundation

/// Okunan/seçili bir maile, LLM ile KISA ve nazik bir Türkçe YANIT TASLAĞI üretir.
/// Saf prompt + `messages(from:subject:body:)` deseni (`ThreadSummarizer`'ı aynalar):
/// gövdenin getirilmesi ve akış (streaming) çağırana aittir; burada yalnız modele
/// verilecek `ChatMessage` dizisi kurulur. Ağ/ajan yok → kolayca test edilir.
public enum ReplyDraft {

    /// Modele rolünü ve katı sınırları anlatan sistem istemi.
    public static let systemPrompt = """
        Sen bir e-posta asistanısın. Sana yanıtlanacak bir e-posta (gönderen, konu, gövde) verilir. \
        Bu maile KISA, nazik ve profesyonel bir Türkçe YANIT TASLAĞI yaz. \
        Yalnızca yanıtın gövdesini ver: uygun bir selamlamayla başla, kapanış (ör. "Saygılarımla") ile bitir. \
        Konu satırı, "Kime/Konu" başlıkları veya taslak dışında ön/son açıklama EKLEME. \
        Yalnızca verilen bilgilere dayan; uydurma bilgi, tarih, rakam ya da söz EKLEME. \
        Bir bilgi eksikse uydurmak yerine [ ... ] biçiminde kısa bir yer tutucu bırak. \
        Sade düz metin kullan; abartılı ifadelerden ve gereksiz tekrardan kaçın.
        """

    /// Orijinal mailden taslak için LLM mesajlarını üretir (sistem + gönderen/konu/gövde istemi).
    public static func messages(from fromName: String?, subject: String, body: String) -> [ChatMessage] {
        [.init(role: "system", content: systemPrompt),
         .init(role: "user", content: buildPrompt(from: fromName, subject: subject, body: body))]
    }

    /// Kullanıcı mesajını kurar: gönderen, konu ve (çok uzunsa kırpılan) gövde.
    /// Eksik alanlar güvenli yer tutucularla (`?`, `(konu yok)`, `(gövde yok)`) doldurulur.
    static func buildPrompt(from fromName: String?, subject: String, body: String) -> String {
        let sender = (fromName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let subj = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        // Çok uzun gövdeler istemi şişirmesin: makul bir sınıra kırp (özetleyiciyle aynı ölçek).
        let cleanBody = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        return [
            "Yanıtlanacak e-posta:",
            "Gönderen: \(sender.isEmpty ? "?" : sender)",
            "Konu: \(subj.isEmpty ? "(konu yok)" : subj)",
            "Gövde:",
            cleanBody.isEmpty ? "(gövde yok)" : cleanBody,
            "",
            "Bu maile Türkçe, kısa ve nazik bir yanıt taslağı yaz.",
        ].joined(separator: "\n")
    }
}
