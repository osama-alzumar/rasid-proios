import SwiftUI

@main
struct RasidApp: App {
    @StateObject private var model = AppModel.make()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .overlay { if model.isLocked { LockView() } }
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.brand)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: if !model.isLocked { model.syncSoon() }
            case .background: model.lockIfNeeded()
            default: break
            }
        }
    }
}
