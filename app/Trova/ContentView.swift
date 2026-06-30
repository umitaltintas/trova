import SwiftUI
import TrovaCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoSync") private var autoSync = false
    @State private var showPalette = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar(autoSync: $autoSync)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
        } content: {
            Group {
                if model.shouldShowSetup { SetupView() }
                else if model.section == .ask { AskColumn() }
                else if model.section == .digest { DigestColumn() }
                else if model.section == .people { PeopleColumn() }
                else if model.section == .insights { InsightsColumn() }
                else if model.section == .attachments { AttachmentsColumn() }
                else { SearchColumn() }
            }
            // Kolon min'leri düşürüldü ki dar pencerede içerik sarmalanıp akabilsin (kırpılmasın).
            .navigationSplitViewColumnWidth(min: 320, ideal: 440)
        } detail: {
            ReadingPane()
                .navigationSplitViewColumnWidth(min: 340, ideal: 480)
        }
        .task { model.onAppear(); if autoSync { model.setAutoSync(true) } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshAccess(); model.refreshStatus() }
        }
        .overlay(alignment: .bottom) { ErrorBanner() }
        .background { KeyboardShortcuts(showPalette: $showPalette) }
        .sheet(isPresented: $showPalette) { CommandPaletteView().environment(model) }
        .sheet(isPresented: $model.showShortcuts) { ShortcutsSheet() }
    }
}

/// Görünmez düğmelerle global klavye kısayolları: ⌘K palet, ⌘/ kılavuz, ⌘1–6 bölümler.
private struct KeyboardShortcuts: View {
    @Environment(AppModel.self) private var model
    @Binding var showPalette: Bool

    var body: some View {
        Group {
            Button("") { showPalette.toggle() }.keyboardShortcut("k", modifiers: .command)
            Button("") { model.showShortcuts = true }.keyboardShortcut("/", modifiers: .command)
            Button("") { model.section = .ask }.keyboardShortcut("1", modifiers: .command)
            Button("") { model.section = .search }.keyboardShortcut("2", modifiers: .command)
            Button("") { model.section = .digest }.keyboardShortcut("3", modifiers: .command)
            Button("") { model.section = .people; model.selectedPersonAddress = nil }
                .keyboardShortcut("4", modifiers: .command)
            Button("") { model.section = .insights }.keyboardShortcut("5", modifiers: .command)
            Button("") { model.section = .attachments }.keyboardShortcut("6", modifiers: .command)
            // ⌥↓ / ⌥↑ ile aktif listede sonraki/önceki maile geç.
            Button("") { model.selectAdjacent(1) }.keyboardShortcut(.downArrow, modifiers: .option)
            Button("") { model.selectAdjacent(-1) }.keyboardShortcut(.upArrow, modifiers: .option)
        }
        .opacity(0).frame(width: 0, height: 0)
    }
}

/// Hata mesajını alttan gösteren, kapatılabilir şerit.
private struct ErrorBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))
            .frame(maxWidth: 560)
            .padding(14)
        }
    }
}

// MARK: - Kenar çubuğu

