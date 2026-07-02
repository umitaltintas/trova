import Foundation

/// Ham bir arama sorgusunun sayım/filtre için çözülmüş hâli: FTS metni + yapısal filtre.
/// `runSearch`'teki ayrıştırma zincirinin (operatör → Türkçe tarih) saf, UI'dan bağımsız izdüşümü.
public struct SearchPlan: Equatable, Sendable {
    public let ftsQuery: String     // operatör/tarih kelimeleri elendikten sonra kalan arama metni
    public let filter: SearchFilter // gönderen/ek/tarih ölçütleri (hesap ve okunmadı/bayrak hariç)
    public init(ftsQuery: String, filter: SearchFilter) {
        self.ftsQuery = ftsQuery; self.filter = filter
    }
}

/// Ham sorguyu (kayıtlı arama dahil) `SearchPlan`'a çeviren saf planlayıcı.
/// `runSearch`'ün operatör→tarih→filtre kurma SIRASINI aynalar; ancak yalnız sayım/filtre üretir —
/// PRF (sorgu genişletme), embedding, rerank YOKTUR. UI durumu (hesap, okunmadı/bayrak, tarih
/// picker'ı) dışarıda bırakılır; filtre tamamen ham sorgudaki ifadelerden türer. `now`/`calendar`
/// enjekte edildiğinden deterministik test edilir.
public enum SearchPlanner {
    public static func plan(_ rawQuery: String, now: Date, calendar: Calendar = .current) -> SearchPlan {
        let raw = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // Önce Gmail-tarzı operatörler (from:/has:attachment/has:pdf), sonra Türkçe tarih ifadesi.
        let ops = SearchOperatorParser.parse(raw)
        let parsed = TurkishDateParser.parse(ops.cleaned, now: now, calendar: calendar)
        // runSearch ile aynı: tarih bulunduysa tarih sonrası temizlenmiş metin, yoksa operatör sonrası.
        let ftsQuery = parsed.hint != nil ? parsed.cleaned : ops.cleaned
        let filter = SearchFilter(
            accountID: nil,
            since: parsed.hint?.since, until: parsed.hint?.until,
            fromContains: ops.fromContains, mailboxContains: ops.mailboxContains,
            hasAttachment: ops.hasAttachment,
            attachmentKind: ops.attachmentKind,
            unreadOnly: false, flaggedOnly: false)
        return SearchPlan(ftsQuery: ftsQuery, filter: filter)
    }
}
