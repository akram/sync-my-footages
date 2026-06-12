import SwiftUI

@main
struct SyncMyFootagesApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appState)
        } label: {
            Label("Sync My Footages", systemImage: appState.menuBarIconName)
        }
        .menuBarExtraStyle(.window)
    }
}