private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var autoSync: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Trova").font(.rounded(19, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("⌘K").font(.mono(10)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().stroke(Theme.line))
                    .help("Komut paleti")
            }
            .padding(.top, 4)

            VStack(spacing: 5) {
                ModeButton(title: "Sor", subtitle: "AI ile bul + özetle",
                           icon: "sparkles", active: model.section == .ask) { model.section = .ask }
                ModeButton(title: "Ara", subtitle: "Kelime / anlamsal",
                           icon: "magnifyingglass", active: model.section == .search) { model.section = .search }
                ModeButton(title: "Bugün", subtitle: "Brifing + yanıt bekleyenler",
                           icon: "sun.max", active: model.section == .digest,
                           badge: BadgeCount.label(model.pendingReplyCount)) { model.section = .digest }
                ModeButton(title: "Kişiler", subtitle: "En çok yazışılanlar",
                           icon: "person.2", active: model.section == .people) {
                    model.section = .people; model.selectedPersonAddress = nil
                }
                ModeButton(title: "Genel Bakış", subtitle: "İstatistik + aylık hacim",
                           icon: "chart.bar", active: model.section == .insights) { model.section = .insights }
                ModeButton(title: "Ekler", subtitle: "Ada/türe göre ara + aç",
                           icon: "paperclip", active: model.section == .attachments) { model.section = .attachments }
            }

            StatusBlock()
            FilterBlock()
            Spacer()

            HealthPill()

            Toggle(isOn: $autoSync) {
                Label("Otomatik senkron", systemImage: "bolt.fill").font(.system(size: 12))
            }
            .toggleStyle(.switch).controlSize(.mini).tint(Theme.accent)
            .disabled(!model.hasAccess)
            .onChange(of: autoSync) { _, on in model.setAutoSync(on) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Kenar çubuğunda genel sağlık durumunu renkli noktayla gösterir; tıklayınca teşhis panelini açar.
private struct HealthPill: View {
    @Environment(AppModel.self) private var model
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 7) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text("Sağlık").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "stethoscope").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
        .buttonStyle(.plain)
        .help("Kurulum ve sağlık teşhisi")
        .sheet(isPresented: $show) {
            SetupView(asSheet: true)
                .environment(model)
                .frame(width: 540, height: 560)
        }
    }

    private var dotColor: Color {
        switch model.health.overall {
        case .ok: .green
        case .warn: .orange
        case .fail: .red
        }
    }
}

private struct ModeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let active: Bool
    var badge: String? = nil          // sağa hizalı küçük sayı rozeti (nil → rozet yok)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? .white : Theme.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.rounded(14, .semibold))
                        .foregroundStyle(active ? .white : Theme.ink)
                    Text(subtitle).font(.system(size: 10))
                        .foregroundStyle(active ? Color.white.opacity(0.85) : Theme.muted)
                }
                Spacer()
                if let badge { CountBadge(text: badge, active: active) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(active ? Theme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
        .buttonStyle(.plain)
    }
}

/// Nav satırı sonundaki küçük sayı rozeti (örn. "Bugün" için yanıt-bekleyen sayısı).
/// Pasif satırda Theme.accent dolgulu beyaz metin; aktif (mavi) satırda kontrast için beyaz
/// dolgu + accent metin kullanılır. Genişlik içeriğe göre; "99+" gibi etiketlerde de bozulmaz.
private struct CountBadge: View {
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

private struct StatusBlock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.newMailCount > 0 {
                NewMailBadge(count: model.newMailCount) { model.clearNewMail() }
            }
            if model.hasAccess {
                StatRow(icon: "envelope.fill", label: "Mail", value: model.totalCount.formatted())
                StatRow(icon: "circle.hexagongrid.fill", label: "Vektör", value: model.vectorCount.formatted())
                if model.totalCount > 0 {
                    let coverage = Double(model.vectorCount) / Double(model.totalCount)
                    HStack(spacing: 8) {
                        Text("Kapsam").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        Spacer()
                        SignalBar(value: coverage, segments: 8, height: 8)
                        Text("\(Int(coverage * 100))%").font(.mono(10)).foregroundStyle(Theme.accent)
                    }
                }
            } else {
                Label("Erişim gerekli", systemImage: "lock.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack(spacing: 6) {
                ActionButton(title: "İndeksle", icon: "tray.and.arrow.down",
                             disabled: model.busy || !model.hasAccess) { model.runIndex() }
                ActionButton(title: "Gömme", icon: "wand.and.stars",
                             disabled: model.busy) { model.runEmbed() }
            }
            if model.busy {
                ProgressView(value: model.jobTotal > 0 ? Double(model.jobProcessed) : nil,
                             total: Double(max(model.jobTotal, 1)))
                    .tint(Theme.accent)
                HStack {
                    Text(model.progress).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer()
                    Button("İptal") { model.cancelJob() }
                        .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            } else if !model.progress.isEmpty {
                Text(model.progress).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2)
            }
        }
        .padding(10)
        .cardSurface()
    }
}

