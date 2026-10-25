import SwiftUI

@main
struct DuoNotesApp: App {
    @State private var store = NotebookStore()
    @State private var settings = SettingsStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(settings)
                .preferredColorScheme(settings.pen.appearance.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushSaves() }
        }
    }
}
