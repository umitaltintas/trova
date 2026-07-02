import SwiftUI
import TrovaCore

// MARK: - Birden çok sütun dosyasından kullanılan ortak bileşenler
//
// Bu dosya, UI v2 bölünmesinde ContentView.swift'ten çıkarılan ve artık farklı sütun
// dosyalarından (Ara / Sor / Bugün / Kişiler / Okuma paneli) paylaşılan küçük bileşenleri
// toplar. Bu yüzden hepsi `internal` (private DEĞİL) — dosyalar arası görünür olmalılar.

/// Bir mail listesini (arama sonuçları / kişi mailleri / benzer mailler) Markdown ya da CSV olarak
/// kopyalama/kaydetme için kompakt menü. Dar başlıklarda taşmaması için tek düğmedir.
struct ListExportMenu: View {
    let markdown: () -> String
    let csv: () -> String
    let filename: String
    var labelText = "Dışa aktar"
    /// Opsiyonel: gövdeleri de içeren, konuşmalara gruplanmış TAM yazışma belgesi (yalnız Markdown).
    /// Kişi detayında "tüm yazışma" dışa aktarımı için; nil ise ilgili menü öğeleri gizlenir; böylece
    /// arama/benzer listeleri eskisi gibi yalnız düz liste dışa aktarır.
    var fullDocument: (() -> String)? = nil
    var fullDocumentFilename = ""
    @State private var copied = false

    var body: some View {
        Menu {
            if let fullDocument {
                Button {
                    Exporter.copy(fullDocument()); copied = true
                } label: { Label("Tüm yazışma (Markdown) kopyala", systemImage: "text.book.closed") }
                Button {
                    Exporter.save(fullDocument(), suggestedName: fullDocumentFilename)
                } label: { Label("Tüm yazışma (.md) kaydet", systemImage: "square.and.arrow.down") }
                Divider()
            }
            Button {
                Exporter.copy(markdown()); copied = true
            } label: { Label("Markdown kopyala", systemImage: "doc.on.doc") }
            Button {
                Exporter.save(markdown(), suggestedName: filename)
            } label: { Label(".md kaydet", systemImage: "square.and.arrow.down") }
            Divider()
            Button {
                Exporter.copy(csv()); copied = true
            } label: { Label("CSV kopyala", systemImage: "doc.on.doc") }
            Button {
                Exporter.saveCSV(csv(), suggestedName: filename)
            } label: { Label("CSV (.csv) kaydet", systemImage: "tablecells") }
        } label: {
            Label(copied ? "Kopyalandı" : labelText,
                  systemImage: copied ? "checkmark" : "square.and.arrow.up")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .foregroundStyle(Theme.accent)
        .help("Listeyi Markdown ya da CSV olarak dışa aktar")
    }
}

/// AI yanıtını (kaynaklarıyla) Markdown olarak panoya kopyalama / .md kaydetme çubuğu.
struct ExportBar: View {
    let markdown: () -> String
    let filename: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Exporter.copy(markdown()); copied = true
            } label: {
                Label(copied ? "Kopyalandı" : "Markdown kopyala",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            Button { Exporter.save(markdown(), suggestedName: filename) } label: {
                Label("Dışa aktar", systemImage: "square.and.arrow.down")
            }
            Spacer()
        }
        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.accent)
        .padding(.top, 2)
    }
}

/// Kaynak/atıf satırı: küçük avatar + konu + gönderen; seçiliyken indigo vurgu. Sor ve Kişiler
/// sütunları bir maile hızlı geçiş için kullanır.
struct CitedRow: View {
    let hit: SearchHit
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(name: hit.fromName, email: hit.fromAddress, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.subject ?? "(konu yok)").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    Text(hit.fromName ?? hit.fromAddress ?? "—").font(.system(size: 10))
                        .foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                if !hit.attachments.isEmpty {
                    Image(systemName: "paperclip").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            .padding(10)
            .background(selected ? Theme.accentSoft : Theme.card,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .stroke(selected ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Küçük sayı rozeti (örn. konuşma üye sayısı, kayıtlı aramanın canlı eşleşme sayısı).
/// Pasif satırda Theme.accent dolgulu beyaz metin; aktif (mavi) satırda kontrast için beyaz
/// dolgu + accent metin kullanılır. Genişlik içeriğe göre; "99+" gibi etiketlerde de bozulmaz.
struct CountBadge: View {
    let text: String
    let active: Bool

    var body: some View {
        Text(text)
            .font(.rounded(11, .bold))
            .foregroundStyle(active ? Theme.accent : .white)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .frame(minWidth: 18)
            .background(active ? Color.white : Theme.accent, in: Capsule())
    }
}

/// İkon + etiket + değer üçlüsü; kompakt istatistik satırı.
struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.accent).frame(width: 16)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(.mono(12, .medium)).foregroundStyle(Theme.ink)
        }
    }
}

extension AttributedString {
    /// `Snippet`'ten vurgulu metin kurar: vurgu aralıkları Theme accent + yarı-kalın, gerisi
    /// Theme.faint. Ofsetler Character birimindedir (snippet.text'e göre).
    init(snippet: Snippet, size: CGFloat = 11) {
        var attr = AttributedString(snippet.text)
        attr.foregroundColor = Theme.faint
        let total = attr.characters.count
        for h in snippet.highlights {
            guard h.start >= 0, h.length > 0, h.start + h.length <= total else { continue }
            let lo = attr.index(attr.startIndex, offsetByCharacters: h.start)
            let hi = attr.index(lo, offsetByCharacters: h.length)
            attr[lo..<hi].foregroundColor = Theme.accent
            attr[lo..<hi].font = .system(size: size, weight: .semibold)
        }
        self = attr
    }

    /// Okuma panelinde TAM gövde için: arama terimi aralıklarını Theme accent + yarı-kalın +
    /// soluk accent arka planla vurgular (iter 25 snippet stiliyle tutarlı). Taban metin rengi
    /// AYARLANMAZ → çağıran `.foregroundStyle(Theme.ink)` modifikatörü korunur; yalnız vurgular
    /// renklenir. Ofsetler `TermHighlighter`'dan Character (grafem) birimindedir.
    init(body text: String, highlights ranges: [HighlightRange], size: CGFloat = 13) {
        var attr = AttributedString(text)
        let total = attr.characters.count
        for r in ranges {
            guard r.start >= 0, r.length > 0, r.start + r.length <= total else { continue }
            let lo = attr.index(attr.startIndex, offsetByCharacters: r.start)
            let hi = attr.index(lo, offsetByCharacters: r.length)
            attr[lo..<hi].foregroundColor = Theme.accent
            attr[lo..<hi].backgroundColor = Theme.accentSoft
            attr[lo..<hi].font = .system(size: size, weight: .semibold)
        }
        self = attr
    }
}
