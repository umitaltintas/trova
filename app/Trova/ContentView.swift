import SwiftUI
import AppKit
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
            .navigationSplitViewColumnWidth(min: 300, ideal: 440)
        } detail: {
            ReadingPane()
                .navigationSplitViewColumnWidth(min: 300, ideal: 480)
        }
        // Birincil eylemler artık standart macOS toolbar'ında (.primaryAction → başlık çubuğunun
        // sağ üstü). Böylece AppKit'in sol-üstte trafik ışıkları için ayırdığı alana çakışmazlar;
        // pencere de gerçek bir başlık çubuğuna kavuşur (içerik trafik ışıklarının altına kaymaz).
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.runIndex() } label: {
                    Label("İndeksle", systemImage: "tray.and.arrow.down")
                }
                .disabled(model.busy || !model.hasAccess)
                .help("Yeni mailleri indeksle")

                Button { model.runEmbed() } label: {
                    Label("Gömme", systemImage: "wand.and.stars")
                }
                .disabled(model.busy)
                .help("Vektör gömmelerini üret")

                // Komut paleti düğmesi (⌘K kısayolu KeyboardShortcuts'ta zaten tanımlı; burada
                // yalnız görünür bir tetikleyici — eski kenar çubuğu ⌘K kapsülünün yerini alır).
                Button { showPalette = true } label: {
                    Label("Komut paleti", systemImage: "command")
                }
                .help("Komut paleti (⌘K)")
            }
        }
        // NOT: Çalışma-zamanı NSSplitView autosave düzeltmesi (eski `SplitViewAutosaveFixer`)
        // KASITLI OLARAK KALDIRILDI — geri eklemeyin. O yardımcı, eski özel VStack/ScrollView
        // kenar çubuğu için yazılmıştı; yerel `List(.sidebar)` ise kendi NSScrollView yerleşimini
        // AppKit ile uyumlu biçimde kendisi yönetir. Fixer HER SwiftUI güncellemesinde
        // `adjustSubviews()` çağırıyordu; veri yükleyen sütunlar (Sor/Ara) model'i sık
        // güncellediğinde bu, kenar çubuğunun iç yerleşimini sürekli sıfırlayıp satırları GÖRÜNMEZ
        // yapıyordu (kenar çubuğu bomboş kalıyordu). Bayat "NSSplitView Subview Frames …"
        // autosave'inin pencere kurulmadan ÖNCE silinmesi olan asıl açılış-anı koruması ise
        // `TrovaApp.init()` içinde DURUYOR ve tek başına yeterli.
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
