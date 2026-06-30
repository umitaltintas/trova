import SwiftUI
import TrovaCore

/// AI çıktılarındaki blok-düzeyi Markdown'ı (başlık, paragraf, madde/numaralı liste, kod, alıntı)
/// çizen görünüm. `MarkdownBlocks.parse` ile blokları ayırır; her blok metnindeki satır-içi
/// biçimlendirmeyi (kalın/italik/bağlantı/`kod`) ayrıca uygular. Streaming sırasında `text`
/// güncellendikçe yeniden ayrıştırılır — ucuz, sorun değil. Dikey akış; uzun satırlar sarar,
/// yatay taşma olmaz.
struct MarkdownText: View {
    let text: String
    var baseSize: CGFloat = 13

    init(_ text: String, baseSize: CGFloat = 13) {
        self.text = text
        self.baseSize = baseSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, content):
            // Seviyeye göre Theme başlık fontu (SF Pro Rounded), üst boşlukla ayrılır.
            Text(inline(content))
                .font(.rounded(headingSize(level), .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, level <= 2 ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .paragraph(content):
            Text(inline(content))
                .font(.system(size: baseSize))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .bulletList(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(.system(size: baseSize)).foregroundStyle(Theme.accent)
                        Text(inline(item))
                            .font(.system(size: baseSize)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.leading, 4)

        case let .orderedList(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.mono(baseSize - 1)).foregroundStyle(Theme.accent)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(inline(item))
                            .font(.system(size: baseSize)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.leading, 4)

        case let .code(code):
            // Tek satırlık kod yatay taşmasın diye yatay scroll; arka plan kart yüzeyi.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.mono(baseSize - 1))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))

        case let .quote(content):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: 3)
                Text(inline(content))
                    .font(.system(size: baseSize))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Başlık seviyesine göre punto: 1 en büyük, 3+ taban puntoya yaklaşır.
    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return baseSize + 6
        case 2: return baseSize + 3
        case 3: return baseSize + 1
        default: return baseSize
        }
    }

    /// Satır-içi markdown'ı (kalın/italik/bağlantı/`kod`) çözer; ayrıştırma hatasında düz metne döner.
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
