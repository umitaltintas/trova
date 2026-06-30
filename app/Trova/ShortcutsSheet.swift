import SwiftUI
import TrovaCore

/// ⌘/ ile açılan klavye kısayolları kılavuzu (cheat sheet).
/// `ShortcutCatalog.byGroup`'u başlıklı bölümler halinde çizer: solda tuş kombinasyonu
/// (mono rozet), sağda Türkçe açıklama. İçerik taşarsa ScrollView kaydırır; Esc ile kapanır.
struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard").font(.system(size: 16)).foregroundStyle(Theme.accent)
                Text("Klavye kısayolları").font(.rounded(15, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16)).foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain).help("Kapat")
            }
            .padding(16)

            Divider().overlay(Theme.line)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ShortcutCatalog.byGroup, id: \.group) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.group.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.faint).tracking(0.6)
                            VStack(spacing: 4) {
                                ForEach(section.items, id: \.keys) { item in
                                    ShortcutRow(item: item)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 420, height: 540)
        .background(Theme.surface)
    }
}

/// Tek bir kısayol satırı: sol tuş kombinasyonu (mono rozet) + sağ açıklama.
private struct ShortcutRow: View {
    let item: ShortcutItem

    var body: some View {
        HStack(spacing: 12) {
            Text(item.keys)
                .font(.mono(12, .medium)).foregroundStyle(Theme.accent)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .frame(minWidth: 56, alignment: .leading)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))
            Text(item.label).font(.system(size: 13)).foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
