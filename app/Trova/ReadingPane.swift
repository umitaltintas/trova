import SwiftUI
import QuickLook   // .quickLookPreview(_:) modifier'ı için
import TrovaCore

// MARK: - Okuma paneli

struct ReadingPane: View {
    @Environment(AppModel.self) private var model
    @State private var formatted = true

    var body: some View {
        @Bindable var model = model
        content
            .sheet(isPresented: $model.showSimilarSheet) {
                SimilarMailsSheet().environment(model)
            }
            // Ek çiplerinin sağ tık "Hızlı Bak" önizlemesi bu panoya bağlıdır. Bölümler karşılıklı
            // dışlar (ContentView `else if`) → okuma paneli ile Ekler sütunu aynı anda görünmez; her
            // yüzey kendi binding'ini tetikleyicisine yakın taşır ve çakışmaz.
            .quickLookPreview($model.quickLookURL)
    }

    /// Gövde vurgusu yalnız arama bölümünde ve vurgulanacak terim varken etkindir; diğer
    /// bölümlerde (Sor/Kişiler/Bugün…) boş → hiç vurgu yapılmaz.
    private var bodyHighlightTerms: [String] {
        model.section == .search ? model.highlightTerms : []
    }

    /// Performans: çok uzun gövdede vurgu taraması ilk N karaktere sınırlanır.
    private static let bodyHighlightScanLimit = 20_000

    /// Düz metin gövdeyi, arama terimleri varsa vurgulu `Text` olarak kurar; yoksa düz `Text`.
    /// Ofsetler ilk `bodyHighlightScanLimit` karakter üzerinde hesaplanır; bu prefix tam metinle
    /// aynı baş karakterleri paylaştığından aralıklar tam gövdeye de güvenle uygulanır.
    private func bodyText(_ raw: String) -> Text {
        let terms = bodyHighlightTerms
        guard !terms.isEmpty else { return Text(raw) }
        let scan = raw.count > Self.bodyHighlightScanLimit ? String(raw.prefix(Self.bodyHighlightScanLimit)) : raw
        let ranges = TermHighlighter.ranges(in: scan, terms: terms)
        guard !ranges.isEmpty else { return Text(raw) }
        return Text(AttributedString(body: raw, highlights: ranges))
    }

