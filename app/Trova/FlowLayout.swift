import SwiftUI

/// Genişlikten bağımsız, kendiliğinden satır kıran (wrapping) yatay yerleşim.
///
/// Çip/buton satırları dar panoda taşmasın diye `HStack` yerine kullanılır: öğeler
/// kapsayıcı genişliğine sığdıkça yan yana dizilir, sığmayınca otomatik olarak bir
/// alt satıra geçer. Böylece okuma panosu/arama sütunu daraldığında düğme ve çipler
/// ekranın dışında kalıp kırpılmaz. `Layout` protokolüyle yazıldığından SwiftUI'nin
/// boyut/yerleştirme döngüsüne tam uyar (ScrollView/VStack içinde sorunsuz çalışır).
struct FlowLayout: Layout {
    /// Aynı satırdaki öğeler arası yatay boşluk.
    var spacing: CGFloat = 6
    /// Satırlar arası dikey boşluk.
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let contentWidth = rows.map { row in
            row.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, row.count - 1))
        }.max() ?? 0
        let height = rows.enumerated().reduce(CGFloat.zero) { partial, item in
            let rowHeight = item.element.map(\.size.height).max() ?? 0
            return partial + rowHeight + (item.offset > 0 ? lineSpacing : 0)
        }
        // Önerilen genişlik sonluysa onu aşma; yoksa içeriğin doğal genişliğini kullan.
        let width = proposal.width.map { min($0, contentWidth) } ?? contentWidth
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in row {
                // Öğeyi satır içinde dikey ortala (farklı yükseklikteki çip/düğmeler hizalı dursun).
                item.subview.place(
                    at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }

    private struct Item {
        let subview: LayoutSubviews.Element
        let size: CGSize
    }

    /// Öğeleri verilen genişliğe göre satırlara böler: bir öğe satıra sığmazsa yeni satıra geçer.
    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [[Item]] {
        var rows: [[Item]] = [[]]
        var x: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let current = rows.count - 1
            if !rows[current].isEmpty && x + size.width > maxWidth {
                rows.append([Item(subview: subview, size: size)])
                x = size.width + spacing
            } else {
                rows[current].append(Item(subview: subview, size: size))
                x += size.width + spacing
            }
        }
        return rows
    }
}
