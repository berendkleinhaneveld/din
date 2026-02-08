import SwiftUI
import UniformTypeIdentifiers

@main
struct BoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(manager: .shared)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 320, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    Self.showOpenPanel(replace: true)
                }
                .keyboardShortcut("o")

                Button("Add to Playlist...") {
                    Self.showOpenPanel(replace: false)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }

    static func showOpenPanel(replace: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK else { return }
        if replace {
            PlaylistManager.shared.replacePlaylist(urls: panel.urls)
        } else {
            PlaylistManager.shared.addTracks(urls: panel.urls)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            PlaylistManager.shared.replacePlaylist(urls: urls)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        return false
    }
}
