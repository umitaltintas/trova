import SwiftUI
import AppKit

/// Temizlenmiş e-posta HTML'ini salt-okunur gösterir.
///
/// E-posta HTML'i kendi renklerini taşır (çoğunlukla beyaz zemin için siyah metin).
/// Koyu temada şeffaf zemine bu metin görünmez olur; bu yüzden — diğer mail
/// istemcileri gibi — gövdeyi her zaman **beyaz "kâğıt" üzerinde, açık (aqua)
/// görünümde** render ederiz. Böylece e-postanın özgün renkleri okunur kalır.
struct HTMLView: NSViewRepresentable {
    let html: String

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
        textView.isEditable = false
        textView.backgroundColor = .white
    }
}
