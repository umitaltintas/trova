import SwiftUI

@main
struct TrovaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                // Pencere min boyutu küçültüldü: küçük ekranlarda da içerik kırpılmadan
                // yeniden akar (kolon min'leri + sarmalayan düğme/çip satırları sayesinde).
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 780)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
