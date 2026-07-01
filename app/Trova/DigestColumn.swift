import SwiftUI
import TrovaCore

// MARK: - Bugün (proaktif asistan) sütunu

struct DigestColumn: View {
    @Environment(AppModel.self) private var model

    private var isEmpty: Bool {
        model.needsReply.isEmpty && model.waitingOn.isEmpty && model.digestText.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DigestCard()
                if !model.needsReply.isEmpty {
                    TriageSection(title: "Yanıt gerekiyor",
                                  subtitle: "Karşı taraf en son yazdı",
                                  icon: "arrowshape.turn.up.left.fill",
                                  hits: model.needsReply)
                }
                if !model.waitingOn.isEmpty {
                    TriageSection(title: "Yanıt bekliyor",
                                  subtitle: "Sen yazdın, henüz yanıt yok",
                                  icon: "hourglass",
                                  hits: model.waitingOn)
                }
                // Görmezden gelinen öğe varsa: sayı + "Gizlenenleri geri al".
                if model.dismissedHiddenCount > 0 {
                    DismissedFooter()
                }
                if model.isDigesting && model.needsReply.isEmpty && model.waitingOn.isEmpty
                    && model.digestText.isEmpty {
                    // Brifing hazırlanırken spinner yerine iskelet satırlar.
                    SkeletonList(rows: 3).frame(minHeight: 180)
                } else if isEmpty && !model.isDigesting && model.dismissedHiddenCount == 0 {
                    // Yalnız gerçekten boşken (gizlenmiş öğe yokken) "her şey güncel" mesajı.
                    EmptyStateView(content: EmptyStates.digest(
                        hasNeedsReply: !model.needsReply.isEmpty,
                        hasWaiting: !model.waitingOn.isEmpty))
                        .frame(minHeight: 240)
                }
            }
            .padding(12)
        }
        .background(Theme.surface)
        .task { model.loadTriage() }
    }
}

/// Günlük brifing kartı: oluştur/yenile düğmesi + (varsa) markdown brifing.
private struct DigestCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill").font(.system(size: 14)).foregroundStyle(Theme.accent)
                Text("Günlük brifing").font(.rounded(15, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                if model.isDigesting {
                    ProgressView().controlSize(.small)
                } else {
                    Button { model.runDigest() } label: {
                        Label(model.digestText.isEmpty ? "Brifing oluştur" : "Yenile",
                              systemImage: "sparkles").font(.rounded(12, .semibold))
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                }
            }
            if model.digestText.isEmpty && !model.isDigesting {
                Text("Son 2 günde gelen mailleri tek bakışta, temaya göre gruplayıp özetler; "
                   + "yanıt bekleyenleri çıkarır.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.digestText.isEmpty {
                AnswerCard(text: model.digestText)
            }
            // Brifing veya triyaj listelerinden en az biri doluysa Markdown dışa aktarımına izin ver.
            if canExport {
                ExportBar(markdown: { model.digestMarkdown() }, filename: "Bugün brifingi")
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    /// Dışa aktarılacak bir içerik var mı (brifing metni veya triyaj listeleri).
    private var canExport: Bool {
        !(model.digestText.isEmpty && model.needsReply.isEmpty && model.waitingOn.isEmpty)
    }
}

/// Başlık + triyaj satırları (yanıt gerekiyor / yanıt bekliyor).
private struct TriageSection: View {
    @Environment(AppModel.self) private var model
    let title: String
    let subtitle: String
    let icon: String
    let hits: [SearchHit]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.accent)
                Text(title).font(.rounded(14, .semibold)).foregroundStyle(Theme.ink)
                Text("\(hits.count)").font(.mono(11)).foregroundStyle(Theme.faint)
                Spacer()
            }
            Text(subtitle.uppercased()).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.faint).tracking(0.5)
            VStack(spacing: 6) {
                ForEach(hits) { hit in
                    TriageRow(hit: hit, selected: hit.id == model.selection,
                              action: { model.selection = hit.id; model.loadSelected() },
                              onDismiss: { model.dismissDigestItem(hit) })
                }
            }
        }
    }
}

private struct TriageRow: View {
    @Environment(AppModel.self) private var model
    let hit: SearchHit
    let selected: Bool
    let action: () -> Void
    let onDismiss: () -> Void
    @State private var hovering = false

