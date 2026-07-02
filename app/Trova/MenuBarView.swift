import SwiftUI
import AppKit
import TrovaCore

/// Menü çubuğu eki penceresi (`MenuBarExtra` `.window` stili). Kompakt (~300pt) ve Indigo Console
/// diline uygun: üstte durum özeti, ortada hızlı arama, altta tek-tık eylemler. Tamamı Türkçe.
/// Ana pencereyle aynı `AppModel` örneğini paylaşır; buradan tetiklenen arama/indeksleme ana
/// pencereye yansır.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @AppStorage("menuBarExtra") private var menuBarExtra = true
    @State private var quickQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            searchField
            actions
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - Üst satır (başlık + durum)

    private var header: some View {
        HStack(spacing: 8) {
            Text("Trova").font(.rounded(15, .semibold)).foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            statusPill
        }
    }

    /// Sağdaki durum göstergesi: erişim yoksa turuncu uyarı, yeni mail varsa accent kapsül,
    /// değilse toplam mail sayısı (muted).
    @ViewBuilder private var statusPill: some View {
        if !model.hasAccess {
            Label("Erişim gerekli", systemImage: "lock.fill")
                .font(.system(size: 11)).foregroundStyle(.orange)
        } else if model.newMailCount > 0 {
            Text("\(model.newMailCount) yeni mail")
                .font(.rounded(11, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.accent, in: Capsule())
        } else {
            Text("\(model.totalCount.formatted()) mail")
                .font(.mono(11)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Hızlı arama

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11)).foregroundStyle(Theme.faint)
            TextField("Hızlı ara…", text: $quickQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(runQuickSearch)
                .accessibilityLabel("Hızlı arama")
                .accessibilityHint("Ana pencerede arama yapar")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: - Eylemler

    private var actions: some View {
        VStack(spacing: 2) {
            MenuActionButton(title: "Trova'yı Aç", systemImage: "macwindow") {
                bringMainWindowForward()
                dismiss()
            }
            .accessibilityHint("Ana pencereyi öne getirir")

            MenuActionButton(title: "Bugün brifingi", systemImage: "sun.max") {
                bringMainWindowForward()
                model.section = .digest
                dismiss()
            }
            .accessibilityHint("Bugün brifingini ana pencerede açar")

            indexRow

            Divider().padding(.vertical, 4)

            MenuActionButton(title: "Menü çubuğundan kaldır", systemImage: "menubar.rectangle") {
                menuBarExtra = false
            }
            .help("Ayarlar → Genel'den geri açılabilir")

            MenuActionButton(title: "Çıkış", systemImage: "power") {
                NSApp.terminate(nil)
            }
            .help("Trova'dan çık")
        }
    }

    /// İndeksleme satırı: çalışırken ilerleme + İptal; boştayken "İndeksle" düğmesi.
    /// İndeksleme başlatınca menü açık kalır ki kullanıcı ilerlemeyi burada görebilsin.
    @ViewBuilder private var indexRow: some View {
        if model.busy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.progress.isEmpty ? "İndeksleniyor…" : model.progress)
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer(minLength: 0)
                Button("İptal") { model.cancelJob() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        } else {
            MenuActionButton(title: "İndeksle", systemImage: "tray.and.arrow.down") {
                model.runIndex()
            }
            .disabled(!model.hasAccess)
            .accessibilityHint("Yeni mailleri indekslemeye başlar")
        }
    }

    // MARK: - Davranış

    /// Hızlı arama gönderilince: ana pencereyi öne getir, Ara bölümüne geç, sorguyu çalıştır,
    /// alanı temizle ve menü penceresini kapat.
    private func runQuickSearch() {
        let text = quickQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        bringMainWindowForward()
        model.section = .search
        model.query = text
        model.runSearch()
        quickQuery = ""
        dismiss()
    }

    /// Ana içerik penceresini öne getirir. Zaten açıksa (WindowGroup(id:"ana") penceresinin
    /// geri-yükleme kimliği "ana" ile başlar) onu öne alır; kapalıysa yeni pencere açar. Her
    /// durumda uygulamayı öne getirir.
    private func bringMainWindowForward() {
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix("ana") == true
        }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "ana")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Menü penceresindeki tek satırlık eylem düğmesi: soldan ikon + başlık, üzerine gelince
/// hafif accent vurgusu (yerel menü hissi). Plain stil; devre dışıyken soluklaşır.
private struct MenuActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13)).frame(width: 18)
                    .foregroundStyle(isEnabled ? Theme.accent : Theme.faint)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isEnabled ? Theme.ink : Theme.faint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering && isEnabled ? Theme.accentSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
