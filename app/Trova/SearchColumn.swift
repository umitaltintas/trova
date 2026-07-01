import SwiftUI
import TrovaCore

// MARK: - Ara sütunu

struct SearchColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Mailde ara…", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 14)).onSubmit { model.runSearch() }
                Picker("", selection: $model.mode) {
                    Text("Hibrit").tag(SearchMode.hybrid)
                    Text("Anlamsal").tag(SearchMode.semantic)
                    Text("Kelime").tag(SearchMode.fts)
                }
                .labelsHidden().frame(width: 116).controlSize(.small)
                SavedSearchButton()
            }
            .padding(10).cardSurface().padding(.horizontal, 12).padding(.top, 12)

            // Filtre/durum çip satırı; dar panoda FlowLayout ile alt satıra sarar (taşma yok).
            // UI v2: Hesap/Tarih menüleri (eski kenar çubuğu FilterBlock'undan taşındı) satırın
            // BAŞINDA durur — yalnız aramayı etkiledikleri için burada olmaları daha yerindedir.
            FlowLayout(spacing: 6, lineSpacing: 6) {
                // Hesap menüsü (varsayılan "Tümü" dışında accent dolgulu → aktif filtre ipucu).
                Menu {
                    Button("Tüm hesaplar") {
                        model.filterAccount = ""
                        if !model.query.isEmpty { model.runSearch() }
                    }
                    ForEach(model.accounts) { account in
                        Button("\(account.account.prefix(6))… · \(account.count)") {
                            model.filterAccount = account.account
                            if !model.query.isEmpty { model.runSearch() }
                        }
                    }
                } label: {
                    filterMenuLabel(model.filterAccount.isEmpty
                                        ? "Hesap: Tümü"
                                        : "Hesap: \(model.filterAccount.prefix(6))…",
                                    systemImage: "at", active: !model.filterAccount.isEmpty)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Hesaba göre süz")

                // Tarih menüsü.
                Menu {
                    ForEach(DateRange.allCases) { range in
                        Button(range.label) {
                            model.dateRange = range
                            if !model.query.isEmpty { model.runSearch() }
                        }
                    }
                } label: {
                    filterMenuLabel(model.dateRange == .all
                                        ? "Tarih: Tümü"
                                        : "Tarih: \(model.dateRange.label)",
                                    systemImage: "calendar", active: model.dateRange != .all)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Tarih aralığına göre süz")

                FilterToggleChip(text: "Okunmadı", systemImage: "envelope.badge",
                                 isOn: model.unreadOnly) {
                    model.unreadOnly.toggle(); model.runSearch()
                }
                FilterToggleChip(text: "Bayraklı", systemImage: "flag.fill",
                                 isOn: model.flaggedOnly) {
                    model.flaggedOnly.toggle(); model.runSearch()
                }
                FilterToggleChip(text: "Yıldızlı", systemImage: "star.fill",
                                 isOn: model.pinnedOnly) {
                    model.pinnedOnly.toggle(); model.runSearch()
                }
                // Konuşmalara göre gruplama: yalnız GÖSTERİMİ değiştirir, yeniden sorgu YAPMAZ.
                FilterToggleChip(text: "Konuşmalar", systemImage: "bubble.left.and.bubble.right",
                                 isOn: model.groupByThread) {
                    model.groupByThread.toggle()
                }
                // Hızlı tarih çipleri: tek tıkla (yazmadan) aralık; aktif olan vurgulu, tekrar tıklayınca kalkar.
                ForEach(QuickDateRange.allCases, id: \.self) { kind in
                    FilterToggleChip(text: kind.label, systemImage: kind.systemImage,
                                     isOn: model.activeQuickDate == kind) {
                        model.toggleQuickDate(kind)
                    }
                }
                // En az bir filtre aktifken: tüm filtreleri/sıralamayı/gönderen daraltmasını tek tıkla
                // sıfırlayan sade (muted) çip. Sorgu metnine dokunmaz; mevcut çiplerle aynı boyutta.
                if model.hasActiveSearchFilters {
                    Button(action: model.clearSearchFilters) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle").font(.system(size: 9))
                            Text("Filtreleri temizle").font(.system(size: 11)).lineLimit(1)
                        }
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.line, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Tüm arama filtrelerini, sıralamayı ve gönderen daraltmasını sıfırlar (sorgu metni korunur)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 8)

            if model.detectedDateLabel != nil || model.searchFromLabel != nil
                || model.searchHasAttachment || model.searchAttachmentKind != nil
                || !model.expansionChips.isEmpty {
                // Algılanan filtre + sorgu-genişletme çipleri; çok sayıda olunca alt satıra sarar.
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    if let label = model.detectedDateLabel { Chip(text: label, systemImage: "calendar") }
                    if let from = model.searchFromLabel { Chip(text: from, systemImage: "person") }
                    if model.searchHasAttachment { Chip(text: "ekli", systemImage: "paperclip") }
                    if let kind = model.searchAttachmentKind {
                        Chip(text: "Ek türü: \(kind.label)", systemImage: kind.systemImage)
                    }
                    ForEach(model.expansionChips, id: \.self) { Chip(text: "+\($0)", systemImage: "plus.magnifyingglass") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.top, 8)
            }

            // Arama kutusu boşken biriken otomatik arama geçmişini göster.
            if model.query.trimmingCharacters(in: .whitespaces).isEmpty && !model.recentSearches.isEmpty {
                RecentSearchesBar()
            }

            Color.clear.frame(height: 12)

            Divider().overlay(Theme.line)

            if model.isSearching {
                // Spinner yerine sonuç satırı iskeletleri (algılanan yükleme hissi).
                SkeletonList()
            } else if model.results.isEmpty {
                EmptyStateView(content: EmptyStates.search(
                    hasIndex: model.totalCount > 0,
                    hasQuery: !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    hasFilters: model.unreadOnly || model.flaggedOnly || model.pinnedOnly
                              || !model.filterAccount.isEmpty || model.dateRange != .all
                              || model.activeQuickDate != nil),
                    action: { model.runIndex() })
            } else {
                // Sonuç sayısı + sıralama seçimi + listeyi Markdown'a dışa aktarma (yalnız sonuç varken).
                // Sayaç GÖSTERİLEN (filtreli) listeyi yansıtır.
                HStack(spacing: 8) {
                    Text("\(model.displayedResults.count) sonuç").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Spacer()
                    // Sıralama yalnız gösterimi etkiler; değişimi yeniden sorgu YAPMAZ.
                    Picker("Sırala", selection: $model.resultSort) {
                        ForEach(ResultSort.allCases, id: \.self) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
                    ListExportMenu(markdown: { model.exportSearchResults() },
                                   csv: { model.exportSearchResultsCSV() },
                                   filename: model.query.isEmpty ? "Arama sonuçları" : "Arama \(model.query)",
                                   labelText: "Sonuçları dışa aktar")
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                // Gönderen daraltma facet'leri: birden çok gönderen varsa sayılı çipler göster.
                if model.senderFacets.count > 1 {
                    SenderFacetBar()
                }
                // Toplu aksiyon çubuğu: en az bir sonuç seçiliyken listenin üstünde belirir.
                if !model.selectedResultIDs.isEmpty {
                    BulkActionBar()
                }
                List(selection: $model.selection) {
                    if model.groupByThread {
                        // Konuşmalara göre gruplu görünüm: tek üyeli gruplar normal satır;
                        // çok üyeli gruplar katlanabilir başlık + (açıkken) üye satırları.
                        ForEach(model.threadGroups) { group in
                            if group.count == 1 {
                                ResultRow(hit: group.members[0], terms: model.highlightTerms)
                                    .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                                    .listRowSeparator(.hidden)
                            } else {
                                ThreadHeaderRow(group: group)
                                    .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                                    .listRowSeparator(.hidden)
                                if model.expandedThreadKeys.contains(group.key) {
                                    ForEach(group.members) { member in
                                        ResultRow(hit: member, terms: model.highlightTerms)
                                            .listRowInsets(EdgeInsets(top: 3, leading: 28, bottom: 3, trailing: 8))
                                            .listRowSeparator(.hidden)
                                    }
                                }
                            }
                        }
                    } else {
                        ForEach(model.displayedResults) { hit in
                            ResultRow(hit: hit, terms: model.highlightTerms)
                                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .onChange(of: model.selection) { model.loadSelected() }
            }
        }
        .background(Theme.surface)
    }

    /// Ara sütunundaki Hesap/Tarih menülerinin çip görünümlü etiketi. FilterToggleChip'in görsel
    /// dilini paylaşır: varsayılan-dışı (aktif) → accent dolgu + beyaz metin; varsayılan → Theme.line
    /// dolgu + muted metin. Menü olduğunu belli eden küçük bir chevron içerir.
    private func filterMenuLabel(_ text: String, systemImage: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 9))
            Text(text).font(.system(size: 11)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 7))
        }
        .foregroundStyle(active ? .white : Theme.muted)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(active ? Theme.accent : Theme.line, in: Capsule())
    }
}

