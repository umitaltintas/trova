import SwiftUI
import TrovaCore

// MARK: - Kenar çubuğu (UI v2)

/// Yerel macOS kenar çubuğu: `List(selection:)` + `.listStyle(.sidebar)`.
///
/// UI v2 gerekçesi: Eski özel VStack/ScrollView tabanlı kenar çubuğu (iki satırlı ModeButton'lar,
/// StatusBlock, FilterBlock, HealthPill) kısa pencerede kırpılıyordu ve NSSplitView/NSScrollView
/// autosave durumuyla sürekli çatışıyordu. Yerel `List(.sidebar)` kaydırmayı, vibrancy malzemesini
/// ve seçim vurgusunu AppKit ile uyumlu biçimde KENDİSİ yönetir; kısa pencerede kırpılma sınıfı
/// sorunlar yapısal olarak ortadan kalkar. Eski iki satırlı ModeButton'lar tek satır `Label`'a indi;
/// alt açıklamalar `.help` ipucuna taşındı. Filtreler yalnız aramayı etkilediğinden Ara sütununa,
/// durum bilgisi de alttaki sabit `SidebarFooter`'a taşındı.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var autoSync: Bool

    /// `List` seçimi opsiyonel ister; `model.section` ise zorunlu. Bu köprü, seçim değişince
    /// bölümü günceller ve "Kişiler"e geçişte açık kişi detayını sıfırlar (eski ModeButton davranışı).
    private var selection: Binding<AppModel.Section?> {
        Binding(get: { model.section },
                set: { if let v = $0 {
                    model.section = v
                    if v == .people { model.selectedPersonAddress = nil }
                }})
    }

    var body: some View {
        List(selection: selection) {
            Section {
                Label("Sor", systemImage: "sparkles").tag(AppModel.Section.ask)
                    .help("AI ile bul + özetle")
                Label("Ara", systemImage: "magnifyingglass").tag(AppModel.Section.search)
                    .help("Kelime / anlamsal arama")
                Label("Bugün", systemImage: "sun.max").tag(AppModel.Section.digest)
                    .badge(model.pendingReplyCount)
                    .help("Brifing + yanıt bekleyenler")
                Label("Kişiler", systemImage: "person.2").tag(AppModel.Section.people)
                    .help("En çok yazışılanlar")
                Label("Genel Bakış", systemImage: "chart.bar").tag(AppModel.Section.insights)
                    .help("İstatistik + aylık hacim")
                Label("Ekler", systemImage: "paperclip").tag(AppModel.Section.attachments)
                    .help("Ada/türe göre ara + aç")
            }

            // Akıllı Klasörler: sabit sanal klasörler (Okunmamışlar/Yıldızlılar) + kayıtlı aramalar.
            // Section artık HER ZAMAN görünür — sanal klasörler kalıcıdır; kayıtlı aramalar da
            // altlarına eklenir (boşken ForEach doğal olarak hiçbir satır üretmez).
            // Satırlar `.tag`'siz Button — böylece nav Label'larının List seçimine karışmazlar
            // (tıklama section'ı .search yapar, "Ara" satırı doğal olarak seçili görünür). Sanal
            // satırların sağ tık menüsü YOK: silinemezler.
            Section("Akıllı Klasörler") {
                Button {
                    model.openVirtualUnread()
                } label: {
                    Label("Okunmamışlar", systemImage: "envelope.badge")
                }
                .buttonStyle(.plain)
                // Canlı okunmamış sayısı; 0 iken yerel `.badge` kendiliğinden gizlenir.
                .badge(model.unreadTotal)
                .help("Okunmamış mailleri göster")

                Button {
                    model.openVirtualPinned()
                } label: {
                    Label("Yıldızlılar", systemImage: "star")
                }
                .buttonStyle(.plain)
                // Trova-yerel yıldızlı (pinned) sayısı; 0 iken badge gizlenir.
                .badge(model.pinnedIDs.count)
                .help("Trova-yerel yıldızlı mailleri göster")

                ForEach(model.savedSearches) { saved in
                    Button {
                        model.runSavedSearch(saved)
                        model.section = .search
                    } label: {
                        Label(saved.name, systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.plain)
                    // Canlı eşleşme sayısı; 0 iken yerel `.badge` kendiliğinden gizlenir.
                    .badge(model.savedSearchCounts[saved.id] ?? 0)
                    .help("Kayıtlı aramayı çalıştır: \(saved.name)")
                    .contextMenu {
                        Button("Çalıştır") {
                            model.runSavedSearch(saved)
                            model.section = .search
                        }
                        Button("Sil", role: .destructive) { model.deleteSavedSearch(saved.id) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Alt durum bloğu kaydırmanın DIŞINDA kalır → kısa pencerede bile hep görünür.
        .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFooter(autoSync: $autoSync) }
        // Kenar çubuğu görününce kayıtlı aramaları + canlı sayaçlarını mevcut yenileyiciyle tazele.
        .task { model.loadSavedSearches() }
    }
}

/// Kenar çubuğunun altındaki kompakt, sabit durum bloğu: yeni mail rozeti, iş ilerlemesi/iptali,
/// sağlık noktası + toplam mail sayısı + otomatik senkron anahtarı, ve vektör kapsam satırı.
/// Eski StatusBlock + HealthPill'in yerini alır; `.bar` malzemesiyle yerel bir alt çubuk hissi verir.
struct SidebarFooter: View {
    @Environment(AppModel.self) private var model
    @Binding var autoSync: Bool
    @State private var showHealth = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.line)

            VStack(alignment: .leading, spacing: 8) {
                if model.newMailCount > 0 {
                    NewMailBadge(count: model.newMailCount) { model.clearNewMail() }
                }

                // İş ilerlemesi/iptali (yalnız çalışırken); değilse son durum metni (varsa).
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

                // Ana satır: sağlık noktası + toplam mail (ya da erişim uyarısı) + otomatik senkron.
                HStack(spacing: 8) {
                    Button { showHealth = true } label: {
                        Circle().fill(healthColor).frame(width: 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .help("Kurulum ve sağlık teşhisi")
                    .accessibilityLabel("Sağlık: \(healthLabel)")

                    if model.hasAccess {
                        Text(model.totalCount.formatted() + " mail")
                            .font(.mono(11)).foregroundStyle(Theme.ink)
                    } else {
                        Label("Erişim gerekli", systemImage: "lock.fill")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }

                    Spacer()

                    // Yalnız bolt.fill ikonlu otomatik senkron anahtarı (metin etiketi yok;
                    // açıklama .help ipucunda). İkon anahtarın etiketi olduğundan labelsHidden YOK.
                    Toggle(isOn: $autoSync) {
                        Image(systemName: "bolt.fill").font(.system(size: 11))
                    }
                    .toggleStyle(.switch).controlSize(.mini).tint(Theme.accent)
                    .disabled(!model.hasAccess)
                    .help("Otomatik senkron")
                    .onChange(of: autoSync) { _, on in model.setAutoSync(on) }
                }

                // İkincil satır: vektör sayısı + gömme kapsamı (yalnız erişim + indeks varken).
                if model.hasAccess && model.totalCount > 0 {
                    Text("\(model.vectorCount.formatted()) vektör · %\(coveragePercent) gömme")
                        .font(.mono(10)).foregroundStyle(Theme.muted).lineLimit(1)
                }

                // Otomatik gömme sürüyorsa (busy'den ayrı, UI'ı kilitlemez) tek satırlık sessiz ibare.
                if model.autoEmbedding && !model.busy {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(model.autoEmbedRemaining > 0
                             ? "Otomatik gömülüyor · \(model.autoEmbedRemaining.formatted()) kaldı"
                             : "Otomatik gömülüyor…")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(.bar)
        .sheet(isPresented: $showHealth) {
            SetupView(asSheet: true)
                .environment(model)
                .frame(width: 540, height: 560)
        }
    }

    /// Gömme kapsamı yüzdesi (vektör / toplam mail). Çağıran totalCount > 0 olduğunu garanti eder.
    private var coveragePercent: Int {
        Int((Double(model.vectorCount) / Double(model.totalCount) * 100).rounded())
    }

    private var healthColor: Color {
        switch model.health.overall {
        case .ok: .green
        case .warn: .orange
        case .fail: .red
        }
    }
    private var healthLabel: String {
        switch model.health.overall {
        case .ok: "iyi"
        case .warn: "uyarı"
        case .fail: "sorun"
        }
    }
}

/// "N yeni mail" rozeti: autoSync açıkken yeni mail geldiğinde alt blokta belirir. Tıklanınca
/// sayacı sıfırlar ve açık görünümü tazeler; sayı 0 iken hiç gösterilmez (çağıran kontrol eder).
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