/// "N yeni mail" rozeti: autoSync açıkken yeni mail geldiğinde StatusBlock'ta belirir.
/// Tıklanınca sayacı sıfırlar ve açık görünümü tazeler; sayı 0 iken hiç gösterilmez (çağıran kontrol eder).
private struct NewMailBadge: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                Text("\(count) yeni mail").font(.rounded(12, .semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.clockwise").font(.system(size: 9))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Yeni gelen mailleri gör ve görünümü tazele")
    }
}

private struct StatRow: View {
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

private struct ActionButton: View {
    let title: String
    let icon: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small).buttonStyle(.bordered).tint(Theme.accent).disabled(disabled)
    }
}

private struct FilterBlock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            Text("FİLTRE").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.faint).tracking(0.6)
            Picker("Hesap", selection: $model.filterAccount) {
                Text("Tüm hesaplar").tag("")
                ForEach(model.accounts) { account in
                    Text("\(account.account.prefix(6))… · \(account.count)").tag(account.account)
                }
            }
            .labelsHidden().controlSize(.small)
            Picker("Tarih", selection: $model.dateRange) {
                ForEach(DateRange.allCases) { range in Text(range.label).tag(range) }
            }
            .labelsHidden().controlSize(.small)
        }
        .onChange(of: model.filterAccount) { if !model.query.isEmpty { model.runSearch() } }
        .onChange(of: model.dateRange) { if !model.query.isEmpty { model.runSearch() } }
    }
}

// MARK: - Ara sütunu

private struct SearchColumn: View {
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

            HStack(spacing: 6) {
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
                Spacer()
            }
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
                              || !model.filterAccount.isEmpty || model.dateRange != .all),
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
                    ForEach(model.displayedResults) { hit in
                        ResultRow(hit: hit, terms: model.highlightTerms)
                            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .onChange(of: model.selection) { model.loadSelected() }
            }
        }
        .background(Theme.surface)
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
}

// MARK: - Sor (AI) sütunu

private struct AskColumn: View {
    @Environment(AppModel.self) private var model
    @State private var showHistory = false

    private var exportedTurns: [ExportedTurn] {
        model.conversation.filter { !$0.answer.isEmpty }
            .map { ExportedTurn(question: $0.question, answer: $0.answer, citations: $0.cited) }
    }
    private var conversationTitle: String {
        model.conversation.first.map { "Trova: " + String($0.question.prefix(40)) } ?? "Trova sohbeti"
    }
    private var conversationMarkdown: String {
        MarkdownExporter.conversation(exportedTurns, title: conversationTitle)
    }