/// Arama sonuçlarındaki en sık gönderenleri sayılı çiplerle gösterir; bir çipe tıklayınca
/// o gönderene daraltır (istemci tarafı — yeniden sorgu YOK). Aktif filtre varken başta
/// belirgin bir "✕ <gönderen>" temizleme çipi görünür. Sayılar filtre öncesi kümeden gelir;
/// çok sayıda gönderende FlowLayout ile alt satıra sarar (taşma yok).
private struct SenderFacetBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            // Aktif filtre → tek dokunuşla temizleme çipi.
            if let active = model.activeSenderFilter {
                FilterToggleChip(text: "✕ \(active)", systemImage: "person.fill", isOn: true) {
                    model.applySenderFilter(nil)
                }
            }
            ForEach(model.senderFacets, id: \.value) { facet in
                let isActive = facet.value == model.activeSenderFilter
                FilterToggleChip(text: "\(facet.value) (\(facet.count))",
                                 systemImage: "person", isOn: isActive) {
                    // Aktif çipe tekrar tıklamak filtreyi kaldırır.
                    model.applySenderFilter(isActive ? nil : facet.value)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.bottom, 8)
    }
}

/// Çoklu seçim toplu aksiyon çubuğu: arama sonuç listesinin üstünde, en az bir satır seçiliyken
/// belirir. "N seçili" + toplu Yıldızla / Yıldızı kaldır + Dışa aktar (Markdown/CSV) + Tümünü seç +
/// Temizle. Dar panoda taşmasın diye düğmeler FlowLayout ile alt satıra sarar. Yalnız arama
/// sütununda kullanılır (diğer bölümleri etkilemez). Yıldız Trova-yerel — Apple Mail'e yazmaz.
private struct BulkActionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            Text("\(model.selectedResultIDs.count) seçili")
                .font(.rounded(12, .semibold)).foregroundStyle(Theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Theme.accentSoft, in: Capsule())

            Button { model.pinSelected() } label: {
                Label("Yıldızla", systemImage: "star.fill")
            }
            .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
            .help("Seçili mailleri Trova içinde yıldızla (Apple Mail'e yazmaz)")

            Button { model.unpinSelected() } label: {
                Label("Yıldızı kaldır", systemImage: "star.slash")
            }
            .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
            .help("Seçili maillerin Trova-yerel yıldızını kaldır")

            ListExportMenu(markdown: { model.exportSelectedMarkdown() },
                           csv: { model.exportSelectedCSV() },
                           filename: "Seçili sonuçlar",
                           labelText: "Dışa aktar")

            Button { model.selectAllResults() } label: {
                Label("Tümünü seç", systemImage: "checkmark.circle")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent)
            .help("Gösterilen tüm sonuçları seç")

            Button { model.clearResultSelection() } label: {
                Label("Temizle", systemImage: "xmark.circle")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.muted)
            .help("Seçimi temizle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.accentSoft.opacity(0.5))
    }
}

