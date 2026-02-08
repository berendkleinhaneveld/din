import SwiftUI

@main
struct BoxApp: App {
    @StateObject private var manager = PlaylistManager()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 320, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
