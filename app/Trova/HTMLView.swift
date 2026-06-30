import SwiftUI
import AppKit
import TrovaCore

/// Temizlenmiş e-posta HTML'ini salt-okunur gösterir.
///
/// E-posta HTML'i kendi renklerini taşır (çoğunlukla beyaz zemin için siyah metin).
/// Koyu temada şeffaf zemine bu metin görünmez olur; bu yüzden — diğer mail
/// istemcileri gibi — gövdeyi her zaman **beyaz "kâğıt" üzerinde, açık (aqua)
/// görünümde** render ederiz. Böylece e-postanın özgün renkleri okunur kalır.
struct HTMLView: NSViewRepresentable {
    let html: String
    /// Render edilen metinde vurgulanacak arama terimleri (boşsa vurgu yok). Vurgu tamamen
    /// additive'dir: yalnız `.backgroundColor` ekler, render/sanitize akışına dokunmaz.
    var terms: [String] = []

    /// Vurgu hesabı için taranacak en fazla karakter (çok uzun gövdede maliyeti sınırlar).
    private static let highlightScanLimit = 20_000
    /// Vurgu arka planı: Theme.accent (indigo) soluk tonu — beyaz kâğıt üstünde okunur kalır.
    private static let highlightColor = NSColor(srgbRed: 0.35, green: 0.30, blue: 0.92, alpha: 0.22)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.appearance = NSAppearance(named: .aqua)   // dinamik renkleri açık varyanta sabitle
        scroll.automaticallyAdjustsContentInsets = false

        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = true
            textView.backgroundColor = .white
            textView.appearance = NSAppearance(named: .aqua)
            textView.textContainerInset = NSSize(width: 16, height: 16)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let attributed = try? NSAttributedString(
            data: Data(html.utf8), options: options, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            textView.string = html
        }
        // Render BİTTİKTEN sonra arama terimlerini additive olarak vurgula (yalnız arka plan).
        highlightTerms(in: textView.textStorage)
        textView.isEditable = false
        textView.backgroundColor = .white
    }

    /// Render edilen metinde `terms`'ün tüm geçişlerine soluk accent arka planı uygular.
    /// `TermHighlighter` grafem (Character) ofsetleri verir; bunlar `NSRange(_:in:)` ile UTF-16
    /// NSRange'e çevrilir (emoji/çok baytlı karakterlerde de doğru). Mevcut renk/biçim korunur.
    private func highlightTerms(in storage: NSTextStorage?) {
        guard let storage, !terms.isEmpty else { return }
        let text = storage.string
        let scan = text.count > Self.highlightScanLimit ? String(text.prefix(Self.highlightScanLimit)) : text
        let ranges = TermHighlighter.ranges(in: scan, terms: terms)
        guard !ranges.isEmpty else { return }
        storage.beginEditing()
        for r in ranges {
            guard let lo = text.index(text.startIndex, offsetBy: r.start, limitedBy: text.endIndex),
                  let hi = text.index(lo, offsetBy: r.length, limitedBy: text.endIndex) else { continue }
            storage.addAttribute(.backgroundColor, value: Self.highlightColor,
                                 range: NSRange(lo..<hi, in: text))
        }
        storage.endEditing()
    }
}