    var body: some View {
        Group {
            if model.conversation.isEmpty {
                EmptyStateView(content: EmptyStates.ask(hasIndex: model.totalCount > 0),
                               action: { model.runIndex() })
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(model.conversation) { exchange in
                                ExchangeView(exchange: exchange)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(12)
                    }
                    .onChange(of: model.conversation.count) { scrollToBottom(proxy) }
                    .onChange(of: model.conversation.last?.steps.count) { scrollToBottom(proxy) }
                    .onChange(of: model.conversation.last?.answer) { scrollToBottom(proxy) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        // Giriş çubuğunu safeAreaInset ile alta sabitleriz: boş durumda EmptyStateView tüm
        // alanı yutsa bile composer için yer rezerve edilir ve her zaman görünür kalır.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().overlay(Theme.line)
                composer
            }
            .background(Theme.surface)   // şeffaf inset değil; içerik composer ardından sızmasın
        }
        .onAppear { model.loadConversations() }
    }

    /// Mesaj giriş çubuğu (composer): metin alanı, geçmiş popover'ı, dışa aktarma menüsü,
    /// "Yeni sohbet" ile "Sor"/"İptal" düğmeleri. Ekranın altında sabit durur.
    @ViewBuilder private var composer: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            TextField(model.conversation.isEmpty
                        ? "Sor: geçen ay kira ile ilgili mailleri özetle…"
                        : "Takip sorusu sor…",
                      text: $model.question)
                .textFieldStyle(.plain).font(.system(size: 14)).onSubmit { model.runAsk() }
            Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Geçmiş sohbetler")
                .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                    ConversationHistoryList(dismiss: { showHistory = false })
                }
            if !model.conversation.isEmpty && !model.isAsking {
                if !exportedTurns.isEmpty {
                    Menu {
                        Button("Markdown kopyala") { Exporter.copy(conversationMarkdown) }
                        Button("Dışa aktar (.md)") {
                            Exporter.save(conversationMarkdown, suggestedName: conversationTitle)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .fixedSize().foregroundStyle(Theme.muted).help("Sohbeti dışa aktar")
                }
                Button { model.newConversation() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Yeni sohbet")
            }
            if model.isAsking {
                Button { model.cancelJob() } label: { Text("İptal").font(.rounded(13, .semibold)) }
                    .buttonStyle(.bordered).tint(Theme.accent)
            } else {
                Button { model.runAsk() } label: { Text("Sor").font(.rounded(13, .semibold)) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
        .padding(10).cardSurface().padding(12)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

/// Geçmiş sohbetlerin listesi: bir satıra dokununca o sohbeti yeniden açar, çöp kutusu siler.
private struct ConversationHistoryList: View {
    @Environment(AppModel.self) private var model
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 12)).foregroundStyle(Theme.accent)
                Text("Geçmiş sohbetler").font(.rounded(13, .semibold)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            Divider().overlay(Theme.line)

            if model.conversations.isEmpty {
                EmptyState(icon: "bubble.left.and.bubble.right",
                           title: "Henüz sohbet yok",
                           subtitle: "Sorduğun sohbetler burada birikir; eskilerini yeniden açabilirsin.")
                    .frame(height: 240)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.conversations) { summary in
                            ConversationRow(summary: summary,
                                            open: { model.loadConversation(summary.id); dismiss() },
                                            delete: { model.deleteConversation(summary.id) })
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 320, height: 380)
        .onAppear { model.loadConversations() }
    }
}

private struct ConversationRow: View {
    let summary: ConversationSummary
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(summary.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.mono(10)).foregroundStyle(Theme.faint)
                        Text("· \(summary.turnCount) tur").font(.mono(10)).foregroundStyle(Theme.faint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: delete) { Image(systemName: "trash").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Sohbeti sil")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))
    }
}

/// Sohbetteki tek bir tur: kullanıcı sorusu (baloncuk) + ajan izi + yanıt + kaynaklar.
private struct ExchangeView: View {
    @Environment(AppModel.self) private var model
    let exchange: AppModel.Exchange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 40)
                Text(exchange.question)
                    .font(.system(size: 13)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radius))
            }
            if !exchange.steps.isEmpty || exchange.running {
                AgentTrace(steps: exchange.steps, running: exchange.running)
            }
            if !exchange.answer.isEmpty { AnswerCard(text: exchange.answer) }
            if let verification = exchange.verification, verification.verdict != .unknown {
                VerificationBadge(verification: verification)
            }
            if !exchange.cited.isEmpty {
                ForEach(exchange.cited) { hit in
                    CitedRow(hit: hit, selected: hit.id == model.selection) {
                        model.selection = hit.id; model.loadSelected()
                    }
                }
            }
            if !exchange.answer.isEmpty && !exchange.running {
                ExportBar(
                    markdown: {
                        MarkdownExporter.answer(question: exchange.question,
                                                answer: exchange.answer, citations: exchange.cited)
                    },
                    filename: exchange.question)
            }
        }
    }
}