/// Arama kutusu boşken son yapılan aramaları tıklanabilir çipler olarak gösterir.
/// Bir çipe tıklayınca o sorgu yeniden çalıştırılır; "Temizle" tüm geçmişi siler.
private struct RecentSearchesBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SON ARAMALAR").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.faint).tracking(0.6)
                Spacer()
                Button("Temizle") { model.clearRecents() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .help("Son aramaları temizle")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.recentSearches, id: \.self) { q in
                        Button { model.runRecent(q) } label: {
                            Chip(text: q, systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(.plain)
                        .help(q)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 10)
    }
}

/// Aramayı isimle kaydetme + kayıtlıları çalıştırma/silme popover'ı (yer imi düğmesi).
private struct SavedSearchButton: View {
    @Environment(AppModel.self) private var model
    @State private var show = false
    @State private var name = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: model.savedSearches.isEmpty ? "bookmark" : "bookmark.fill")
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .help("Kayıtlı aramalar")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Aramayı kaydet").font(.rounded(13, .semibold)).foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    TextField("İsim", text: $name).textFieldStyle(.roundedBorder)
                        .onSubmit { if canSave { model.saveCurrentSearch(name: name); name = "" } }
                    Button("Kaydet") { model.saveCurrentSearch(name: name); name = "" }
                        .disabled(!canSave)
                }
                if !model.savedSearches.isEmpty {
                    Divider()
                    Text("KAYITLI").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.faint).tracking(0.6)
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(model.savedSearches) { saved in
                                HStack(spacing: 8) {
                                    Button { model.runSavedSearch(saved); show = false } label: {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(saved.name).font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(Theme.ink).lineLimit(1)
                                            Text(saved.query).font(.system(size: 10))
                                                .foregroundStyle(Theme.muted).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    // Akıllı klasör: bu kayıtlı aramanın şu anki canlı eşleşme sayısı.
                                    if let count = model.savedSearchCounts[saved.id],
                                       let badge = BadgeCount.label(count) {
                                        CountBadge(text: badge, active: false)
                                            .help("\(count) eşleşen mail")
                                    }
                                    Button { model.deleteSavedSearch(saved.id) } label: {
                                        Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(Theme.muted)
                                    }
                                    .buttonStyle(.plain).help("Sil")
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding(14).frame(width: 290)
        }
    }
}

