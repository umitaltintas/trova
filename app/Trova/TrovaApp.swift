import SwiftUI

@main
struct TrovaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1200, height: 780)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