/// AI yanıtını (kaynaklarıyla) Markdown olarak panoya kopyalama / .md kaydetme çubuğu.
private struct ExportBar: View {
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

/// Bir mail listesini (arama sonuçları / kişi mailleri / benzer mailler) Markdown ya da CSV olarak
/// kopyalama/kaydetme için kompakt menü. Dar başlıklarda taşmaması için tek düğmedir.
private struct ListExportMenu: View {
    let markdown: () -> String
    let csv: () -> String
    let filename: String
    var labelText = "Dışa aktar"
    @State private var copied = false

    var body: some View {
        Menu {
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

/// Ajanın adım adım ne yaptığını gösteren canlı iz.
private struct AgentTrace: View {
    let steps: [AgentStep]
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                HStack(spacing: 8) {
                    Image(systemName: icon(step.kind)).font(.system(size: 11))
                        .foregroundStyle(Theme.accent).frame(width: 16)
                    Text(label(step)).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            if running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Çalışıyor…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    private func icon(_ kind: AgentStep.Kind) -> String {
        switch kind {
        case .search: "magnifyingglass"
        case .read: "doc.text"
        case .thread: "bubble.left.and.bubble.right"
        case .answer: "checkmark.seal.fill"
        case .note: "info.circle"
        }
    }
    private func label(_ step: AgentStep) -> String {
        switch step.kind {
        case .search: "Arandı: \(step.detail)"
        case .read: "Okundu: \(step.detail)"
        case .thread: "Konu incelendi: \(step.detail)"
        case .answer: "Yanıt hazırlandı"
        case .note: step.detail
        }
    }
}

private struct AnswerCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Yanıt", systemImage: "text.alignleft")
                .font(.rounded(12, .semibold)).foregroundStyle(Theme.accent)
            // Blok-düzeyi markdown (başlık/liste/kod) render edilir; satır-içi de korunur.
            MarkdownText(text, baseSize: 13)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// Yanıtın kaynaklarla ne ölçüde desteklendiğini gösteren küçük rozet (self-critique).
private struct VerificationBadge: View {
    let verification: Verification

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(tint)
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(tint)
            }
            ForEach(Array(verification.issues.enumerated()), id: \.offset) { _, issue in
                Text("• \(issue)").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: String {
        switch verification.verdict {
        case .grounded: "checkmark.seal.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .unsupported: "xmark.seal.fill"
        case .unknown: "questionmark.circle"
        }
    }
    private var label: String {
        switch verification.verdict {
        case .grounded: "Kaynaklarla doğrulandı"
        case .partial: "Bazı iddialar kısmen destekli"
        case .unsupported: "İddialar kaynaklarla desteklenmiyor"
        case .unknown: ""
        }
    }
    private var tint: Color {
        switch verification.verdict {
        case .grounded: .green
        case .partial: .orange
        case .unsupported: .red
        case .unknown: Theme.muted
        }
    }
}

private struct CitedRow: View {
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

// MARK: - Kişiler sütunu

private struct PeopleColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            if let address = model.selectedPersonAddress {
                PersonDetailHeader(address: address)
                Divider().overlay(Theme.line)
                personMails
            } else {
                header
                // Liste görünümünde ada/adrese göre canlı süzme (kişi detayındayken gizli).
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Kişi ara (ad/adres)…", text: $model.peopleQuery)
                        .textFieldStyle(.plain).font(.system(size: 14))
                        .onSubmit { model.loadPeople() }
                    if !model.peopleQuery.isEmpty {
                        Button { model.peopleQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint)
                        }
                        .buttonStyle(.plain).help("Aramayı temizle")
                    }
                }
                .padding(10).cardSurface().padding(.horizontal, 12).padding(.bottom, 12)
                .onChange(of: model.peopleQuery) { model.loadPeople() }

                Divider().overlay(Theme.line)
                peopleList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
        .task { if model.people.isEmpty { model.loadPeople() } }
    }

    private var header: some View {
        HStack {
            Text("Kişiler").font(.rounded(18, .bold)).foregroundStyle(Theme.ink)
            Spacer()
            if !model.people.isEmpty {
                Text("\(model.people.count) kişi").font(.mono(11)).foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var peopleList: some View {
        if model.people.isEmpty {
            EmptyStateView(content: EmptyStates.people(
                hasIndex: model.totalCount > 0,
                hasQuery: !model.peopleQuery.trimmingCharacters(in: .whitespaces).isEmpty),
                           action: { model.runIndex() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.people) { person in
                        PersonRow(person: person) { model.selectPerson(person.address) }
                    }
                }
                .padding(12)
            }
        }
    }

    private var personMails: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(model.personMails) { hit in
                    CitedRow(hit: hit, selected: hit.id == model.selection) {
                        model.selection = hit.id; model.loadSelected()
                    }
                }
            }
            .padding(12)
        }
    }
}

private struct PersonDetailHeader: View {
    @Environment(AppModel.self) private var model
    let address: String