private struct ResultRow: View {
    @Environment(AppModel.self) private var model
    let hit: SearchHit
    var terms: [String] = []          // vurgulanacak arama terimleri (AppModel.highlightTerms)

    /// Gösterilecek önizleme parçası: FTS «» işaretçileri ayıklanır, kalan metin terimlere göre
    /// en yoğun pencere seçilip vurgulanır. Terim/eşleşme yoksa düz önizlemeye yakın kalır.
    private var snippet: Snippet {
        let clean = hit.snippet
            .replacingOccurrences(of: "«", with: "")
            .replacingOccurrences(of: "»", with: "")
        return SnippetExtractor.make(body: clean, terms: terms)
    }

    /// Arama terimleriyle adı eşleşen ek(ler) — sonuçta "hangi ek tuttu" rozeti için.
    private var matchedAttachments: [String] {
        AttachmentMatch.matching(names: hit.attachments, terms: terms)
    }

    /// Bu satır toplu aksiyon için seçili mi (çoklu seçim — okuma panelindeki "açık" seçimden ayrı).
    private var isSelected: Bool { model.selectedResultIDs.contains(hit.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Çoklu seçim onay kutusu (birincil seçim yolu): kendi tıklamasını yutar → satırı
            // AÇMAZ, yalnız seçimi değiştirir. Maili açmak için satırın geri kalanına tıklanır.
            Button { model.toggleResultSelection(id: hit.id) } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.faint)
                    .frame(width: 22, height: 32)   // avatar yüksekliğiyle dikey hizala
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Seçimi kaldır" : "Toplu aksiyon için seç")
            .accessibilityLabel(isSelected ? "Seçili" : "Seç")
            Avatar(name: hit.fromName, email: hit.fromAddress, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    MessageBadges(isRead: hit.isRead, isFlagged: hit.isFlagged)
                    if model.pinnedIDs.contains(hit.id) {
                        Image(systemName: "star.fill").font(.system(size: 10))
                            .foregroundStyle(Theme.amber).help("Yıldızlı")
                    }
                    if !hit.attachments.isEmpty {
                        Image(systemName: "paperclip").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                    Text(hit.subject ?? "(konu yok)")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    if let date = hit.date {
                        Text(RelativeTime.short(date, now: Date()))
                            .font(.mono(10)).foregroundStyle(Theme.faint)
                            .help(RelativeTime.absolute(date))
                            .accessibilityLabel("Tarih: \(RelativeTime.absolute(date))")
                    }
                }
                Text(hit.fromName ?? hit.fromAddress ?? "—")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                if !hit.snippet.isEmpty {
                    Text(AttributedString(snippet: snippet))
                        .font(.system(size: 11)).lineLimit(2)
                }
                if hit.matchedInAttachment {
                    Chip(text: "ek içeriğinde", systemImage: "doc.text.magnifyingglass")
                        .padding(.top, 1)
                        .help("Bu mail, bir ekin içeriğinde aranan terimle eşleşti")
                }
                if !matchedAttachments.isEmpty {
                    MatchedAttachmentChips(names: matchedAttachments) { name in
                        model.openAttachment(named: name, messageID: hit.id)
                    }
                }
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 4)
        // Çoklu seçimde satırı hafifçe vurgula (okuma panelindeki "açık" seçimden ayrı görsel ipucu).
        .background(isSelected ? Theme.accentSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
            .stroke(isSelected ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1))
        .contextMenu {
            if let address = hit.fromAddress, !address.isEmpty {
                Button { model.composeNew(to: address) } label: {
                    Label("Yeni e-posta", systemImage: "square.and.pencil")
                }
            }
        }
    }
}

