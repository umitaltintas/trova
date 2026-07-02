import SwiftUI
import QuickLook   // .quickLookPreview(_:) modifier'ı için
import TrovaCore

// MARK: - Ekler sütunu

/// Tüm e-posta eklerini ada/türe göre arayıp tek tıkla açan 6. bölüm.
struct AttachmentsColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "paperclip").foregroundStyle(Theme.muted)
                TextField("Eklerde ara (dosya adı)…", text: $model.attachmentQuery)
                    .textFieldStyle(.plain).font(.system(size: 14))
                if !model.attachmentQuery.isEmpty {
                    Button { model.attachmentQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint)
                    }
                    .buttonStyle(.plain).help("Aramayı temizle")
                }
            }
            .padding(10).cardSurface().padding(.horizontal, 12).padding(.top, 12)
            // Canlı arama: yazdıkça (yerel SQLite LIKE) süzülür.
            .onChange(of: model.attachmentQuery) { model.loadAttachments() }

            AttachmentKindChips()

            Color.clear.frame(height: 10)
            Divider().overlay(Theme.line)

            if model.isLoadingAttachments && model.attachments.isEmpty {
                // İlk yükleme/filtre değişiminde spinner yerine iskelet satırlar.
                SkeletonList()
            } else if model.attachments.isEmpty {
                EmptyStateView(content: EmptyStates.attachments(
                    hasAny: model.attachmentKindCounts.values.reduce(0, +) > 0,
                    hasQueryOrFilter: !model.attachmentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || model.attachmentKind != nil),
                    action: { model.runIndex() })
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.attachments) { row in
                            AttachmentRowView(row: row,
                                              open: { model.openAttachmentRow(row) },
                                              quickLook: { model.quickLookAttachment(row: row) },
                                              openInMail: { model.openRowInMail(row) })
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Theme.surface)
        // Hızlı Bak önizlemesini bu sütunda bağlarız. Bölümler karşılıklı dışlar (ContentView `else if`
        // zinciri) → Ekler ve okuma paneli aynı anda hiyerarşide olmaz; her sütun tetikleyicisine yakın
        // kendi binding'ini taşır ve çakışmaz.
        .quickLookPreview($model.quickLookURL)
        .task { model.loadAttachments() }
    }
}

/// Kategori çipleri ("Tümü" + sayısı 0'dan büyük her tür); bir çip seçili türü açar/kapatır.
private struct AttachmentKindChips: View {
    @Environment(AppModel.self) private var model

    private var total: Int { model.attachmentKindCounts.values.reduce(0, +) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                AttachmentKindChip(label: "Tümü", systemImage: "square.grid.2x2",
                                   count: total, selected: model.attachmentKind == nil) {
                    model.attachmentKind = nil; model.loadAttachments()
                }
                ForEach(AttachmentKind.allCases, id: \.self) { kind in
                    let count = model.attachmentKindCounts[kind] ?? 0
                    if count > 0 {
                        AttachmentKindChip(label: kind.label, systemImage: kind.systemImage,
                                           count: count, selected: model.attachmentKind == kind) {
                            // Aynı türe tekrar dokununca filtreyi kaldır.
                            model.attachmentKind = (model.attachmentKind == kind ? nil : kind)
                            model.loadAttachments()
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }
}

/// Tek bir kategori çipi: ikon + etiket + sayı; seçiliyken indigo dolgu.
private struct AttachmentKindChip: View {
    let label: String
    let systemImage: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 9))
                Text(label).font(.system(size: 11))
                Text("\(count)").font(.mono(10))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.faint)
            }
            .foregroundStyle(selected ? .white : Theme.muted)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(selected ? Theme.accent : Theme.line, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Liste satırı: tür ikonu + dosya adı + sahip gönderen/konu + göreli tarih. Tıkla → eki aç.
private struct AttachmentRowView: View {
    let row: AttachmentRow
    let open: () -> Void
    let quickLook: () -> Void
    let openInMail: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft)
                        .frame(width: 34, height: 34)
                    Image(systemName: row.kind.systemImage)
                        .font(.system(size: 15)).foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.fileName).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 5) {
                        Text(row.fromName ?? row.fromAddress ?? "—")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                        if let subject = row.subject, !subject.isEmpty {
                            Text("· \(subject)").font(.system(size: 11))
                                .foregroundStyle(Theme.faint).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                if let date = row.date {
                    Text(RelativeTime.short(date, now: Date()))
                        .font(.mono(10)).foregroundStyle(Theme.faint)
                        .help(RelativeTime.absolute(date))
                }
                // Hover'da beliren "göz": Hızlı Bak. Satırın ana tıklaması değişmez (eki açar).
                if hovering {
                    Button(action: quickLook) {
                        Image(systemName: "eye")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain).help("Hızlı Bak")
                }
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Eki aç: \(row.fileName)")
        .contextMenu {
            Button { quickLook() } label: { Label("Hızlı Bak", systemImage: "eye") }
            Button { open() } label: { Label("Eki aç", systemImage: "arrow.up.right.square") }
            Button { openInMail() } label: { Label("Mail'de Aç", systemImage: "arrow.up.forward.app") }
        }
    }
}