    private var person: SenderStat? { model.people.first { $0.address == address } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    model.selectedPersonAddress = nil
                    model.personMails = []
                    model.personDetail = nil
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent).help("Kişilere dön")
                Avatar(name: person?.name, email: address, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person?.name ?? address).font(.rounded(14, .semibold))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    if person?.name != nil {
                        Text(address).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer()
                if !model.personMails.isEmpty {
                    ListExportMenu(markdown: { model.exportPersonMails() },
                                   csv: { model.exportPersonMailsCSV() },
                                   filename: person?.name ?? address)
                }
                Button { model.composeNew(to: address) } label: {
                    Label("Yeni e-posta", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
                .help("Bu kişiye yeni e-posta oluştur (Mail.app penceresi açılır; gönderme yok)")
            }

            if let detail = model.personDetail {
                // İstatistik çipleri dar kişi panosunda taşmasın diye sarmalanır.
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    Chip(text: "\(detail.total) mail", systemImage: "envelope")
                    if detail.withAttachments > 0 {
                        Chip(text: "\(detail.withAttachments) ekli", systemImage: "paperclip")
                    }
                    if let first = detail.firstDate, let last = detail.lastDate {
                        let now = Date()
                        Chip(text: "\(RelativeTime.format(first, now: now)) – \(RelativeTime.format(last, now: now))",
                             systemImage: "calendar")
                            .help("\(RelativeTime.absolute(first)) – \(RelativeTime.absolute(last))")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
    }
}

private struct PersonRow: View {
    @Environment(AppModel.self) private var model
    let person: SenderStat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(name: person.name, email: person.address, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name ?? person.address).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    if person.name != nil {
                        Text(person.address).font(.system(size: 10))
                            .foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer()
                Text("\(person.count)").font(.mono(11)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accentSoft, in: Capsule())
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { model.composeNew(to: person.address) } label: {
                Label("Yeni e-posta", systemImage: "square.and.pencil")
            }
        }
    }
}

// MARK: - Bugün (proaktif asistan) sütunu

private struct DigestColumn: View {
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

// MARK: - Okuma paneli

private struct ReadingPane: View {
    @Environment(AppModel.self) private var model
    @State private var formatted = true

    var body: some View {
        @Bindable var model = model
        content
            .sheet(isPresented: $model.showSimilarSheet) {
                SimilarMailsSheet().environment(model)
            }
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
                            Button { model.openAttachment(named: name) } label: {
                                Chip(text: name, systemImage: "paperclip")
                            }
                            .buttonStyle(.plain).help("Eki aç")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Eylem düğmeleri de sarmalanır: pano daralınca düğmeler ekran dışında
                    // kalıp kırpılmaz, otomatik olarak bir alt satıra geçer.
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        Button {
                            Exporter.copy(MarkdownExporter.email(hit, body: model.selectedBody))
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("Maili Markdown olarak panoya kopyala")
                        Button { model.composeReply() } label: {
                            Label("Yanıtla", systemImage: "arrowshape.turn.up.left")
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
                        .disabled((hit.fromAddress ?? "").isEmpty)
                        .help("Bu maile Mail.app'te yanıt oluştur (gönderme yok; yalnız pencere açılır)")
                        Button { model.openInMail() } label: {
                            Label("Mail'de Aç", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
                        .disabled(MailLink.appleMailURL(messageID: model.selectedMessageID) == nil)
                        .help("Bu maili Apple Mail.app'te aç (yanıtlamak/işlem yapmak için)")
                        // Trova-yerel yıldızla/yıldızı kaldır (Apple Mail'e YAZMAZ; anahtar message.id).
                        let pinned = model.pinnedIDs.contains(hit.id)
                        Button { model.togglePin(id: hit.id) } label: {
                            Label(pinned ? "Yıldızı kaldır" : "Yıldızla",
                                  systemImage: pinned ? "star.fill" : "star")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(pinned ? Theme.amber : Theme.accent)
                        .help(pinned ? "Bu mailin Trova-yerel yıldızını kaldır"
                                     : "Bu maili Trova içinde yıldızla (Apple Mail'e yazmaz)")
                        Button { model.loadSimilar(messageID: hit.id) } label: {
                            Label("Benzer mailler", systemImage: "square.stack.3d.up")
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
                        .help("Bu maile embedding'e göre anlamsal olarak en benzer mailleri bul")
                        Button { model.generateReplyDraft() } label: {
                            Label("Yanıt taslağı", systemImage: "pencil.and.outline")
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
                        .disabled((hit.fromAddress ?? "").isEmpty || model.isDraftingReply)
                        .help("Bu maile LLM ile kısa, nazik bir Türkçe yanıt taslağı üret")
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
                    HTMLView(html: html)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line))
                        .padding(12)
                } else {
                    ScrollView {
                        Text(model.selectedBody?.isEmpty == false ? model.selectedBody! : hit.snippet)
                            .font(.system(size: 13)).foregroundStyle(Theme.ink).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }
                }

                if model.selectedThread.count > 1 {
                    Divider().overlay(Theme.line)
                    ThreadStrip()
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

private struct ThreadStrip: View {
    @Environment(AppModel.self) private var model

    private var showSummary: Bool {
        model.threadSummary != nil && model.summaryThreadKey == model.selectedHit?.threadKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("BU KONUDA \(model.selectedThread.count) MAIL")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint).tracking(0.6)
                Spacer()
                if model.isSummarizing {
                    ProgressView().controlSize(.small)
                } else {
                    Button { model.summarizeThread() } label: {
                        Label("Konuyu özetle", systemImage: "text.append")
                    }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)

            if showSummary, let summary = model.threadSummary {
                ThreadSummaryCard(summary: summary)
                    .padding(.horizontal, 16).padding(.vertical, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.selectedThread) { message in
                        Button {
                            model.selection = message.id
                            model.loadSelected()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.fromName ?? message.fromAddress ?? "—")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                if let date = message.date {
                                    Text(RelativeTime.short(date, now: Date()))
                                        .font(.mono(9)).foregroundStyle(Theme.muted)
                                        .help(RelativeTime.absolute(date))
                                        .accessibilityLabel("Tarih: \(RelativeTime.absolute(date))")
                                }
                            }
                            .padding(8).frame(width: 132, alignment: .leading)
                            .background(message.id == model.selection ? Theme.accentSoft : Theme.card,
                                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
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

// MARK: - Ekler sütunu

/// Tüm e-posta eklerini ada/türe göre arayıp tek tıkla açan 6. bölüm.
private struct AttachmentsColumn: View {
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
                                              openInMail: { model.openRowInMail(row) })
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Theme.surface)
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
    let openInMail: () -> Void

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
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Eki aç: \(row.fileName)")
        .contextMenu {
            Button { open() } label: { Label("Eki aç", systemImage: "arrow.up.right.square") }
            Button { openInMail() } label: { Label("Mail'de Aç", systemImage: "arrow.up.forward.app") }
        }
    }
}

// MARK: - Erişim kapısı