/// Çok üyeli bir konuşma grubunun (thread) katlanabilir başlık satırı. Konu (representativeSubject),
/// üye sayısı rozeti, en yeni tarih ve okunmamış varsa indigo nokta gösterir. Satıra tıklanınca
/// grup açılır/kapanır (üye satırları ResultRow olarak altında belirir). Tıklama Button ile yutulur
/// → List seçimini DEĞİŞTİRMEZ (yalnız genişletmeyi açar).
private struct ThreadHeaderRow: View {
    @Environment(AppModel.self) private var model
    let group: ThreadGrouping.ThreadGroup

    private var expanded: Bool { model.expandedThreadKeys.contains(group.key) }

    var body: some View {
        // En yeni üye başlık avatarı/yaşı için kullanılır (grup en az iki üye içerir).
        let newest = group.members[0]
        Button { model.toggleThreadExpanded(group.key) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22, height: 32)   // ResultRow onay kutusuyla aynı genişlik (hizalama)
                Avatar(name: newest.fromName, email: newest.fromAddress, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        // Grupta okunmamış mail varsa belirgin indigo nokta.
                        if group.unreadCount > 0 {
                            Circle().fill(Theme.accent).frame(width: 7, height: 7)
                                .help("\(group.unreadCount) okunmamış")
                        }
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted)
                        Text(group.representativeSubject)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                            .lineLimit(1).truncationMode(.tail)
                        CountBadge(text: "\(group.count)", active: false)
                        Spacer()
                        if let date = group.latestDate {
                            Text(RelativeTime.short(date, now: Date()))
                                .font(.mono(10)).foregroundStyle(Theme.faint)
                                .help(RelativeTime.absolute(date))
                                .accessibilityLabel("En yeni: \(RelativeTime.absolute(date))")
                        }
                    }
                    Text("\(group.count) mesaj"
                         + (group.unreadCount > 0 ? " · \(group.unreadCount) okunmamış" : ""))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .padding(.vertical, 4).padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.representativeSubject), \(group.count) mesajlık konuşma")
        .accessibilityHint(expanded ? "Konuşmayı kapat" : "Konuşmayı aç")
    }
}

/// Arama terimiyle eşleşen ek adlarını küçük tıklanabilir çiplerle gösterir (en çok 3, fazlası "+N").
/// Bir çipe dokununca o ek sahip mailden çıkarılıp sistemde açılır.
private struct MatchedAttachmentChips: View {
    let names: [String]
    let open: (String) -> Void

    private let maxVisible = 3

    var body: some View {
        HStack(spacing: 4) {
            ForEach(names.prefix(maxVisible), id: \.self) { name in
                Button { open(name) } label: {
                    Chip(text: name, systemImage: "paperclip")
                }
                .buttonStyle(.plain).help("Eki aç: \(name)")
            }
            if names.count > maxVisible {
                Chip(text: "+\(names.count - maxVisible)")
                    .help(names.dropFirst(maxVisible).joined(separator: ", "))
            }
        }
        .padding(.top, 1)
    }
}
