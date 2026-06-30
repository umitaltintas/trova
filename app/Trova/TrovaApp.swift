import SwiftUI

@main
struct TrovaApp: App {
    @State private var model = AppModel()

    init() {
        // KÖK NEDEN DÜZELTMESİ: AppKit, NSSplitView'lerin alt-görünüm yüksekliklerini otomatik
        // kayıt (autosave) ile UserDefaults'a "NSSplitView Subview Frames …" anahtarlarıyla yazar.
        // Önceki bir pencere/ekran boyutundan kalma bozuk bir kayıt varsa (ör. 1526pt'lik bir
        // yükseklik, ama gerçek pencere 572pt), pencere ilk açıldığı anda — ContentView'deki
        // koşulsuz çalışma zamanı düzeltmesi devreye girmeden ÖNCE — AppKit bu bozuk değeri okuyup
        // kenar çubuğunu tamamen görünüm alanı dışına taşıyabilir (kenar çubuğu boş görünür).
        // Bunu kökünden önlemek için uygulama başlarken bu önekle başlayan TÜM kayıtlı anahtarları
        // proaktif olarak siliyoruz; böylece bozuk bir geçmiş kaydı asla okunmaz.
        let defaults = UserDefaults.standard
        let staleSplitViewKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("NSSplitView Subview Frames ")
        }
        for key in staleSplitViewKeys { defaults.removeObject(forKey: key) }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                // Pencere min boyutu: kısa ekranlarda da çalışsın diye yükseklik 520'ye çekildi.
                // Kenar çubuğu içeriği ScrollView içinde olduğundan bu boyutta kırpılmaz, kaydırılır;
                // kolon min'leri (200+300+300=800 ≤ 820) bu genişlikte üç sütunun da sığmasını sağlar.
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1200, height: 780)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