    // Aksiyon etkinlik durumları (öğenin alanlarına göre): adres/Message-ID yoksa ilgili aksiyon pasif.
    private var canReply: Bool { !(hit.fromAddress ?? "").isEmpty }
    private var canOpenInMail: Bool { MailLink.appleMailURL(messageID: hit.messageID) != nil }
    private var pinned: Bool { model.pinnedIDs.contains(hit.id) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(name: hit.fromName, email: hit.fromAddress, size: 30)
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
                if pinned {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.amber)
                }
                AgeChip(date: hit.date)
            }
            .padding(10)
            .background(selected ? Theme.accentSoft : Theme.card,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .stroke(selected ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Hızlı aksiyonlar: hover'da beliren kompakt ikon kümesi (alt sağ) — Yanıtla / Mail'de Aç / Yıldızla.
        // Pano daralırsa FlowLayout ile alt satıra kayarlar; mevcut × "Görmezden gel" üst sağda korunur.
        .overlay(alignment: .bottomTrailing) {
            if hovering {
                FlowLayout(spacing: 3, lineSpacing: 3) {
                    actionIcon("arrowshape.turn.up.left", tint: Theme.accent, enabled: canReply,
                               help: "Bu maile yanıt oluştur (gönderme yok; yalnız pencere açılır)",
                               action: { model.composeReply(hit) })
                    actionIcon("envelope", tint: Theme.accent, enabled: canOpenInMail,
                               help: "Bu maili Apple Mail.app'te aç",
                               action: { model.openInMail(messageID: hit.messageID) })
                    actionIcon(pinned ? "star.fill" : "star", tint: pinned ? Theme.amber : Theme.accent,
                               enabled: true,
                               help: pinned ? "Trova-yerel yıldızı kaldır"
                                            : "Bu maili Trova içinde yıldızla (Apple Mail'e yazmaz)",
                               action: { model.togglePin(id: hit.id) })
                }
                .fixedSize()
                .padding(3)
                .background(Theme.card.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                .padding(5)
            }
        }
        // "Görmezden gel": hover'da beliren küçük × (sağ üst köşe) + sağ tık menüsü.
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .background(Circle().fill(Theme.card).padding(1))
            }
            .buttonStyle(.plain)
            .help("Görmezden gel (yeni yanıt gelirse tekrar görünür)")
            .accessibilityLabel("Görmezden gel")
            .opacity(hovering ? 1 : 0)
            .padding(5)
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button { model.composeReply(hit) } label: {
                Label("Yanıtla", systemImage: "arrowshape.turn.up.left")
            }
            .disabled(!canReply)
            Button { model.openInMail(messageID: hit.messageID) } label: {
                Label("Mail'de Aç", systemImage: "envelope")
            }
            .disabled(!canOpenInMail)
            Button { model.togglePin(id: hit.id) } label: {
                Label(pinned ? "Yıldızı kaldır" : "Yıldızla", systemImage: pinned ? "star.fill" : "star")
            }
            Divider()
            Button { onDismiss() } label: {
                Label("Görmezden gel", systemImage: "eye.slash")
            }
        }
    }

    /// Hover aksiyon kümesindeki tek bir kompakt ikon düğmesi (pasifse soluk ve tıklanamaz).
    private func actionIcon(_ systemName: String, tint: Color, enabled: Bool,
                            help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? tint : Theme.faint)
                .frame(width: 22, height: 22)
                .background(Theme.card, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Görmezden gelinen öğe sayısını gösterir ve hepsini geri almayı sağlar.
private struct DismissedFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash").font(.system(size: 11)).foregroundStyle(Theme.faint)
            Text("\(model.dismissedHiddenCount) öğe gizlendi")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
            Spacer()
            Button { model.restoreDismissedDigest() } label: {
                Label("Gizlenenleri geri al", systemImage: "arrow.uturn.backward")
                    .font(.rounded(11, .semibold)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .help("Görmezden gelinen tüm öğeleri tekrar göster")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))
    }
}

/// Mailin yaşını "şimdi" / "3g" / "dün" gibi kısa bir çiple gösterir (tek kaynak: RelativeTime).
private struct AgeChip: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(RelativeTime.short(date, now: Date()))
                .font(.mono(10, .medium)).foregroundStyle(Theme.accent)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Theme.accentSoft, in: Capsule())
                .help(RelativeTime.absolute(date))
                .accessibilityLabel("Yaş: \(RelativeTime.absolute(date))")
        }
    }
}