    @ViewBuilder private var content: some View {
        if let hit = model.selectedHit {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(hit.subject ?? "(konu yok)")
                        .font(.rounded(18, .bold)).foregroundStyle(Theme.ink)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Avatar(name: hit.fromName, email: hit.fromAddress, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            // Uzun ad/adres pencere genişliğini zorlamasın: tek satır + kuyruktan kırp.
                            Text(hit.fromName ?? hit.fromAddress ?? "—")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                                .lineLimit(1).truncationMode(.tail)
                            if let address = hit.fromAddress, hit.fromName != nil {
                                Text(address).font(.system(size: 11)).foregroundStyle(Theme.muted)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Spacer()
                        MessageBadges(isRead: hit.isRead, isFlagged: hit.isFlagged, dotSize: 9)
                        if let date = hit.date {
                            Text(RelativeTime.format(date, now: Date()))
                                .font(.mono(11)).foregroundStyle(Theme.muted)
                                .help(RelativeTime.absolute(date))
                                .accessibilityLabel("Tarih: \(RelativeTime.absolute(date))")
                        }
                    }
                    // Üst-veri çipleri (kutu + ekler) dar okuma panosunda taşmasın diye sarmalanır.
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        Chip(text: hit.mailbox, systemImage: "tray")
                        ForEach(hit.attachments, id: \.self) { name in
                            // Sol tık: eki aç (mevcut davranış). Sağ tık: Hızlı Bak / Eki aç.
                            Button { model.openAttachment(named: name) } label: {
                                Chip(text: name, systemImage: "paperclip")
                            }
                            .buttonStyle(.plain).help("Eki aç · Sürükleyerek dışa aktar")
                            // Sürükleyerek Finder'a bırakınca ek dosya olarak dışa aktarılır. Tıkla-aç ve sağ-tık
                            // menüsü değişmez. Çıkarma başarısızsa boş sağlayıcı — sürükleme sessizce başlamaz.
                            .onDrag {
                                guard let url = model.attachmentDragURL(named: name, messageID: hit.id)
                                else { return NSItemProvider() }
                                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                            }
                            .contextMenu {
                                Button { model.quickLookAttachment(named: name) } label: {
                                    Label("Hızlı Bak", systemImage: "eye")
                                }
                                Button { model.openAttachment(named: name) } label: {
                                    Label("Eki aç", systemImage: "arrow.up.right.square")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Eylem çubuğu (UI v2 sadeleşmesi): birincil "Yanıtla" + "Mail'de Aç" + ikon-only
                    // yıldız + "⋯" menüsü (Markdown kopyala / Benzer mailler / Yanıt taslağı). Eski
                    // yedi düğmelik duvar bu dörde indi. FlowLayout ile sarmalanır → dar panoda
                    // kırpılmaz; biçim seçici (yalnız HTML varken) son öğe olarak akışa katılır
                    // (FlowLayout sarma layout'u olduğundan itici bir Spacer kullanılmaz).
                    let pinned = model.pinnedIDs.contains(hit.id)
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        Button { model.composeReply() } label: {
                            Label("Yanıtla", systemImage: "arrowshape.turn.up.left")
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small).tint(Theme.accent)
                        .disabled((hit.fromAddress ?? "").isEmpty)
                        .help("Bu maile Mail.app'te yanıt oluştur (gönderme yok; yalnız pencere açılır)")

                        Button { model.openInMail() } label: {
                            Label("Mail'de Aç", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(MailLink.appleMailURL(messageID: model.selectedMessageID) == nil)
                        .help("Bu maili Apple Mail.app'te aç (yanıtlamak/işlem yapmak için)")

                        // Trova-yerel yıldızla/yıldızı kaldır (Apple Mail'e YAZMAZ; anahtar message.id).
                        Button { model.togglePin(id: hit.id) } label: {
                            Image(systemName: pinned ? "star.fill" : "star")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(pinned ? Theme.amber : Theme.accent)
                        .help(pinned ? "Bu mailin Trova-yerel yıldızını kaldır"
                                     : "Bu maili Trova içinde yıldızla (Apple Mail'e yazmaz)")

                        // İkincil eylemler tek "⋯" menüsünde toplandı.
                        Menu {
                            Button {
                                Exporter.copy(MarkdownExporter.email(hit, body: model.selectedBody))
                            } label: {
                                Label("Markdown kopyala", systemImage: "doc.on.doc")
                            }
                            Button { model.loadSimilar(messageID: hit.id) } label: {
                                Label("Benzer mailler", systemImage: "square.stack.3d.up")
                            }
                            Button { model.generateReplyDraft() } label: {
                                Label("Yanıt taslağı", systemImage: "pencil.and.outline")
                            }
                            .disabled((hit.fromAddress ?? "").isEmpty || model.isDraftingReply)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .foregroundStyle(Theme.accent)
                        .help("Diğer eylemler: Markdown kopyala, benzer mailler, yanıt taslağı")

                        if model.selectedHTML?.isEmpty == false {
                            Picker("", selection: $formatted) {
                                Text("Biçimli").tag(true)
                                Text("Düz").tag(false)
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 140).controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Yanıt taslağı kartı: yalnız bu maile aittir; üretilirken/hata olunca da gösterilir.
                    if model.replyDraftHit == hit.id,
                       model.replyDraft != nil || model.isDraftingReply || model.draftError != nil {
                        ReplyDraftCard()
                    }
                }
                .padding(16)

                Divider().overlay(Theme.line)

                if formatted, let html = model.selectedHTML, !html.isEmpty {
                    HTMLView(html: html, terms: bodyHighlightTerms)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line))
                        .padding(12)
                } else {
                    ScrollView {
                        bodyText(model.selectedBody?.isEmpty == false ? model.selectedBody! : hit.snippet)
                            .font(.system(size: 13)).foregroundStyle(Theme.ink).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }
                }

                if model.selectedThread.count > 1 {
                    Divider().overlay(Theme.line)
                    ConversationSection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface)
        } else {
            EmptyState(icon: "envelope.open",
                       title: "Mail seçin",
                       subtitle: "Soldaki listeden bir mail seçince içeriği burada okunur.")
                .background(Theme.surface)
        }
    }
}

/// "Benzer mailler" sheet'i: seçili maile embedding'e göre en yakın mailleri benzerlik
/// çipiyle listeler; bir satıra dokununca o maile geçer. Yükleme sırasında iskelet,
/// sonuç yoksa (ya da mail gömülü değilse) yönlendirici boş durum gösterir.
private struct SimilarMailsSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 16)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Benzer mailler").font(.rounded(15, .bold)).foregroundStyle(Theme.ink)
                    if let subject = model.similarSourceSubject, !subject.isEmpty {
                        Text(subject).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer()
                if !model.isLoadingSimilar && !model.similarMails.isEmpty {
                    ListExportMenu(markdown: { model.exportSimilar() },
                                   csv: { model.exportSimilarCSV() }, filename: "Benzer mailler")
                }
                Button { model.showSimilarSheet = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain).help("Kapat")
            }
            .padding(16)

            Divider().overlay(Theme.line)

            Group {
                if model.isLoadingSimilar {
                    SkeletonList(rows: 5)
                } else if model.similarMails.isEmpty {
                    EmptyStateView(content: EmptyStates.similar(hasVectors: model.vectorCount > 0))
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.similarMails) { hit in
                                SimilarRow(hit: hit) { model.openSimilar(hit) }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 440, height: 540)
        .background(Theme.surface)
    }
}

/// Benzer mailler listesindeki tek satır: gönderen + konu + benzerlik yüzdesi çipi.
private struct SimilarRow: View {
    let hit: SearchHit
    let action: () -> Void

    // Normalize vektörlerde skor = kosinüs [-1, 1]; yüzdeyi [0, 100] aralığına kırp.
    private var percent: Int { max(0, min(100, Int((hit.score * 100).rounded()))) }

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
                Chip(text: "%\(percent)", systemImage: "sparkles")
                    .help("Anlamsal benzerlik: %\(percent)")
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Okuma panelinin altındaki katlanabilir "Konuşma" bölümü: seçili mailin konusundaki (thread)
/// mailleri `ConversationTimeline` ile tekilleştirip kronolojik (en eski üstte) dikey bir zaman
/// çizelgesi olarak dizer. Başlıktan katlanır/açılır; açıkken (istenirse) konu özeti kartı + mesaj
/// listesi gösterilir. Uzun konuşma okuma panelini yutmasın diye liste ~5 satırla sınırlı bir
/// kaydırma alanındadır.
private struct ConversationSection: View {
    @Environment(AppModel.self) private var model
    /// Katlama durumu yereldir (varsayılan açık); AppModel'e state eklenmez.
    @State private var expanded = true

    /// Kaydırma yüksekliği hesabı için sabit satır ölçüleri.
    private let rowHeight: CGFloat = 40
    private let rowSpacing: CGFloat = 4
    private let maxVisibleRows = 5

    private var showSummary: Bool {
        model.threadSummary != nil && model.summaryThreadKey == model.selectedHit?.threadKey
    }

    /// Dışa aktarma dosya adı: "Konuşma <konu>" (konu boşsa yalnız "Konuşma").
    private var exportFilename: String {
        let subject = (model.selectedHit?.subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? "Konuşma" : "Konuşma \(subject)"
    }

    var body: some View {
        // Tekilleştirilmiş, kronolojik akış — hem başlık sayısı hem liste bunu kullanır.
        let rows = ConversationTimeline.timeline(model.selectedThread)
        let visible = min(rows.count, maxVisibleRows)
        let scrollHeight = CGFloat(visible) * rowHeight + CGFloat(max(0, visible - 1)) * rowSpacing

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint)
                        Text("KONUŞMA (\(rows.count) MAIL)")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint).tracking(0.6)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(expanded ? "Konuşmayı katla" : "Konuşmayı aç")

                Spacer()

                if model.isSummarizing {
                    ProgressView().controlSize(.small)
                } else {
                    Button { model.summarizeThread() } label: {
                        Label("Konuyu özetle", systemImage: "text.append")
                    }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                }

                // Konuşmanın tamamını (zaman çizelgesi sırasıyla) tek dosyaya aktar.
                ListExportMenu(markdown: { model.exportConversation() },
                               csv: { model.exportConversationCSV() },
                               filename: exportFilename)
                    .help("Konuşmanın tamamını Markdown ya da CSV olarak dışa aktar")
            }
            .padding(.horizontal, 16).padding(.top, 8)

            if expanded {
                if showSummary, let summary = model.threadSummary {
                    ThreadSummaryCard(summary: summary)
                        .padding(.horizontal, 16).padding(.vertical, 4)
                }

                ScrollView(showsIndicators: true) {
                    VStack(spacing: rowSpacing) {
                        ForEach(rows) { message in
                            ConversationRow(message: message, height: rowHeight)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: scrollHeight)
                .padding(.bottom, 10)
            }
        }
    }
}

/// Konuşma zaman çizelgesindeki tek satır: küçük avatar + gönderen adı + göreli tarih. Açık olan
/// mail (`message.id == model.selection`) accentSoft dolgu + accent çerçeveyle vurgulanır; satıra
/// dokununca o maile geçilir.
private struct ConversationRow: View {
    @Environment(AppModel.self) private var model
    let message: SearchHit
    let height: CGFloat

    // Kimlik eşleşmesi yeterli değil: seçili mailin kopyası timeline dedup'ında elenmişse ayakta
    // kalan satırın kimliği seçime uymaz; o durumda normalize messageID üzerinden de eşleşilir.
    private var isCurrent: Bool {
        ConversationTimeline.isCurrentRow(
            rowID: message.id, rowMessageID: message.messageID,
            selectionID: model.selection, selectionMessageID: model.selectedMessageID)
    }

    /// Erişilebilirlik etiketi: "<gönderen>, <mutlak tarih>".
    private var a11yLabel: String {
        let who = message.fromName ?? message.fromAddress ?? "Bilinmeyen gönderen"
        if let date = message.date { return "\(who), \(RelativeTime.absolute(date))" }
        return who
    }

    var body: some View {
        Button {
            model.selection = message.id
            model.loadSelected()
        } label: {
            HStack(spacing: 8) {
                Avatar(name: message.fromName, email: message.fromAddress, size: 26)
                Text(message.fromName ?? message.fromAddress ?? "—")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                if let date = message.date {
                    Text(RelativeTime.short(date, now: Date()))
                        .font(.mono(10)).foregroundStyle(Theme.faint)
                        .help(RelativeTime.absolute(date))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Theme.accentSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .stroke(isCurrent ? Theme.accent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yLabel)
    }
}

/// "Konuyu özetle" çıktısını gösteren, kopyalanabilir markdown kartı.
private struct ThreadSummaryCard: View {
    let summary: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Konu özeti", systemImage: "sparkles")
                    .font(.rounded(12, .semibold)).foregroundStyle(Theme.accent)
                Spacer()
                Button { Exporter.copy(summary); copied = true } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 11))
                .help("Özeti panoya kopyala")
            }
            // Blok-düzeyi markdown (başlık/liste/kod) render edilir; satır-içi de korunur.
            MarkdownText(summary, baseSize: 12)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// "Yanıt taslağı" çıktısını gösteren kart: canlı dolar, kopyalanabilir ve "Mail'de yanıtla"
/// ile Mail.app oluşturma penceresi açar. ThreadSummaryCard'ı aynalar (gönderme/yazma yok).
private struct ReplyDraftCard: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Yanıt taslağı", systemImage: "pencil.and.outline")
                    .font(.rounded(12, .semibold)).foregroundStyle(Theme.accent)
                if model.isDraftingReply { ProgressView().controlSize(.small) }
                Spacer()
                Button { model.clearReplyDraft() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).font(.system(size: 11))
                .help("Taslağı kapat")
            }

            if let error = model.draftError {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let draft = model.replyDraft, !draft.isEmpty {
                // Blok-düzeyi markdown render edilir; metin seçilebilir/kopyalanabilir.
                MarkdownText(draft, baseSize: 12).textSelection(.enabled)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    Button { Exporter.copy(draft); copied = true } label: {
                        Label(copied ? "Kopyalandı" : "Kopyala",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Taslağı panoya kopyala")
                    Button { model.composeReplyWithDraft() } label: {
                        Label("Mail'de yanıtla", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
                    .help("Taslağı panoya kopyalayıp Mail.app yanıt penceresini açar (gönderme yok)")
                }
            } else if model.isDraftingReply {
                Text("Taslak üretiliyor…").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}
