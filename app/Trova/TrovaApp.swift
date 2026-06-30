import SwiftUI

@main
struct TrovaApp: App {
    @State private var model = AppModel()

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
