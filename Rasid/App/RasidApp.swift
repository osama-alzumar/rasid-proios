import SwiftUI

@main
struct RasidApp: App {
    @StateObject private var model = AppModel.make()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.brand)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.syncSoon() }
        }
    }
}
