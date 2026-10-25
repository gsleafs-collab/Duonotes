import SwiftUI

@main
struct DuoNotesApp: App {
    @State private var store = NotebookStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
        }
    }
}
